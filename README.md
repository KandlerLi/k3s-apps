# k3s-apps

Workloads for a personal k3s cluster, such as the ingress, Authelia, Grafana,
Headlamp, Blocky and Stalwart: one directory of manifests per app under
`argocd/`, which Argo CD syncs from `main`. Secrets come from AWS Secrets
Manager through the External Secrets Operator.

## Documentation

Setup, operations and design notes, including the sections code comments refer to:
[`docs/README.md`](docs/README.md)
