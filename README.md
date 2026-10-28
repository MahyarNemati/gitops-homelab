# gitops-homelab

[![CI](https://github.com/MahyarNemati/gitops-homelab/actions/workflows/ci.yml/badge.svg)](https://github.com/MahyarNemati/gitops-homelab/actions/workflows/ci.yml)

A k3s cluster that rebuilds itself from this repository. OpenTofu provisions
the nodes and installs Argo CD; everything after that — ingress, certificates,
sealed secrets, monitoring, logging and the demo workload — is synced from
Git by Argo CD.

Two environments, `dev` and `prod`, share one set of base manifests through
Kustomize overlays.

## Rebuild from nothing

```bash
cp terraform/environments/dev.tfvars my.tfvars    # set your node addresses
tofu -chdir=terraform init
tofu -chdir=terraform apply -var-file=../my.tfvars

export KUBECONFIG=$PWD/kubeconfig-dev
kubectl get nodes
kubectl -n argocd get applications
```

That is the whole process. Terraform's responsibility ends at the root
Application; from there the cluster converges on its own.

See [docs/REBUILD.md](docs/REBUILD.md) for the bare-metal runbook.

## How the pieces fit

```
  OpenTofu
     │  1. installs k3s over SSH (server + agents)
     │  2. fetches the kubeconfig, rewriting 127.0.0.1 -> node address
     │  3. helm install argo-cd
     │  4. kubectl apply bootstrap/root/<env>.yaml
     ▼
  Argo CD ──── watches apps/overlays/<env>  (app-of-apps)
     │
     ├─▶ sealed-secrets      decryption controller
     ├─▶ traefik             ingress
     ├─▶ cert-manager        + ClusterIssuers per environment
     ├─▶ kube-prometheus     Prometheus, Alertmanager, Grafana
     ├─▶ loki + alloy        log aggregation and shipping
     ├─▶ monitoring-config   dashboards and alert rules
     └─▶ demo                podinfo with HPA, PDB, NetworkPolicies
```

```
apps/
  base/                  one Argo CD Application per platform component
  components/env/        shared Kustomize component applied by both overlays
  overlays/{dev,prod}/   the app-of-apps root for each environment
bootstrap/
  argocd/                values used only for the initial Helm install
  root/{dev,prod}.yaml   the single Application that starts everything
manifests/
  demo/                  base + overlays for the demo workload
  monitoring/            dashboards, Prometheus rules
  cluster-issuers/        selfsigned (dev) vs Let's Encrypt (prod)
values/
  common/                Helm values shared by both environments
  {dev,prod}/            per-environment overrides
terraform/
  modules/k3s/           k3s install over SSH, kubeconfig fetch
  modules/platform/      Argo CD install + root Application
  environments/          example tfvars
scripts/                 dashboard and alert-rule validators used by CI
```

## Decisions worth explaining

### Argo CD manages Argo CD

OpenTofu installs Argo CD with the **same values** the `argocd` Application in
`apps/base` uses, then applies the root Application — which includes Argo CD
itself. After bootstrap, Argo CD owns its own installation and Terraform never
touches it again.

Using identical values at both steps is the detail that makes this work. If
they differed, Argo CD would come up and immediately report itself
`OutOfSync` against its own manifest, which is a confusing first impression of
a healthy cluster.

### Terraform provisions, GitOps configures

Terraform is deliberately limited to things that cannot be done from inside the
cluster: installing k3s on bare metal, getting a kubeconfig, and creating the
first Application. Everything expressible as a Kubernetes object lives in Git
and is applied by Argo CD.

This matters because the two tools have incompatible reconciliation models.
Terraform reconciles when you run it; Argo CD reconciles continuously. Managing
the same object with both gives you a fight, where `selfHeal` reverts your
`tofu apply` and you get to debug that.

### The bundled Traefik and ServiceLB are disabled

`k3s_server_args` passes `--disable=traefik --disable=servicelb`, because
Traefik is installed through Argo CD. Leaving k3s's copy enabled means two
ingress controllers contending for `:80`, which presents as intermittent 404s
and takes an afternoon to diagnose.

### Secrets are sealed, not absent

Sealed Secrets lets the **encrypted** secret live in Git. Only the controller's
private key — which never leaves the cluster — can decrypt it, so the
repository is safe to make public and a rebuild does not depend on a secret
store you forgot to back up.

The catch, stated plainly: that private key **is** the backup. Lose it and
every SealedSecret in this repository is unrecoverable ciphertext. Back up the
sealed-secrets controller key separately.

### Default-deny networking on the demo app

`manifests/demo/base/networkpolicies.yaml` denies all ingress and egress, then
allows only what podinfo needs. Default-deny is the only policy posture that
fails safe: with default-allow, a forgotten rule is an open path, and nothing
tells you.

### Dev and prod differ only in overlays

The same base manifests produce both environments. `dev` uses a self-signed
ClusterIssuer and smaller resource requests; `prod` uses Let's Encrypt and real
replica counts. Anything that must differ is an overlay patch, so "it works in
dev" means something.

## What CI actually validates

Since a live cluster is not available in CI, every check is one that catches a
real class of mistake statically:

| Job | Catches |
|---|---|
| yaml lint | malformed YAML anywhere |
| overlays build | a `kustomization.yaml` that does not build — otherwise Argo CD is the thing that discovers it, at sync time |
| manifests validate | schema errors, against Kubernetes 1.31 plus the community CRD catalogue for Argo CD, ServiceMonitor, cert-manager and SealedSecret kinds |
| grafana dashboards | malformed dashboard JSON, and panels with no query targets — a bad dashboard imports as a blank panel with no error shown anywhere |
| prometheus rules | invalid PromQL, by unwrapping `PrometheusRule.spec` and running `promtool`. An unparseable expression otherwise means an alert that silently never fires |
| opentofu fmt/validate | HCL errors |

## Honest limitations

- **No live apply has been performed from this repository.** Everything is
  statically validated and the manifests build, but the nodes in
  `terraform/environments/*.tfvars` are examples. Treat the first apply as the
  real test.
- **OpenTofu, not Terraform.** They are CLI-compatible here; OpenTofu is used
  because Terraform's licence change removed it from Homebrew core, and the
  configuration uses nothing OpenTofu-specific.
- **Single control-plane node.** No etcd HA. Appropriate for a homelab,
  inappropriate for anything that matters.
- **The k3s install is remote-exec over SSH**, so it is imperative glue rather
  than declarative infrastructure. The k3s installer is idempotent and the
  resource triggers re-run it on version or flag changes, but this is not the
  same guarantee as a cloud provider's API.
- **No backup or restore story.** Persistent volumes and the sealed-secrets key
  need a separate plan.

## License

Apache-2.0 — see [LICENSE](LICENSE).
