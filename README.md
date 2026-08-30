# k3s-apps

Terraform-managed workloads for the personal k3s learning cluster
(`k3s-node-1`, see the `k3s_node` role in `home-infra`). This is a
**learning project**, kept deliberately separate from `home-infra`'s
production Ansible-managed services -- services are cut over to it one
at a time, each proven live first.

Uses Terraform's `kubernetes` provider directly against the cluster,
instead of plain `kubectl apply -f` -- a deliberate choice to keep one
IaC tool (Terraform) consistent across the whole homelab, at the known
cost of a second reconciler alongside Kubernetes' own control loop (see
this repo's commit history / conversation history for the trade-off).

## What's here

One module per service (`modules/<service>/`), wired together by the
root `main.tf`. Adding a third service means a new `modules/<service>/`
directory plus a `module` block in `main.tf` -- an existing service's
code doesn't need touching.

- `modules/landing_page/` -- the k3s-native equivalent of `home-infra`'s
  now-deleted `ansible/roles/landing_page` role: same pinned image
  digest, same mount point, same real content (`files/index.html`,
  `files/style.css`, pulled from the live homeserver, not fabricated).
  Serves `home.jkandler.de` in production.
- `modules/deluge/` -- statically-provisioned NFS storage bound to
  `home-infra`'s `nfs_server` exports (`storage.tf`), Deluge's own
  web-login Secret reproducing its salted-SHA1 scheme (`secret.tf`), and
  the Deployment/Services/Ingress (`main.tf`, with an init container
  working around a Kubernetes `subPath`/NFS `root_squash`
  incompatibility). Serves `torrent.jkandler.de` in production.
- `modules/home_agent/` -- `home_agent` + `nextcloud_tools` as sidecars
  in one Pod, sharing a Unix socket through an `emptyDir` (preserves the
  exact trust shape `home-infra`'s own deployment has today, just
  relocated from "two processes on one host" to "two containers in one
  Pod"). `nextcloud_tools` reaches Nextcloud AIO's Apache at
  `192.168.101.1:11000` (see `nextcloud_aio_apache_ip_binding` in
  `home-infra`). `home_agent`'s own image is a private GHCR package,
  built and pushed by `home-infra`'s `build-home-agent.yml` on its
  self-hosted CI runner -- never on the homeserver. The one dependency
  that couldn't move as a sidecar is `home_tools_service` (it reports
  the *homeserver's own* hardware, so it has to keep running there);
  reached instead over its own optional TCP listener at
  `192.168.101.1:8095`. Confirmed live 2026-08-30: both containers
  Running, and all four paths this Pod depends on actually exercised
  from inside it (not just "the process didn't crash") --
  `home-agent`'s own `/healthz`, the Unix socket to `nextcloud-tools`,
  `nextcloud-tools` reaching Nextcloud AIO's `/status.php`, and
  `home-agent` reaching `home_tools_service` over the TCP listener and
  getting real homeserver hardware data back. Getting there needed
  several real fixes past the first-cut manifest: CPU requests/limits
  sized without measuring what these processes actually do (starved the
  Pod off the VM's 2 vCPU budget), a serviceaccount token neither
  container needs colliding with `read_only_root_filesystem`,
  `nextcloud_tools_service.py`'s own loopback-only guard not knowing
  about this Pod's real address, non-deterministic file permissions
  from the CI image build, and the two containers' sidecar UIDs not
  sharing a GID despite the Unix socket depending on one. No Ingress
  yet -- not cut over to `ai.jkandler.de`.
- `modules/open_webui/` -- the k3s-native copy of `home-infra`'s own
  `open_webui` role: same pinned image, same real data (mounted from
  an NFS export of `/var/lib/open-webui`, not started fresh -- same
  "share the real state" choice already made for Deluge's config,
  see `nfs_server_exports` in `home-infra`), and the same UID:GID
  (`995:0`, not the account's own default group -- see the module's
  own comment) the Docker deployment already runs as, so the shared
  NFS export's permissions just work. Points at `home_agent`'s own
  in-cluster Service instead of the Docker `home-agent` network alias
  for its OpenAI-compatible API. Resourced deliberately differently
  from every other module here (Burstable, not this repo's usual
  limits-only-implies-Guaranteed) -- see the module's own comment for
  why. Migrated against the real, already-live data: home-infra's own
  container was stopped first (SQLite tolerates concurrent NFS writers
  far worse than Deluge's own session state did), the k3s copy then
  confirmed to have read the real accounts/chat history (persisted
  database settings came back, not fresh env-var defaults), not
  restarted afterward -- the outage carried straight through into the
  routing cutover below instead of a throwaway validate-then-revert
  cycle.
- `ai_ingress.tf` -- the one resource that genuinely depends on both
  `home_agent`'s and `open_webui`'s own Services (via each module's
  `outputs.tf`), so it lives at the root instead of inside either
  module. Replicates `home-infra`'s own `shared_ingress` path split
  for `ai.jkandler.de` (`/healthz` and `/v1/chat` to `home_agent`,
  everything else to `open_webui`) using standard Kubernetes Ingress
  path matching instead of Traefik's own priority annotation.
- `modules/grafana/` -- Phase 1 of moving `home-infra`'s `monitoring`
  role into k3s: Grafana only. Prometheus, Alertmanager, the exporters,
  and Blocky all stay on the homeserver permanently (they report *this
  physical host's* own hardware/Docker daemon, or are LAN-facing --
  see the module's own comment), reached here over the additive
  `192.168.101.1` listeners `home-infra`'s `blocky` and `monitoring`
  roles now expose (`blocky_postgres_k3s_bind_address`,
  `monitoring_prometheus_k3s_bind_address`), confirmed reachable from
  inside the cluster (`kubectl exec` + `curl`/`nc`) before this module
  was built. No PVC, deliberately -- everything Grafana needs
  (datasources, dashboard provider, the five dashboard JSONs vendored
  from `home-infra`'s `ansible/roles/monitoring/files/dashboards/*.json`,
  checksummed identical) is provisioned from files, confirmed with
  Julian first that there's no click-through UI state worth migrating
  (matching the role's own README). Has its own Ingress for
  `grafana.jkandler.de` already, but **not cut over yet** --
  `home-infra`'s `shared_ingress_grafana_upstream` still points at the
  Docker container until this is verified live with real dashboard
  data from both datasources.
- `moved.tf` -- records the 2026-08-30 restructure from flat root-level
  resources into modules, so `terraform plan` recognizes each resource's
  new address as the same object rather than proposing a
  destroy+recreate. Safe to delete once a plan against the current state
  comes back clean.

## Running it from your laptop

The k3s VM's network (`192.168.101.0/24`) only exists as a
directly-connected route on the homeserver itself -- confirmed live,
nothing beyond the homeserver (not your router, not your laptop) knows
how to reach it. So running Terraform from your laptop needs an SSH
tunnel to the apiserver, opened first and kept running:

```
ssh -L 6443:192.168.101.10:6443 julian@192.168.178.100
```

Then, **one-time**, pull the kubeconfig k3s already generates onto your
laptop (its `server:` field is already `https://127.0.0.1:6443` by
default -- k3s assumes it'll be used locally on the node itself, which
is exactly what the tunnel above fakes -- so it works unmodified):

```
scp -o ProxyJump=julian@192.168.178.100 ansible@192.168.101.10:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-node-1.yaml
```

Then, with the tunnel still open in its own terminal:

```
git clone https://github.com/KandlerLi/k3s-apps.git
cd k3s-apps
terraform init
TF_VAR_deluge_web_password="$(pass show deluge/password)" terraform plan
TF_VAR_deluge_web_password="$(pass show deluge/password)" terraform apply
```

No `KUBECONFIG=...` prefix needed for the `terraform` commands above --
unlike `kubectl`, the `kubernetes` provider does **not** read that
environment variable (confirmed against its own docs; an earlier version
of this file assumed it did, which silently fell back to querying
`http://localhost` instead of erroring clearly). `provider.tf` points
`config_path` straight at `~/.kube/k3s-node-1.yaml` instead, so it isn't
dependent on how you invoke the shell.

State is local (`terraform.tfstate`, gitignored) -- there's no S3
backend like every other Terraform repo in this homelab uses, because
that would mean putting AWS credentials on your laptop's local runs for
no real benefit yet. Move to a remote backend later if/when this
cluster holds something worth protecting against that file being lost.

## Relationship to the Ansible-managed originals

Both services here now serve their real production domains --
`home.jkandler.de` (cut over 2026-08-29, the old `landing_page` role
then deleted outright) and `torrent.jkandler.de` (cut over 2026-08-30,
the old `deluge` role reshaped down to just the host prerequisites --
service account, NFS-exported directories -- this cluster still depends
on, since unlike `landing_page` it owns real state a homeserver rebuild
still needs). `home-infra`'s `shared_ingress` role points at this
cluster's Traefik Ingress (`http://192.168.101.10:80`) for both routes;
see `home-infra-ai-context/context/current-state.md`'s "k3s learning
cluster" section for the full cutover history.

## Cutting over `ai.jkandler.de`

Unlike Deluge's or `home.jkandler.de`'s single-service swap,
`ai.jkandler.de` is one hostname split by *path* between two services
(`home_agent` answers `/healthz` and `/v1/chat` directly, `open_webui`
gets everything else). `ai_ingress.tf` at the root replicates that
split; `home-infra`'s own `shared_ingress` role points both
`shared_ingress_agent_upstream` and `shared_ingress_open_webui_upstream`
at this cluster (`http://192.168.101.10:80`) once ready -- both have to
move together, since this file's own path split forwards each branch
to the same k3s Traefik entrypoint, which then re-splits internally.
Cut over 2026-08-30, done in one pass rather than the usual
validate-then-revert cycle: `open_webui`'s own migration already
required stopping the live Docker container before the k3s copy could
even be started (SQLite's own concurrent-NFS-writer risk), so once
that data was confirmed to have migrated correctly, the outage carried
straight through into this routing cutover instead of restoring the
old container first.

The old `home_agent`/`open_webui`/`nextcloud_tools` Docker containers
and the roles that ran them are gone now too (also 2026-08-30, a
distinct follow-up step, not bundled into this cutover): `home_agent`
and `open_webui` reshaped down to just the host prerequisites their
k3s copies still depend on (mirroring `deluge`'s own precedent),
`nextcloud_tools` retired outright since its only consumer was
`home_agent`'s own now-gone container. See `home-infra-ai-context/
context/current-state.md` for that reshape's own real near-miss: an
intervening `site.yml` run for an unrelated fix silently restarted the
already-stopped `open-webui` container (its role was still
Docker-based at that point), leaving it running against the same
NFS-shared WAL-mode SQLite database as this Pod for about two hours
before being caught -- `PRAGMA integrity_check` came back clean and no
corruption resulted, but it's a real sequencing lesson for any future
reshape-after-cutover step here.
