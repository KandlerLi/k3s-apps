# Source this (not execute it) to export every TF_VAR_* this repo's
# Terraform needs into your current shell, decrypted from home-infra's
# and this repo's own secrets.sops.yml -- see print_tf_var_exports.py
# for exactly where each one comes from.
#
#   source scripts/export-tf-vars.sh
#   terraform plan
#   terraform apply
#
# Safe to re-run any time; nothing here is written anywhere, and
# nothing is echoed to the terminal beyond confirmation that it worked.

_export_tf_vars_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if output="$(python3 "${_export_tf_vars_script_dir}/print_tf_var_exports.py")"; then
  eval "${output}"
  echo "Exported TF_VAR_* for: home_agent_ghcr_token, home_agent_openai_api_key, grafana_admin_password, blocky_postgres_password, nextcloud_tools_app_password, sankey_export_app_password, alertmanager_ses_smtp_username, alertmanager_ses_smtp_password, github_runner_github_token, shared_ingress_auth_password_hash, k3s_ingress_acme_dns01_access_key_id, k3s_ingress_acme_dns01_secret_access_key, authelia_session_secret, authelia_storage_encryption_key, authelia_reset_password_jwt_secret, authelia_admin_password_hash, authelia_oidc_hmac_secret, authelia_oidc_issuer_private_key, authelia_oidc_grafana_client_secret_hash, authelia_oidc_openwebui_client_secret_hash, authelia_oidc_grafana_client_secret, authelia_oidc_openwebui_client_secret"
  unset _export_tf_vars_script_dir output
else
  echo "export-tf-vars.sh: failed, see error above -- nothing was exported" >&2
  unset _export_tf_vars_script_dir output
  # `return`, not `exit` -- this script is only ever meant to be
  # sourced (see the header above), never executed directly, so this
  # only ends the sourcing operation itself, not the caller's own
  # interactive shell. Confirmed live, 2026-09-08: without this, a
  # failure here was completely silent to anything checking $? right
  # after sourcing -- the branch printed its error but fell through to
  # `unset` (a successful command), so the source command itself
  # reported success with zero variables actually exported.
  # bootstrap/k3s-bootstrap's own roll-out.sh already sources this
  # script unconditionally and would have silently proceeded straight
  # into `terraform plan` with nothing set, exactly reproducing the
  # interactive-prompt problem this whole script exists to avoid.
  return 1
fi
