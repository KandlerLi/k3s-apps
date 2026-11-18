# k3s-apps

The workloads of the personal k3s cluster (`k3s-node-1`, see the
`k3s_node` role in `home-infra`), as manifests under `argocd/` that Argo
CD syncs from `main` (ADR 0031). Their Secrets come from AWS Secrets
Manager through the External Secrets Operator (ADR 0032): each app's
`externalsecret.yaml` names the keys, never the values. Argo CD itself,
ESO, Reloader, the SecretStores and all RBAC live in `k3s-bootstrap`.
This repo has had no Terraform since 2026-11-15.

## What's here

One directory per app under `argocd/`, one Argo CD Application each. A
new app needs its directory here plus its Application and object names
in `k3s-bootstrap`'s `argocd.tf`.

- `argocd/landing-page/` -- the k3s-native equivalent of `home-infra`'s
  now-deleted `ansible/roles/landing_page` role: same pinned image
  digest, same mount point, same real content (`files/index.html`,
  `files/style.css`, pulled from the live homeserver, not fabricated).
  Serves `home.jkandler.de` in production. Deployed by Argo CD: see
  "Argo CD" below. Its route is in `argocd/ingress/values.yaml`.
- `argocd/headlamp/` -- Headlamp, the read-only cluster UI serving
  `k8s.jkandler.de` behind Authelia, deployed by Argo CD (see "Argo CD"). Runs with
  `-unsafe-use-service-account-token`, so every visitor past Authelia
  acts as its ServiceAccount without a token prompt; that ServiceAccount
  and its read-only RBAC live in `k3s-bootstrap`, since granting RBAC is
  privilege-defining and this CI-applied root can't do it to itself.
- `argocd/grafana/` -- Phase 1 of moving `home-infra`'s `monitoring`
  role into k3s: Grafana only. Prometheus, the exporters, and Blocky
  all stay on the homeserver permanently (they report *this physical
  host's* own hardware/Docker daemon, or are LAN-facing -- see the
  module's own comment; Alertmanager has since moved too, see
  `argocd/alertmanager/` below), reached here over the additive
  `192.168.101.1` listeners `home-infra`'s `blocky` and `monitoring`
  roles now expose (`blocky_postgres_k3s_bind_address`,
  `monitoring_prometheus_k3s_bind_address`), confirmed reachable from
  inside the cluster (`kubectl exec` + `curl`/`nc`) before this module
  was built. No PVC, deliberately -- everything Grafana needs
  (datasources, dashboard provider, the dashboard JSONs vendored
  from `home-infra`'s `ansible/roles/monitoring/files/dashboards/*.json`,
  checksummed identical) is provisioned from files, confirmed with
  Julian first that there's no click-through UI state worth migrating
  (matching the role's own README). Two real bugs found and fixed past
  the first-cut manifest, both the kind that don't crash-loop loudly:
  the admin-password Secret mounted at `/run/secrets` collided with
  kubelet's own serviceaccount-token auto-mount there (fixed with
  `automount_service_account_token = false`), and that Secret's data key didn't match its
  own `GF_SECURITY_ADMIN_PASSWORD__FILE` path -- the Pod started fine
  but silently kept the default `admin/admin` login instead of the
  real sops password, caught only by actually logging in and checking.
  **Confirmed live and cut over 2026-08-30**: `home-infra`'s
  `shared_ingress_grafana_upstream` now points here (real TLS, real
  Traefik Basic Auth, real Grafana admin login, both datasources
  healthy with real scrape data), and its `monitoring` role is
  reshaped down to nothing at all -- unlike `deluge`/`open_webui`,
  Grafana left no host prerequisites behind, since its directories
  were always ephemeral rather than real shared state.
- `argocd/alertmanager/` -- Phase 2: Alertmanager. Unlike Grafana, it
  has no host dependency at all, so it moves outright rather than
  needing a network exception in both directions -- but the direction
  here is reversed from Grafana's own: Prometheus (staying on the
  homeserver) has to reach *this*, not the other way around, over a
  `type = "LoadBalancer"` Service (k3s's bundled ServiceLB binds it
  directly to `192.168.101.10:9093`) rather than a ClusterIP +
  Ingress, since this isn't a browser-facing app and needs a plain
  `IP:port` target. Alertmanager itself keeps reaching the ntfy relay,
  which stays on the homeserver, over the additive
  `monitoring_ntfy_relay_k3s_bind_address` listener `home-infra`'s
  `monitoring` role now exposes. No PVC (confirmed with Julian first,
  same question already asked for Grafana) -- its own `/alertmanager`
  data is active silences and a notification-dedup log, not real
  history. Resourced off real `docker stats` (0.77% of one core,
  17.67MiB/128MiB memory) rather than its Docker `cpus:` ceiling, the
  smallest request yet (`20m`/`100m` CPU) given only 250m of headroom
  was free before this module. **Confirmed live and cut over
  2026-08-31**: a synthetic test alert posted straight to this
  module's own API reached both ntfy and the real SES inbox before
  `home-infra`'s `monitoring_alertmanager_upstream` was ever switched
  over (ruling out double-firing during the cutover, the risk a
  simultaneous old-and-new target would have carried); Prometheus's
  own `/api/v1/alertmanagers` then confirmed exactly this target,
  healthy, once switched. `home-infra`'s `monitoring` role is
  reshaped down to just the ntfy relay it still runs -- unlike
  Grafana, Alertmanager left no host prerequisites behind either.
- `github_runner` (now `k3s-bootstrap`'s `modules/github_runner/`) -- Phase B of moving `github_runner` to k3s
  (a much bigger arc than the other migrations here: real production
  CI for 6 repositories, `home-infra` itself included, so the old
  VM-based role keeps serving throughout rather than a cutover window
  -- see the plan in home-infra's own history). One Deployment per
  repository (`for_each` over `repositories.auto.tfvars.json`, itself
  generated by home-infra's `scripts/sync_github_runner_repositories.py`
  from the same [`repo-infra/config.yml`](https://github.com/KandlerLi/repo-infra/blob/main/config.yml) source the VM-based
  role already reads -- one generator, two consumers). Every Deployment
  is pinned via `node_selector`/`toleration` to `k3s-node-2`, a second,
  tainted k3s node `home-infra`'s own `k3s_node` role now supports
  specifically for this -- `k3s-node-1` runs everything else and never
  schedules CI workloads. Docker access is a privileged `docker:dind`
  sidecar per Pod (not kaniko/rootless building), a deliberate,
  accepted trade-off: every repository's existing `docker build`/
  `docker run` workflow steps keep working completely unmodified, at
  the real cost that a privileged container can escape to its own
  node -- contained to `k3s-node-2` alone. Runner image is the
  community `myoung34/github-runner`, not a hand-rolled entrypoint --
  its own registration/deregistration logic on container start/stop
  replaces the drift/busy-safety Ansible asserts the old VM-based
  role needed specifically because *that* was a persistent systemd
  service Ansible reapplied idempotently. Rolled out additively, not
  as a switch (unlike Alertmanager's notification target list): the
  new runners registered and started serving real jobs alongside the
  old VM's own runners with zero interruption risk, repository by
  repository, GitHub pooling capacity across both since they shared
  labels -- confirmed live with a real successful `Checks` run on
  every repository, `home-infra` itself included, before the old VM's
  runners were deregistered and **the VM itself decommissioned
  entirely, 2026-08-31** (`ansible/roles/github_runner` and its two
  driving playbooks deleted outright from `home-infra`, not reshaped --
  nothing on the homeserver depended on that role for host
  prerequisites once the VM was gone). That additive pooling window
  did surface one real, since-resolved regression along the way: a
  first cut at fixing a `container:` job step's own permission race
  used a continuously-polling `chmod -R 0777 /work` sidecar container,
  which turned out to actively fight `home-infra`'s own
  `checks.yml` (its `chmod o-w "$GITHUB_WORKSPACE"` security step,
  re-widened moments later by the poll loop) -- confirmed live, then
  replaced entirely by the runner container's own `umask 000` instead,
  which fixes the same race at the actual point files get created,
  no polling and nothing left to fight a later legitimate `chmod`.
  The module has since moved to
  [`k3s-bootstrap`](https://github.com/KandlerLi/k3s-bootstrap), and
  since 2026-11-01 its per-repository Deployments are replaced by ARC
  runner scale sets that create one Pod per job (tracker #39). Current
  design: that repo's README, "Runner design".
- `argocd/alloy/` -- Grafana Alloy tailing every Pod's logs through the
  Kubernetes API (`loki.source.kubernetes`, no hostPath) and pushing them
  to Loki on the homeserver (`192.168.101.1:3100`, `home-infra`'s
  `monitoring` role, which also ships the host journal there). Labels
  `job="k3s-pods"`, `namespace`, `pod`, `container`, `node`, `app`. Its
  ServiceAccount and read-only RBAC (Pods, `pods/log`) live in
  `k3s-bootstrap`. Reloader ignores ConfigMaps, so a `config.alloy`
  change needs `kubectl -n monitoring rollout restart deployment alloy`.
  Grafana has Loki as a datasource (`argocd/grafana/externalsecret.yaml`).
- `argocd/ingress/` (Argo CD, a small Helm chart: every route in
  `values.yaml`, rendered into Traefik routers and middlewares; the ACME
  credentials come from `templates/externalsecret.yaml`) -- moving `shared_ingress` to k3s, the last and
  highest-stakes piece of this whole project: unlike every service
  before it, there's no safe additive window (only one thing can hold
  the homeserver's own physical ports 80/443), so if this cutover ever
  goes wrong, every public service goes dark at once, not one at a
  time. A new, dedicated Traefik Deployment, not a reconfiguration of
  k3s's own bundled instance (`k3s_node`'s own README deliberately
  keeps that at defaults) -- k3s's bundled Traefik gets `--disable
  traefik` on `k3s-node-1`'s own systemd unit once this one takes
  over cleanly. Static/dynamic config mirrors `home-infra`'s own
  `shared_ingress` role's templates nearly verbatim (the lowest-risk
  possible translation, not a rewrite into Kubernetes'
  `IngressRoute`/`Middleware` CRDs), but every backend now routes to
  this cluster's own in-cluster Service DNS names directly
  (`grafana-svc`, `landing-page-svc`) instead of bouncing back out
  through the node's own external address -- this Traefik lives
  inside the cluster now, so it doesn't need to. Nextcloud AIO's own
  Apache is the one backend that isn't a k3s Service at all (stays on
  the homeserver permanently); Traefik's route targets
  `http://192.168.101.1:11000` directly (the file provider takes any
  URL). It used to go through a selector-less Service plus Endpoints,
  but Argo CD excludes Endpoints by default, so it couldn't manage that. A small PVC persists `/letsencrypt/acme.json` across
  Pod restarts (unlike Alertmanager's/Grafana's own "start fresh, no
  PVC" choice) -- losing it would mean re-issuing every certificate
  every time, a real, avoidable rate-limit risk. ACME uses DNS-01, not
  the original role's own TLS-ALPN-01 -- TLS-ALPN-01 always validates
  against the domain's real port 443, tying cert issuance to the exact
  moment 80/443 get cut over, with no way to rehearse it safely first.
  DNS-01 decouples the two entirely (real certs issued and renewed
  against `jkandler.de`'s own Route53 zone with no port ever touched),
  via lego's own route53 provider and a dedicated, narrowly-scoped IAM
  user (`dyndns`'s own `traefik-acme-dns01`, `route53:
  ChangeResourceRecordSets`/`GetChange` on that one zone only). Public
  traffic
  actually reaching this Service at all still needs `home-infra`'s
  own new `k3s_ingress_forward` role (iptables DNAT on the
  homeserver, since the k3s VM's network is deliberately unreachable
  from the LAN otherwise) -- see that role's own README, and the plan
  in `home-infra`'s own history for the full staged rollout sequence.
- `secrets.tf` -- reads every secret this repo's modules need straight
  from AWS Secrets Manager at plan/apply time (`data
  "aws_secretsmanager_secret_version"` + `jsondecode`), not a
  `TF_VAR_*` a human or CI has to supply. Replaced the old
  `secrets.sops.yml` / `scripts/export-tf-vars.sh` flow entirely
  2026-09-09 (the SOPS-to-Secrets-Manager cutover) -- both
  are gone, including this repo's own separate SOPS vault.
## Argo CD

Argo CD deploys every app under `argocd/`, one Application each
(node-exporter lives in k3s-bootstrap, Stalwart's API settings in the
stalwart-config repo). Argo CD itself, its project, the
Applications and its RBAC live in `k3s-bootstrap` (`argocd.tf`, see its
docs' "Argo CD"). This repo holds its side of the UI on
`argo.jkandler.de`: the `argo` route in `argocd/ingress/values.yaml` (forward-auth, which
`argocd/authelia`'s config limits to `user:julian`) and the `argocd` OIDC client
(`julian_only`, PKCE). Its secret pair rotates with
`scripts/rotate-oidc-client-secret.sh argocd`, which applies
`k3s-bootstrap` afterwards.

- `argocd/<app>/` holds plain Kustomize manifests; `argocd/ingress` is a
  small Helm chart instead, so a route stays one entry in its
  `values.yaml`. Argo CD syncs `main` automatically, with prune and
  self-heal, so the merge is the only gate.
- Argo CD may change only the objects `k3s-bootstrap` names in its Role,
  so a new object here needs a `k3s-bootstrap` change first. ConfigMaps
  keep static names for that reason.
- **Secrets come from ESO** (ADR 0032, every app since 2026-11-15). An
  app with Secrets has an `externalsecret.yaml` (keys from Secrets
  Manager through its namespace's SecretStore, refreshed hourly; composite
  files such as Authelia's `configuration.yml` are ESO templates) and the
  Deployment annotation `secret.reloader.stakater.com/reload: <secrets>`,
  so Reloader restarts it after a rotation (sankey-export is a CronJob and
  reads its Secrets at each run). Argo CD manages only the
  ExternalSecrets, never a Secret. Each module keeps only `removed`
  blocks. To pick up a rotation at once:
  `kubectl -n <ns> annotate externalsecret <name> force-sync=$(date +%s) --overwrite`.
- **PVCs** live in each app's `storage.yaml` with `Prune=false,Delete=false`,
  and Argo CD's Role grants no `delete` on PVCs at all, so no sync can
  remove a volume; `create` stays, for a rebuilt cluster. Dynamically
  provisioned ones (Vaultwarden's and Authelia's data) leave `volumeName`
  out, so a rebuild provisions fresh.
- The apps came from this repo's former Terraform modules: `removed`
  blocks forgot the live objects without destroying them, and Argo CD
  and ESO adopted them. Before changing a manifest, `kubectl diff -k
  argocd/<app>` against the live objects shows what a sync will do.
- Handing an app back: put the module back, `import` its objects, then
  remove its Application and names from `k3s-bootstrap`. Applications
  have no finalizer, so deleting one leaves its objects running.

## CI

`checks.yml`'s required `Validate` check renders every app under
`argocd/` the way Argo CD does (`kubectl kustomize`, `helm template` for
the ingress chart). Trivy scans
the manifests and images (`security-scan.yml`). `build-sankey-export.yml`
builds and pushes sankey-export's image on the in-cluster runner, the
only job that needs it; that runner has no cluster or AWS access any
more. Nothing applies anything: Argo CD syncs `main`.

`blocky_postgres_password` is rotated by hand, yearly or on suspicion
(`scripts/rotate-blocky-postgres-password.sh`, from the laptop with
`aws login`): it ALTERs the role through `kubectl exec` into Blocky's
Postgres sidecar, writes the new value to Secrets Manager and forces ESO
to sync, so Reloader restarts Blocky and Grafana. Until 2026-11-15 a
monthly workflow did this unattended on the in-cluster runner; it moved
off CI with Blocky's Secrets (it had also failed since the move to ARC,
whose runner image has no AWS CLI).

## Running it from your laptop

Only the rotation scripts under `scripts/` run from the laptop. They need
`aws login` (to write Secrets Manager) and `kubectl` against the cluster,
whose network (`192.168.101.0/24`) exists only on the homeserver, so
through an SSH tunnel to the apiserver (the scripts open it themselves):

```
ssh -L 6443:192.168.101.10:6443 julian@192.168.178.100
```

and, once, the kubeconfig k3s generates (its `server:` is already
`https://127.0.0.1:6443`, which the tunnel serves):

```
scp -o ProxyJump=julian@192.168.178.100 ansible@192.168.101.10:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-node-1.yaml
```

The own image's digest is pinned in its manifest (sankey-export,
`:main@sha256:…`); Renovate proposes each new build's.
The former Terraform state stays in the `jkandler-terraform-state`
bucket under `k3s-apps/` as an archive.

## Relationship to the Ansible-managed originals

`home.jkandler.de` was cut over 2026-08-29 and the old `landing_page`
role deleted outright. `torrent.jkandler.de` (cut over 2026-08-30,
Deluge then qBittorrent) was retired outright on 2026-11-15, along with
the `deluge` role's host prerequisites and its data. `ai.jkandler.de`
(Open WebUI and `home_agent`, cut over 2026-08-30) was retired outright
on 2026-11-16, data included. See
`home-infra-docs/docs/history.md`'s "k3s learning cluster" section for
the full cutover history.
