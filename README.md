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
terraform plan
terraform apply
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

**Before the first `terraform apply`**: if you built `landing-page`
by hand with `kubectl create`/`kubectl apply` first (the learning path
that led here), delete those objects first -- Terraform doesn't know
about resources it didn't create, and will fail with "already exists"
on names it collides with. Run this against the same tunnel/kubeconfig:

```
KUBECONFIG=~/.kube/k3s-node-1.yaml kubectl delete deployment landing-page
KUBECONFIG=~/.kube/k3s-node-1.yaml kubectl delete service landing-page-svc
KUBECONFIG=~/.kube/k3s-node-1.yaml kubectl delete ingress landing-page-ingress
KUBECONFIG=~/.kube/k3s-node-1.yaml kubectl delete configmap landing-page-html
```

## Relationship to the Ansible-managed original

The real `landing_page` role on the homeserver, and `landing.jkandler.de`
DNS/Traefik routing, are both untouched by this. This is a parallel,
private copy running only on the k3s VM's own isolated network,
reachable only through the tunnel above, unreachable from anywhere else.
Cutting over the real domain to point here -- and retiring the Ansible
role -- is a deliberate later step, not something this repo does on its
own.
