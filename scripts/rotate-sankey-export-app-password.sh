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
#     --name "rotate-$(date +%F)" -- sankey-export
#
# then give it the printed token. Default is a silent prompt -- nothing
# echoed, nothing in shell history:
#
#   scripts/rotate-sankey-export-app-password.sh          # prompts silently
#   scripts/rotate-sankey-export-app-password.sh -        # read from a pipe
#   scripts/rotate-sankey-export-app-password.sh 'token'  # arg (lands in history)
#
# It merges the token into the k3s-apps/sankey-export secret
# (put-secret-value -- the blessed out-of-band write for these
# container-only secrets, see bootstrap/secrets-manager), runs
# `terraform apply` to roll the Kubernetes Secret, waits for the next
# CronJob run to prove the new token works, and prints how to revoke the
# old token. It never touches the old token itself -- both stay valid
# until you delete the old one, so there's no blackout window.
#
# Needs, which it does NOT set up: an `aws login` session with
# PutSecretValue on k3s-apps/sankey-export (julian's own operator
# identity has it), a working kubeconfig at ~/.kube/k3s-node-1.yaml (the
# one-time scp in README's "Running it from your laptop"), and `jq`.
#
# What it DOES set up: the SSH tunnel to the k3s apiserver -- same
# pattern as bootstrap/k3s-bootstrap's own roll-out.sh: if one is
# already open it's left alone, if this script opens it the script
# closes it again on exit.

set -euo pipefail

secret_id="k3s-apps/sankey-export"
json_key="sankey_export_app_password"
region="eu-central-1"
tunnel_pattern="ssh.*-L 6443:192.168.101.10:6443"

tmp=""
tunnel_started_by_this_script=0
cleanup() {
  [ -n "${tmp}" ] && rm -f "${tmp}"
  if [ "${tunnel_started_by_this_script}" -eq 1 ]; then
    echo "==> closing the SSH tunnel this script started"
    pkill -f "${tunnel_pattern}" || true
  fi
}
trap cleanup EXIT INT TERM

fail() {
  echo "rotate-sankey-export-app-password: $1" >&2
  exit 1
}

[ $# -le 1 ] || fail "usage: $(basename "$0") [<new-token>|-]"
command -v jq >/dev/null || fail "jq not found"
command -v aws >/dev/null || fail "aws not found"
command -v terraform >/dev/null || fail "terraform not found"
command -v kubectl >/dev/null || fail "kubectl not found"
command -v ssh >/dev/null || fail "ssh not found"

arg="${1:--prompt}"
case "${arg}" in
  -prompt)
    # silent read -- not echoed, not in shell history (the command has
    # no token argument). Paste + Enter.
    read -rsp "paste the new sankey-export token (input hidden): " new_token
    echo >&2
    ;;
  -)
    new_token="$(cat)"
    ;;
  *)
    new_token="${arg}"
    ;;
esac
new_token="${new_token#"${new_token%%[![:space:]]*}"}" # ltrim
new_token="${new_token%"${new_token##*[![:space:]]}"}" # rtrim
[ -n "${new_token}" ] || fail "empty token"
case "${new_token}" in
  *[[:space:]]*) fail "token contains whitespace -- paste just the token string" ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "${script_dir}")"
cd "${repo_root}"

# terraform reads its own kubeconfig from provider.tf's config_path; kubectl
# (used only for the post-apply CronJob check) needs to be told the same one.
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/k3s-node-1.yaml}"
[ -f "${KUBECONFIG}" ] || fail "${KUBECONFIG} not found -- see README's 'Running it from your laptop'"

if pgrep -f "${tunnel_pattern}" >/dev/null 2>&1; then
  echo "==> SSH tunnel already open, leaving it alone"
else
  echo "==> starting SSH tunnel to the k3s apiserver"
  ssh -f -N -L 6443:192.168.101.10:6443 julian@192.168.178.100
  tunnel_started_by_this_script=1
  sleep 1
fi

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

tmp="$(mktemp)"  # removed by cleanup() on EXIT
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
# The pod list is sorted here in `sort`, not via kubectl --sort-by: the
# latter throws "the server rejected our request for an unknown reason"
# against this k3s version. Newest pod = last line.
deadline=$(( $(date +%s) + 180 ))
last_seen=""
while [ "$(date +%s)" -lt "${deadline}" ]; do
  newest="$(kubectl get pods -l app=sankey-export \
    -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' \
    2>/dev/null | sort | tail -n1 | cut -f2,3 || true)"
  if [ -n "${newest}" ] && [ "${newest}" != "${last_seen}" ]; then
    echo "    ${newest}"
    last_seen="${newest}"
  fi
  case "${newest}" in
    *$'\t'"Succeeded") echo "==> new token works -- the CronJob completed."; ok=1; break ;;
    *$'\t'"Failed")    echo "==> newest run FAILED -- check its logs before revoking anything:"; \
                       echo "    kubectl logs $(echo "${newest}" | cut -f1)"; ok=0; break ;;
  esac
  sleep 5
done
: "${ok:=0}"

echo
if [ "${ok}" = "1" ]; then
  echo "Rotation applied and verified. Now revoke the OLD token on the homeserver:"
else
  echo "Could not confirm a successful run in time. Check the CronJob before revoking:"
  echo "  kubectl get pods -l app=sankey-export -o wide   # newest by AGE"
  echo "  kubectl logs -l app=sankey-export --tail=30"
fi
cat <<'EOF'
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:list sankey-export
  # then delete every entry EXCEPT the one you just minted for this
  # rotation -- if the arg order below is rejected, run the command with
  # --help; occ prints its own usage (as it does for :add):
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:delete <OLD_ID> sankey-export
EOF
