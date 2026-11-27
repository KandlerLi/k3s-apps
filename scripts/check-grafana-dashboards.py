#!/usr/bin/env python3
"""Static checks for argocd/grafana/dashboards, run by the Validate job (ported from home-infra, tracker #76)."""
import json
import pathlib
import sys

DIR = pathlib.Path("argocd/grafana/dashboards")
UIDS = {"prometheus": "prometheus", "grafana-postgresql-datasource": "blocky-postgres"}
errors = []


def datasources(panels):
    for panel in panels:
        for ds in [panel.get("datasource")] + [t.get("datasource") for t in panel.get("targets", [])]:
            if isinstance(ds, dict):
                yield ds
        yield from datasources(panel.get("panels", []))


kustomization = (DIR.parent / "kustomization.yaml").read_text()
for path in sorted(DIR.glob("*.json")):
    name = path.name
    raw = path.read_text()
    board = json.loads(raw)
    if f"dashboards/{name}" not in kustomization:
        errors.append(f"{name}: not listed in kustomization.yaml")
    if not board.get("panels"):
        errors.append(f"{name}: no panels")
    for ds in datasources(board.get("panels", [])):
        want = UIDS.get(ds.get("type"))
        if want and ds.get("uid") != want:
            errors.append(f"{name}: {ds.get('type')} datasource uid {ds.get('uid')!r}, expected {want!r}")
    # File-provisioned with fixed values, so no import placeholders.
    if "${DS_" in raw or "${VAR_" in raw:
        errors.append(f"{name}: import placeholder left in")
    # refresh 0 ("never") leaves query variables empty on load.
    for var in board.get("templating", {}).get("list", []):
        if var.get("type") == "query" and var.get("refresh") not in (1, 2):
            errors.append(f"{name}: query variable {var['name']} doesn't refresh on load")

for e in errors:
    print(f"::error file={DIR}::{e}")
sys.exit(1 if errors else 0)
