# Installs Argo CD, then applies the root Application. After that the cluster
# manages itself: Argo CD syncs apps/overlays/<env>, which is an app-of-apps
# pointing at everything else in this repository.
#
# Argo CD's own configuration lives in values/ and is applied here only to
# bootstrap. The argocd Application in apps/base takes ownership afterwards,
# so Argo CD ends up managing its own installation.

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  # Same values the Argo CD Application uses, so the handover is a no-op
  # rather than Argo CD immediately reporting itself OutOfSync.
  values = [
    file("${path.root}/../values/common/argocd.yaml"),
    file("${path.root}/../values/${var.environment}/argocd.yaml"),
  ]

  # CRDs must exist before the root Application can be created.
  wait          = true
  wait_for_jobs = true
  timeout       = 600
  atomic        = true
}

# Applied with kubectl rather than kubernetes_manifest: that resource needs the
# Application CRD present at *plan* time, which it cannot be on a cluster this
# same apply is creating. This is the standard bootstrap chicken-and-egg.
resource "null_resource" "root_application" {
  triggers = {
    environment = var.environment
    repo_url    = var.repo_url
    revision    = var.target_revision
    manifest    = filesha256("${path.root}/../bootstrap/root/${var.environment}.yaml")
    argocd      = helm_release.argocd.metadata[0].revision
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG='${var.kubeconfig_path}'

      # Wait for the CRD to be established, not merely created.
      kubectl wait --for=condition=established --timeout=120s \
        crd/applications.argoproj.io

      kubectl apply -n argocd -f '${path.root}/../bootstrap/root/${var.environment}.yaml'
    EOT
  }

  depends_on = [helm_release.argocd]
}
