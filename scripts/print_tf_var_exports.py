#!/usr/bin/env python3
"""Print `export TF_VAR_...` lines for every secret this repo's Terraform needs.

Prints to stdout only -- never writes anything, never runs terraform
itself -- so it's meant to be eval'd into the current shell, not
executed for its own sake:

    eval "$(python3 scripts/print_tf_var_exports.py)"
    terraform plan
    terraform apply

or, more conveniently, sourced via scripts/export-tf-vars.sh, which
wraps exactly that eval.

Two sources, both decrypted via `sops -d` (never written back out here):

- home-infra's own secrets.sops.yml, for the secrets every module here
  shares with home-infra's own Ansible-managed deployment of the same
  service (Deluge's web password, home_agent's GHCR/OpenAI credentials,
  Grafana's admin password, Blocky's Postgres password).
- this repo's own secrets.sops.yml, for nextcloud_tools_app_password --
  deliberately NOT in home-infra's vault, since it's a separate,
  independently-revocable app password for this k3s copy (see
  modules/home_agent/variables.tf).

home_agent_image isn't a secret (just a pinned public digest string) --
it lives in this repo's own tracked terraform.tfvars instead, which
`terraform` already loads automatically, so it's not part of this
script at all.

HOME_INFRA_DIR overrides the default sibling-directory guess
(../home-infra relative to this repo's root) if your checkout lives
somewhere else.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
HOME_INFRA_DIR = Path(
    os.environ.get("HOME_INFRA_DIR", REPO_ROOT.parent / "home-infra")
).expanduser()
HOME_INFRA_SECRETS_FILE = (
    HOME_INFRA_DIR / "ansible" / "inventory" / "group_vars" / "all" / "secrets.sops.yml"
)
K3S_APPS_SECRETS_FILE = REPO_ROOT / "secrets.sops.yml"

# Each entry: (source file, key in that file, TF_VAR name to export).
SECRET_SOURCES = [
    (HOME_INFRA_SECRETS_FILE, "deluge_web_password", "deluge_web_password"),
    (HOME_INFRA_SECRETS_FILE, "home_agent_ghcr_token", "home_agent_ghcr_token"),
    (HOME_INFRA_SECRETS_FILE, "home_agent_openai_api_key", "home_agent_openai_api_key"),
    (HOME_INFRA_SECRETS_FILE, "monitoring_grafana_admin_password", "grafana_admin_password"),
    (HOME_INFRA_SECRETS_FILE, "blocky_postgres_password", "blocky_postgres_password"),
    (K3S_APPS_SECRETS_FILE, "nextcloud_tools_app_password", "nextcloud_tools_app_password"),
    (
        HOME_INFRA_SECRETS_FILE,
        "monitoring_ses_smtp_username",
        "alertmanager_ses_smtp_username",
    ),
    (
        HOME_INFRA_SECRETS_FILE,
        "monitoring_ses_smtp_password",
        "alertmanager_ses_smtp_password",
    ),
]


def decrypt(secrets_file: Path) -> dict[str, object]:
    if not secrets_file.is_file():
        raise SystemExit(f"error: {secrets_file} does not exist")
    result = subprocess.run(
        ["sops", "-d", str(secrets_file)],
        check=True,
        capture_output=True,
        text=True,
    )
    return yaml.safe_load(result.stdout) or {}


def main() -> int:
    decrypted_by_file: dict[Path, dict[str, object]] = {}
    for secrets_file, _key, _tf_var in SECRET_SOURCES:
        if secrets_file not in decrypted_by_file:
            try:
                decrypted_by_file[secrets_file] = decrypt(secrets_file)
            except subprocess.CalledProcessError as error:
                print(f"error: sops -d {secrets_file} failed: {error.stderr}", file=sys.stderr)
                return 1

    lines = []
    for secrets_file, key, tf_var in SECRET_SOURCES:
        value = decrypted_by_file[secrets_file].get(key)
        if not isinstance(value, str) or not value or value == "CHANGE_ME":
            print(
                f"error: {key} missing or still CHANGE_ME in {secrets_file} "
                f"-- run `sops {secrets_file}` to fill it in",
                file=sys.stderr,
            )
            return 1
        lines.append(f"export TF_VAR_{tf_var}={shlex.quote(value)}")

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
