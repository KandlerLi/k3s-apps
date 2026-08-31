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
  echo "Exported TF_VAR_* for: deluge_web_password, home_agent_ghcr_token, home_agent_openai_api_key, grafana_admin_password, blocky_postgres_password, nextcloud_tools_app_password, alertmanager_ses_smtp_username, alertmanager_ses_smtp_password"
else
  echo "export-tf-vars.sh: failed, see error above -- nothing was exported" >&2
fi

unset _export_tf_vars_script_dir output
