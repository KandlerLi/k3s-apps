#!/usr/bin/env bash
# Rotates blocky_postgres_password end-to-end, unattended and in-cluster only: see the README, "CI",
# and secrets-manager's home-infra/blocky runbook.

set -euo pipefail

region="eu-central-1"
secret_id="home-infra/blocky"
postgres_host="${BLOCKY_POSTGRES_HOST:-blocky-svc.default.svc.cluster.local}"
postgres_port="${BLOCKY_POSTGRES_PORT:-5432}"

fail() {
  echo "rotate-blocky-postgres-password: $1" >&2
  exit 1
}

command -v aws >/dev/null || fail "aws not found"
command -v jq >/dev/null || fail "jq not found"
command -v psql >/dev/null || fail "psql not found"
command -v terraform >/dev/null || fail "terraform not found"
command -v curl >/dev/null || fail "curl not found"

tmp_secret=""
cleanup() {
  [ -n "${tmp_secret}" ] && rm -f "${tmp_secret}"
}
trap cleanup EXIT INT TERM

echo "==> reading the current value from ${secret_id}"
current_json="$(aws secretsmanager get-secret-value --secret-id "${secret_id}" --region "${region}" \
  --query SecretString --output text)" || fail "get-secret-value for ${secret_id} failed"
old_password="$(echo "${current_json}" | jq -r '.blocky_postgres_password')"
[ -n "${old_password}" ] && [ "${old_password}" != "null" ] || fail "${secret_id} has no blocky_postgres_password value"

echo "==> generating a new password"
# Alphanumeric only: the password goes into a postgres:// URL.
new_password="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)"
[ ${#new_password} -eq 40 ] || fail "failed to generate a 40-character password"

echo "==> ALTERing the live Postgres role at ${postgres_host}:${postgres_port}"
PGPASSWORD="${old_password}" psql -h "${postgres_host}" -p "${postgres_port}" -U blocky -d blocky_query_log \
  -v ON_ERROR_STOP=1 -c "ALTER USER blocky WITH PASSWORD '${new_password}';" \
  || fail "ALTER USER failed -- old password may already be stale, or blocky-svc is unreachable"

echo "==> writing the new password into ${secret_id}"
tmp_secret="$(mktemp)"
echo "${current_json}" | jq --arg p "${new_password}" '.blocky_postgres_password = $p' > "${tmp_secret}"
aws secretsmanager put-secret-value --secret-id "${secret_id}" --region "${region}" \
  --secret-string "file://${tmp_secret}" --query VersionId --output text >/dev/null \
  || fail "put-secret-value for ${secret_id} failed"

echo "==> terraform apply (rolls both Blocky and Grafana, via their own checksum annotations)"
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform apply -input=false -auto-approve

echo "==> verifying the new password actually works against the live database"
for attempt in 1 2 3 4 5 6; do
  if PGPASSWORD="${new_password}" psql -h "${postgres_host}" -p "${postgres_port}" -U blocky -d blocky_query_log \
      -v ON_ERROR_STOP=1 -c "SELECT 1;" >/dev/null 2>&1; then
    echo "    new password authenticated successfully"
    break
  fi
  [ "${attempt}" -eq 6 ] && fail "new password still doesn't authenticate after the apply -- Blocky's own Pod may not have restarted"
  echo "    not ready yet (attempt ${attempt}/6), waiting for the Pod to roll..."
  sleep 10
done

echo "==> verifying Blocky and Grafana are actually up afterward"
curl -fsS -o /dev/null "http://blocky-svc.default.svc.cluster.local:4000/metrics" || fail "blocky-svc:4000/metrics did not respond"
curl -fsS -o /dev/null "http://grafana-svc.default.svc.cluster.local:80/api/health" || fail "grafana-svc:80/api/health did not respond"

echo "==> done. blocky_postgres_password rotated, applied, and verified end-to-end."
