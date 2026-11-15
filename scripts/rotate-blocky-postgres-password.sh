#!/usr/bin/env bash
# Rotates blocky_postgres_password by hand from the laptop (yearly or on suspicion): see secrets-manager's home-infra/blocky runbook.
set -euo pipefail

region="eu-central-1"
secret_id="home-infra/blocky"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/k3s-node-1.yaml}"

fail() {
  echo "rotate-blocky-postgres-password: $1" >&2
  exit 1
}

for cmd in aws jq kubectl openssl; do
  command -v "${cmd}" >/dev/null || fail "${cmd} not found"
done
[ -f "${KUBECONFIG}" ] || fail "${KUBECONFIG} not found"

echo "==> reading the current value from ${secret_id}"
current_json="$(aws secretsmanager get-secret-value --secret-id "${secret_id}" --region "${region}" \
  --query SecretString --output text)" || fail "get-secret-value failed (aws login expired?)"
echo "${current_json}" | jq -e 'has("blocky_postgres_password")' >/dev/null \
  || fail "${secret_id} has no blocky_postgres_password key"

# Alphanumeric only: the password goes into postgres:// URLs.
new_password="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)"
[ ${#new_password} -eq 40 ] || fail "failed to generate a 40-character password"

# The postgres image trusts its local socket, so no old password is needed; SQL goes on stdin, never into argv.
echo "==> ALTERing the role in Blocky's Postgres sidecar"
printf "ALTER USER blocky WITH PASSWORD '%s';\n" "${new_password}" \
  | kubectl -n apps exec -i deploy/blocky -c postgres -- psql -q -U blocky -d blocky_query_log -v ON_ERROR_STOP=1 \
  || fail "ALTER USER failed -- nothing written to Secrets Manager, the old password still works"

echo "==> writing the new password into ${secret_id}"
echo "${current_json}" | jq -c --arg p "${new_password}" '.blocky_postgres_password = $p' \
  | aws secretsmanager put-secret-value --secret-id "${secret_id}" --region "${region}" \
    --secret-string file:///dev/stdin --query VersionId --output text >/dev/null \
  || fail "put-secret-value failed -- the database already has the new password: rerun this script"
unset new_password current_json

# Blocky and Grafana fail to log in until ESO delivers the new value, so don't wait for the hourly refresh.
echo "==> forcing ESO to sync now; Reloader restarts Blocky and Grafana"
now="$(date +%s)"
kubectl -n apps annotate externalsecret blocky-config blocky-postgres-credentials blocky-postgres-exporter-dsn \
  force-sync="${now}" --overwrite >/dev/null
kubectl -n monitoring annotate externalsecret grafana-datasources force-sync="${now}" --overwrite >/dev/null

echo "==> waiting for the rollouts"
sleep 15
kubectl -n apps rollout status deploy/blocky --timeout=180s
kubectl -n monitoring rollout status deploy/grafana --timeout=180s

echo "==> done. Check Grafana's Blocky query-log dashboard shows fresh queries."
