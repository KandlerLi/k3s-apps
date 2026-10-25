#!/usr/bin/env bash
# Usage: rotate-authelia-internal-secrets.sh
# Rotates Authelia's session secret, storage encryption key and OIDC issuer key; procedure in secrets-manager's runbooks.

set -euo pipefail

region="eu-central-1"
secret_id="home-infra/authelia"
keys=(authelia_session_secret authelia_storage_encryption_key authelia_oidc_issuer_private_key)
tunnel_pattern="ssh.*-L 6443:192.168.101.10:6443"

fail() {
  echo "rotate-authelia-internal-secrets: $1" >&2
  exit 1
}

for tool in jq aws terraform ssh kubectl openssl; do
  command -v "$tool" >/dev/null || fail "$tool not found"
done

tunnel_started_by_this_script=0
db_rekeyed=0
old_json=""
new_json=""
new_storage_key=""

cleanup() {
  status=$?
  if [ "${db_rekeyed}" -eq 1 ] && [ "${status}" -ne 0 ]; then
    cat >&2 <<EOF

!! The SQLite database is already re-encrypted with the NEW storage key,
!! and ${secret_id} in Secrets Manager already holds it (written before
!! change-key). Do NOT put the old version back. Finish with:
!!   terraform apply   (in this repo)
EOF
  fi
  unset old_json new_json new_storage_key
  if [ "${tunnel_started_by_this_script}" -eq 1 ]; then
    echo "==> closing the SSH tunnel this script started"
    pkill -f "${tunnel_pattern}" || true
  fi
}
trap cleanup EXIT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "${script_dir}")"

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

aws sts get-caller-identity --region "${region}" >/dev/null 2>&1 || fail "no valid AWS session -- run 'aws login' first"

echo "==> reading ${secret_id} (kept in memory only)"
old_json="$(aws secretsmanager get-secret-value --secret-id "${secret_id}" --region "${region}" \
  --query SecretString --output text)" || fail "get-secret-value for ${secret_id} failed"
for k in "${keys[@]}"; do
  printf '%s' "${old_json}" | jq -e --arg k "$k" 'has($k)' >/dev/null \
    || fail "${secret_id} has no \"$k\" key -- aborting rather than guessing"
done

echo "==> checking the live database still matches the current storage key"
kubectl exec deploy/authelia -c authelia -- \
  authelia storage encryption check --config /config/configuration.yml | grep SUCCESS >/dev/null \
  || fail "current storage key doesn't validate against the live database -- not touching it"

echo "==> taking a fresh Authelia backup before touching the database"
backup_job="authelia-backup-pre-rotation-$(date +%Y%m%d%H%M%S)"
kubectl create job --from=cronjob/authelia-backup "${backup_job}" >/dev/null
kubectl wait --for=condition=complete "job/${backup_job}" --timeout=300s >/dev/null \
  || fail "backup job ${backup_job} didn't complete -- not touching the database"

cat <<EOF

About to rotate in ${secret_id}:
  - authelia_session_secret           (everyone is logged out)
  - authelia_storage_encryption_key   (database re-encrypted in place; TOTP stays)
  - authelia_oidc_issuer_private_key  (every OIDC client session ends)
EOF
read -rp "Continue? [y/N] " answer
[ "${answer}" = "y" ] || fail "aborted, nothing changed"

echo "==> generating new values (in memory only)"
new_session_secret="$(openssl rand -hex 32)"
new_storage_key="$(openssl rand -hex 32)"
new_issuer_key="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 2>/dev/null)"
[ "${#new_session_secret}" -eq 64 ] && [ "${#new_storage_key}" -eq 64 ] || fail "random generation came up short"
case "${new_issuer_key}" in "-----BEGIN PRIVATE KEY-----"*) ;; *) fail "RSA key generation failed" ;; esac

# Values go to jq via its environment, never argv, so ps can't show them.
new_json="$(printf '%s' "${old_json}" | S="${new_session_secret}" E="${new_storage_key}" I="${new_issuer_key}" jq \
  '.authelia_session_secret = env.S | .authelia_storage_encryption_key = env.E | .authelia_oidc_issuer_private_key = env.I')"
unset new_session_secret new_issuer_key

# Secrets Manager first: the running Pod keeps its old config until the apply, and the new key can never get lost.
echo "==> writing the new values into ${secret_id}"
printf '%s' "${new_json}" | aws secretsmanager put-secret-value --secret-id "${secret_id}" --region "${region}" \
  --secret-string file:///dev/stdin --query VersionId --output text >/dev/null \
  || fail "put-secret-value failed -- nothing changed"

echo "==> re-encrypting the live database with the new storage key"
if ! printf '%s\n' "${new_storage_key}" | kubectl exec -i deploy/authelia -c authelia -- sh -c \
  'IFS= read -r k; authelia storage encryption change-key --config /config/configuration.yml --new-encryption-key "$k"'; then
  echo "==> change-key failed, putting the previous values back into ${secret_id}" >&2
  printf '%s' "${old_json}" | aws secretsmanager put-secret-value --secret-id "${secret_id}" --region "${region}" \
    --secret-string file:///dev/stdin --query VersionId --output text >/dev/null \
    || fail "ROLLBACK FAILED: restore ${secret_id} to its AWSPREVIOUS version by hand"
  fail "change-key failed; ${secret_id} restored, database unchanged"
fi
db_rekeyed=1

printf '%s\n' "${new_storage_key}" | kubectl exec -i deploy/authelia -c authelia -- sh -c \
  'IFS= read -r k; authelia storage encryption check --config /config/configuration.yml --encryption-key "$k"' \
  | grep SUCCESS >/dev/null || fail "the database doesn't validate against the new key"
echo "==> database validates against the new key"

echo "==> terraform apply (rolls the Authelia Pod onto the new values)"
echo "    review the plan -- it should touch only Authelia's own Secret and Deployment"
terraform init -input=false >/dev/null
terraform apply

cat <<EOF

Done. Verify by hand:
  1. Log in at https://auth.jkandler.de -- password and TOTP must still work
     (TOTP working proves the storage re-encryption).
  2. Sign in to Grafana, Open WebUI, Nextcloud, Paperless and Bulwark via
     Authelia once each (they fetch the new signing key from the JWKS).
  3. Record the rotation: secrets-manager's scripts/manage-rotation-schedule.sh.
Backup taken before the change: job ${backup_job}.
EOF
