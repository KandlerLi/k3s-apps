#!/usr/bin/env bash
# Usage: rotate-sankey-export-app-password.sh [<new-token>|-]  (no argument prompts silently)
# Procedure: secrets-manager's k3s-apps/sankey-export runbook.

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
    # Silent read: not echoed, not in shell history.
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

# kubectl needs the same kubeconfig terraform reads via provider.tf.
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

# Watches the next CronJob run; sorted with sort, since kubectl --sort-by fails on this k3s version.
node_kubectl='ssh -J julian@192.168.178.100 ansible@192.168.101.10 sudo k3s kubectl -n apps'
ok=0
if kubectl -n apps get pods -l app=sankey-export -o name >/dev/null 2>&1; then
  echo "==> waiting for the next sankey-export CronJob run to finish (up to 3 min)"
  deadline=$(( $(date +%s) + 180 ))
  last_seen=""
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    newest="$(kubectl -n apps get pods -l app=sankey-export \
      -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' \
      2>/dev/null | sort | tail -n1 | cut -f2,3 || true)"
    if [ -n "${newest}" ] && [ "${newest}" != "${last_seen}" ]; then
      echo "    ${newest}"
      last_seen="${newest}"
    fi
    case "${newest}" in
      *$'\t'"Succeeded") echo "==> new token works -- the CronJob completed."; ok=1; break ;;
      *$'\t'"Failed")    echo "==> newest run FAILED -- check its logs before revoking anything:"; \
                         echo "    kubectl -n apps logs $(echo "${newest}" | cut -f1)"; ok=0; break ;;
    esac
    sleep 5
  done
else
  echo "==> local kubectl can't talk to this cluster (version skew) -- skipping the automated check"
fi

echo
if [ "${ok}" = "1" ]; then
  echo "Rotation applied and verified. Now revoke the OLD token on the homeserver:"
else
  echo "Verify the next CronJob run succeeded before revoking. Local kubectl:"
  echo "  kubectl -n apps get pods -l app=sankey-export -o wide"
  echo "  kubectl -n apps logs -l app=sankey-export --tail=30"
  echo "or the node's own bundled kubectl over SSH (works regardless of local version):"
  echo "  ${node_kubectl} get pods -l app=sankey-export -o wide"
  echo "  ${node_kubectl} logs -l app=sankey-export --tail=30"
fi
cat <<'EOF'
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:list sankey-export
  # Then delete every id except the new one (:delete takes <uid> then <id>).
  docker exec nextcloud-aio-nextcloud php occ user:auth-tokens:delete sankey-export <OLD_ID>
EOF
