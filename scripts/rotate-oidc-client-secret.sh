#!/usr/bin/env bash
# Usage: rotate-oidc-client-secret.sh <grafana|openwebui|bulwark|paperless|nextcloud>
# Rotates an Authelia OIDC client secret pair; procedure per client in secrets-manager's runbooks.

set -euo pipefail

region="eu-central-1"
authelia_secret_id="home-infra/authelia"
tunnel_pattern="ssh.*-L 6443:192.168.101.10:6443"

fail() {
  echo "rotate-oidc-client-secret: $1" >&2
  exit 1
}

[ $# -eq 1 ] || fail "usage: $(basename "$0") <grafana|openwebui|bulwark|paperless|nextcloud>"
client="$1"
case "$client" in
  grafana)
    client_secret_id="home-infra/grafana"
    ;;
  openwebui)
    client_secret_id="home-infra/open-webui"
    ;;
  bulwark)
    client_secret_id="k3s-apps/bulwark"
    ;;
  paperless)
    client_secret_id="k3s-apps/paperless"
    ;;
  nextcloud)
    client_secret_id="home-infra/nextcloud"
    ;;
  *)
    fail "usage: $(basename "$0") <grafana|openwebui|bulwark|paperless|nextcloud>"
    ;;
esac
hash_key="authelia_oidc_${client}_client_secret_hash"
plaintext_key="authelia_oidc_${client}_client_secret"

command -v jq >/dev/null || fail "jq not found"
command -v aws >/dev/null || fail "aws not found"
command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

tmp_authelia=""
tmp_client=""
tunnel_started_by_this_script=0
cleanup() {
  [ -n "${tmp_authelia}" ] && rm -f "${tmp_authelia}"
  [ -n "${tmp_client}" ] && rm -f "${tmp_client}"
  if [ "${tunnel_started_by_this_script}" -eq 1 ]; then
    echo "==> closing the SSH tunnel this script started"
    pkill -f "${tunnel_pattern}" || true
  fi
}
trap cleanup EXIT INT TERM

read -rsp "paste the new PLAINTEXT client secret (input hidden): " plaintext
echo >&2
read -rsp "paste the new pbkdf2 HASH (input hidden): " hash
echo >&2

for v in plaintext hash; do
  val="${!v}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf -v "$v" '%s' "$val"
done
[ -n "${plaintext}" ] || fail "empty plaintext"
[ -n "${hash}" ] || fail "empty hash"
case "${plaintext}" in
  *[[:space:]]*) fail "plaintext contains whitespace -- paste just the value" ;;
  '$'*) fail "the plaintext looks like a pbkdf2 hash (starts with \$) -- did you swap plaintext and hash?" ;;
esac
case "${hash}" in
  *[[:space:]]*) fail "hash contains whitespace -- paste just the value" ;;
  '$'*) ;;
  *) fail "the hash doesn't look like a pbkdf2 modular-crypt hash (expected to start with \$) -- did you swap plaintext and hash?" ;;
esac
[ "${plaintext}" != "${hash}" ] || fail "plaintext and hash are identical -- something's wrong"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "${script_dir}")"
cd "${repo_root}"

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

echo "==> writing the new hash into ${authelia_secret_id}"
authelia_json="$(aws secretsmanager get-secret-value --secret-id "${authelia_secret_id}" --region "${region}" \
  --query SecretString --output text)" || fail "get-secret-value for ${authelia_secret_id} failed"
echo "${authelia_json}" | jq -e --arg k "${hash_key}" 'has($k)' >/dev/null \
  || fail "${authelia_secret_id} has no \"${hash_key}\" key -- aborting rather than guessing"
tmp_authelia="$(mktemp)"
echo "${authelia_json}" | jq --arg k "${hash_key}" --arg v "${hash}" '.[$k] = $v' > "${tmp_authelia}"
aws secretsmanager put-secret-value --secret-id "${authelia_secret_id}" --region "${region}" \
  --secret-string "file://${tmp_authelia}" --query VersionId --output text >/dev/null \
  || fail "put-secret-value for ${authelia_secret_id} failed"

echo "==> writing the new plaintext into ${client_secret_id}"
client_json="$(aws secretsmanager get-secret-value --secret-id "${client_secret_id}" --region "${region}" \
  --query SecretString --output text)" || fail "get-secret-value for ${client_secret_id} failed"
echo "${client_json}" | jq -e --arg k "${plaintext_key}" 'has($k)' >/dev/null \
  || fail "${client_secret_id} has no \"${plaintext_key}\" key -- aborting rather than guessing"
tmp_client="$(mktemp)"
echo "${client_json}" | jq --arg k "${plaintext_key}" --arg v "${plaintext}" '.[$k] = $v' > "${tmp_client}"
aws secretsmanager put-secret-value --secret-id "${client_secret_id}" --region "${region}" \
  --secret-string "file://${tmp_client}" --query VersionId --output text >/dev/null \
  || fail "put-secret-value for ${client_secret_id} failed"

if [ "${client}" = "nextcloud" ]; then
  echo "==> terraform apply (rolls Authelia's own side only -- nextcloud has no k3s Deployment)"
  echo "    review the plan -- it should touch only Authelia's own Secret"
else
  echo "==> terraform apply (rolls Authelia + ${client} together, in sync)"
  echo "    review the plan -- it should touch only Authelia's own Secret and ${client}'s own Secret"
fi
terraform init -input=false >/dev/null
terraform apply

if [ "${client}" = "nextcloud" ]; then
  home_infra_dir="${repo_root}/../home-infra"
  [ -d "${home_infra_dir}" ] || fail "expected KandlerLi/home-infra as a sibling of this repo at ${home_infra_dir}, not found"
  [ -x "${home_infra_dir}/.venv/bin/ansible-playbook" ] || fail "${home_infra_dir}/.venv/bin/ansible-playbook not found -- set up its venv first"

  echo "==> re-running KandlerLi/home-infra's site.yml so Nextcloud's own occ config picks up the new plaintext"
  echo "    (this is a real upsert, not a formality -- ansible/roles/nextcloud_aio/tasks/oidc.yml's own occ user_oidc:provider call)"
  ( cd "${home_infra_dir}" && ./.venv/bin/ansible-playbook ansible/playbooks/site.yml --ask-become-pass )

  cat <<EOF

Done. This can't be verified automatically -- it's a browser OIDC login
flow. Confirm for real:
  1. Sign out of Nextcloud if signed in.
  2. "Sign in with Authelia" on Nextcloud -- must reach a real Authelia
     login/consent screen and land back in Nextcloud authenticated.
  3. If it fails, the two values are still both in Secrets Manager, in
     Authelia's live Kubernetes Secret, and in Nextcloud's own occ
     config from the site.yml run above -- re-check you pasted the
     plaintext and hash from the SAME generation command, not two
     different runs (the pair only matches if generated together).
EOF
else
  cat <<EOF

Done. This can't be verified automatically -- it's a browser OIDC login
flow. Confirm for real:
  1. Sign out of ${client} if signed in.
  2. "Sign in with Authelia" on ${client} -- must reach a real Authelia
     login/consent screen and land back in ${client} authenticated.
  3. If it fails, the two values are still both in Secrets Manager and
     in the live Kubernetes Secrets -- re-check you pasted the plaintext
     and hash from the SAME generation command, not from two different
     runs (the pair only matches if generated together).
EOF
fi
