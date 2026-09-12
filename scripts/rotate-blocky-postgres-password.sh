#!/usr/bin/env bash
# Rotates blocky_postgres_password end-to-end: generates a new
# password, ALTERs the live Postgres role directly over the network
# (blocky-svc:5432 -- the same in-cluster Service modules/grafana's own
# datasource already reaches directly), writes the new value to
# Secrets Manager, then runs terraform apply (rolls both Blocky's and
# Grafana's Deployments via their own checksum annotations -- added
# 2026-09-12 specifically so this works; without them neither Pod
# would pick up the new value on its own).
#
# The only secret in this whole workspace judged genuinely safe to
# rotate unattended: mechanically simple, low blast radius, and no
# external system whose own UI needs separate reconfiguring the way
# every OIDC pair or dyndns/fritzbox's router-side credential does.
#
# Built to run from this repo's own scheduled GitHub Actions workflow
# (rotate-blocky-postgres.yml) on the self-hosted runner living inside
# the same cluster -- blocky-svc is only reachable from in-cluster, so
# unlike the other rotate-*.sh scripts here, this one genuinely can't
# run from an arbitrary outside machine. TF_VAR_in_cluster=true (set
# by that workflow, same as apply.yml) is what makes the kubernetes
# provider use the runner Pod's own ServiceAccount token instead of a
# local kubeconfig/SSH tunnel.
#
# Needs, which it does NOT set up: an AWS session with GetSecretValue/
# PutSecretValue on home-infra/blocky (the workflow's own OIDC role
# assumption covers this), network reachability to blocky-svc:5432 and
# grafana-svc:80 (true only from inside the cluster), and `psql` on
# PATH (installed by the calling workflow -- not baked into the shared
# CI image, gha-common's own Dockerfile has no Postgres client at all).

set -euo pipefail

region="eu-central-1"
secret_id="home-infra/blocky"
postgres_host="${BLOCKY_POSTGRES_HOST:-blocky-svc}"
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
# Alphanumeric only -- this value ends up in a postgres://user:PASSWORD@...
# URL inside Blocky's own config.yml, so the same characters that broke
# dyndns/fritzbox's URL authority (:, @, /) have to be avoided here too.
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
curl -fsS -o /dev/null "http://blocky-svc:4000/metrics" || fail "blocky-svc:4000/metrics did not respond"
curl -fsS -o /dev/null "http://grafana-svc:80/api/health" || fail "grafana-svc:80/api/health did not respond"

echo "==> done. blocky_postgres_password rotated, applied, and verified end-to-end."
