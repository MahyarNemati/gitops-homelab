# Rebuild runbook

From bare metal to a converged cluster. Assumes three machines (one server,
two agents) running a recent Debian or Ubuntu.

## 1. Prepare the nodes

On every node:

```bash
# k3s needs these off, and a reboot-persistent swap-off.
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Reachable by SSH as root with your key.
sudo mkdir -p /root/.ssh
sudo tee -a /root/.ssh/authorized_keys < ~/.ssh/id_ed25519.pub
```

Confirm from your workstation:

```bash
for h in 192.168.1.10 192.168.1.11 192.168.1.12; do
  ssh -o BatchMode=yes root@$h 'hostname; uname -r'
done
```

If that does not work, nothing below will.

## 2. Provision

```bash
cp terraform/environments/dev.tfvars my.tfvars
$EDITOR my.tfvars          # node addresses, key path, kubeconfig path

tofu -chdir=terraform init
tofu -chdir=terraform plan  -var-file=../my.tfvars
tofu -chdir=terraform apply -var-file=../my.tfvars
```

What this does, in order: installs k3s on the server, waits for `/readyz`,
joins the agents, fetches and rewrites the kubeconfig, installs Argo CD, and
applies `bootstrap/root/dev.yaml`.

## 3. Watch it converge

```bash
export KUBECONFIG=$PWD/kubeconfig-dev

kubectl get nodes                       # all Ready
kubectl -n argocd get applications -w   # Synced / Healthy
```

First sync takes a few minutes: cert-manager and the Prometheus stack pull a
lot of images.

### Argo CD UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  (user: admin)
```

### Grafana

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Dashboards from `manifests/monitoring/base/dashboards/` are loaded by the
sidecar: cluster overview, demo RED metrics, and GitOps sync status.

## 4. Sealed secrets

Install the CLI, then seal a secret against **this** cluster's key:

```bash
brew install kubeseal

kubectl create secret generic my-secret \
  --from-literal=token=s3cr3t --dry-run=client -o yaml \
  | kubeseal --controller-namespace sealed-secrets --format yaml \
  > manifests/demo/base/my-sealedsecret.yaml

git add manifests/demo/base/my-sealedsecret.yaml && git commit && git push
```

Argo CD syncs it and the controller decrypts it in-cluster. The plaintext never
enters Git.

**Back up the controller key.** It is the only thing that can decrypt anything
in this repository:

```bash
kubectl -n sealed-secrets get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key.backup.yaml   # store this somewhere safe
```

## 5. Teardown

```bash
tofu -chdir=terraform destroy -var-file=../my.tfvars
```

`destroy` removes Terraform's own resources but does **not** uninstall k3s from
the nodes, because the install was done by remote-exec. To wipe a node:

```bash
ssh root@192.168.1.10 /usr/local/bin/k3s-uninstall.sh       # server
ssh root@192.168.1.11 /usr/local/bin/k3s-agent-uninstall.sh # agent
```

## Troubleshooting

**Agents not joining.** The token must match and `:6443` must be reachable from
the agent:

```bash
ssh root@<agent> 'journalctl -u k3s-agent -n 50 --no-pager'
```

**Applications stuck Progressing.** Usually an image pull or a CRD that has not
been established yet:

```bash
kubectl -n argocd get app <name> -o jsonpath='{.status.conditions}' | jq
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

**Certificates not issuing.** In `dev` the issuer is self-signed and should be
instant; in `prod`, check the challenge:

```bash
kubectl get certificates,certificaterequests,challenges -A
```

**Argo CD reports itself OutOfSync right after bootstrap.** The Helm values
used by Terraform have drifted from `values/common/argocd.yaml`. They must stay
identical — see the README.
