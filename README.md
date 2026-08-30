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
  yet -- not cut over to `ai.jkandler.de`, and `open_webui` (the only
  other consumer) hasn't moved here yet either.
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
