#!/usr/bin/env bash
# Rotate the sankey-export Nextcloud account's app password.
#
# The one step this can't do is minting the new token -- a Nextcloud app
# password cannot mint another (a deliberate Nextcloud boundary), and the
# only things that can (occ on the homeserver, or the account's login
# password) aren't reachable from here by design. So mint it yourself
# first, on the homeserver:
#
#   docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:add \
#     --user sankey-export --name "rotate-$(date +%F)"
#
# then run this with the printed token:
#
#   scripts/rotate-sankey-export-app-password.sh 'the-new-token'
#   scripts/rotate-sankey-export-app-password.sh -   # read token from stdin
#
# It merges the token into the k3s-apps/sankey-export secret
# (put-secret-value -- the blessed out-of-band write for these
# container-only secrets, see bootstrap/secrets-manager), runs
# `terraform apply` to roll the Kubernetes Secret, waits for the next
# CronJob run to prove the new token works, and prints how to revoke the
# old token. It never touches the old token itself -- both stay valid
# until you delete the old one, so there's no blackout window.
#
# Needs, none of which it sets up: an `aws login` session with
# PutSecretValue on k3s-apps/sankey-export (julian's own operator
# identity has it), the SSH tunnel + kubeconfig `terraform apply` here
# already needs (see README's "Running it from your laptop"), and `jq`.

set -euo pipefail

secret_id="k3s-apps/sankey-export"
json_key="sankey_export_app_password"
region="eu-central-1"

fail() {
  echo "rotate-sankey-export-app-password: $1" >&2
  exit 1
}

[ $# -eq 1 ] || fail "usage: $(basename "$0") <new-token>|-"
command -v jq >/dev/null || fail "jq not found"
command -v aws >/dev/null || fail "aws not found"
command -v terraform >/dev/null || fail "terraform not found"

new_token="$1"
if [ "${new_token}" = "-" ]; then
  new_token="$(cat)"
fi
new_token="${new_token#"${new_token%%[![:space:]]*}"}" # ltrim
new_token="${new_token%"${new_token##*[![:space:]]}"}" # rtrim
[ -n "${new_token}" ] || fail "empty token"
case "${new_token}" in
  *[[:space:]]*) fail "token contains whitespace -- paste just the token string" ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "${script_dir}")"
cd "${repo_root}"

echo "==> reading the current ${secret_id} value"
current_json="$(aws secretsmanager get-secret-value \
  --secret-id "${secret_id}" --region "${region}" \
  --query SecretString --output text)" \
  || fail "get-secret-value failed (aws login expired? wrong identity?)"

echo "${current_json}" | jq -e --arg k "${json_key}" 'has($k)' >/dev/null \
  || fail "current secret has no \"${json_key}\" key -- aborting rather than guessing"

if [ "$(echo "${current_json}" | jq -r --arg k "${json_key}" '.[$k]')" = "${new_token}" ]; then
  fail "the new token is identical to the current one -- nothing to rotate"
fi

new_json="$(echo "${current_json}" | jq --arg k "${json_key}" --arg v "${new_token}" '.[$k] = $v')"

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
printf '%s' "${new_json}" > "${tmp}"

echo "==> writing the new token into ${secret_id}"
aws secretsmanager put-secret-value \
  --secret-id "${secret_id}" --region "${region}" \
  --secret-string "file://${tmp}" \
  --query VersionId --output text >/dev/null \
  || fail "put-secret-value failed"

echo "==> terraform apply (rolls kubernetes_secret_v1.sankey_export_app_password)"
echo "    review the plan -- it should touch only module.sankey_export's app-password Secret"
terraform init -input=false >/dev/null
terraform apply

echo "==> waiting for the next sankey-export CronJob run to finish (up to 3 min)"
deadline=$(( $(date +%s) + 180 ))
last_seen=""
while [ "$(date +%s)" -lt "${deadline}" ]; do
  newest="$(kubectl get pods -l app=sankey-export \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{range .items[-1:]}{.metadata.name}{" "}{.status.phase}{end}' 2>/dev/null || true)"
  if [ -n "${newest}" ] && [ "${newest}" != "${last_seen}" ]; then
    echo "    ${newest}"
    last_seen="${newest}"
  fi
  case "${newest}" in
    *" Succeeded") echo "==> new token works -- the CronJob completed."; ok=1; break ;;
    *" Failed")    echo "==> newest run FAILED -- check its logs before revoking anything:"; \
                   echo "    kubectl logs $(echo "${newest}" | cut -d' ' -f1)"; ok=0; break ;;
  esac
  sleep 5
done
: "${ok:=0}"

echo
if [ "${ok}" = "1" ]; then
  echo "Rotation applied and verified. Now revoke the OLD token on the homeserver:"
else
  echo "Could not confirm a successful run in time. Check the CronJob before revoking:"
  echo "  kubectl get pods -l app=sankey-export --sort-by=.metadata.creationTimestamp"
fi
cat <<'EOF'
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:list --user sankey-export
  # delete every entry EXCEPT the one you just minted for this rotation:
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:delete --user sankey-export <OLD_ID>
EOF
