# k3s-apps

Terraform-managed workloads for a personal k3s cluster, such as the ingress,
Authelia, Grafana, Headlamp, Blocky and Stalwart. Each service is one module
under `modules/`, wired together by the root `main.tf`, and CI applies changes
on merge to `main`.

## Documentation

Setup, operations and design notes, including the sections code comments refer to:
[`docs/README.md`](docs/README.md)
