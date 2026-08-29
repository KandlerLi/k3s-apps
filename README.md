# k3s-apps

Terraform-managed workloads for the personal k3s learning cluster
(`k3s-node-1`, see the `k3s_node` role in `home-infra`). This is a
**learning project**, kept deliberately separate from `home-infra`'s
production Ansible-managed services.

Uses Terraform's `kubernetes` provider directly against the cluster,
instead of plain `kubectl apply -f` -- a deliberate choice to keep one
IaC tool (Terraform) consistent across the whole homelab, at the known
cost of a second reconciler alongside Kubernetes' own control loop (see
this repo's commit history / conversation history for the trade-off).

## What's here

- `landing_page.tf` -- the k3s-native equivalent of `home-infra`'s
  `ansible/roles/landing_page` role: same pinned image digest, same
  mount point, same real content (`files/index.html`, `files/style.css`,
  pulled from the live homeserver, not fabricated).

## Running it

Runs **on the k3s VM itself** (`ansible@k3s-node-1`, reachable via
`ssh -J julian@<homeserver> ansible@192.168.101.10`), not from the
homeserver or your laptop -- that's where both `kubectl` and now
`terraform` are already installed, and where the kubeconfig
(`/etc/rancher/k3s/k3s.yaml`) `provider.tf` points at already lives.

Copy this repo onto the VM, then:

```
terraform init
terraform plan
terraform apply
```

State is local to the VM for now (`terraform.tfstate`, gitignored) --
there's no S3 backend like every other Terraform repo in this homelab
uses, because that would mean putting AWS credentials on a learning VM
for no real benefit yet. Move to a remote backend later if/when this
cluster holds something worth protecting against the VM's disk being
lost.

**Before the first `terraform apply`**: if you built `landing-page`
by hand with `kubectl create`/`kubectl apply` first (the learning path
that led here), delete those objects first -- Terraform doesn't know
about resources it didn't create, and will fail with "already exists"
on names it collides with:

```
kubectl delete deployment landing-page
kubectl delete service landing-page-svc
kubectl delete ingress landing-page-ingress
kubectl delete configmap landing-page-html
```

## Relationship to the Ansible-managed original

The real `landing_page` role on the homeserver, and `landing.jkandler.de`
DNS/Traefik routing, are both untouched by this. This is a parallel,
private copy running only on the k3s VM's own isolated network
(`192.168.101.0/24`), unreachable from anywhere else. Cutting over the
real domain to point here -- and retiring the Ansible role -- is a
deliberate later step, not something this repo does on its own.
