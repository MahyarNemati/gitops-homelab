# Provisions k3s on SSH-reachable hosts, then hands the cluster over to
# Argo CD. Everything after the root Application is managed by GitOps, not by
# Terraform: Terraform's job ends once the cluster can sync itself.

locals {
  advertise_address = coalesce(var.server.advertise_address, var.server.host)
}

# Configured here rather than inside modules/platform: a module carrying its
# own provider configuration is a "legacy module" and may not be called with
# depends_on, which the Argo CD bootstrap ordering requires.
#
# The kubeconfig does not exist until module.k3s has run. That is fine because
# the helm provider connects lazily, at apply time, not at plan time.
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# The node token is generated here rather than left to k3s so agents can be
# provisioned in the same apply without reading it back off the server first.
resource "random_password" "node_token" {
  length  = 48
  special = false
}

module "k3s" {
  source = "./modules/k3s"

  server               = var.server
  agents               = var.agents
  ssh_private_key_path = var.ssh_private_key_path
  k3s_version          = var.k3s_version
  server_args          = var.k3s_server_args
  node_token           = random_password.node_token.result
  advertise_address    = local.advertise_address
  kubeconfig_path      = var.kubeconfig_path
}

module "platform" {
  source = "./modules/platform"

  kubeconfig_path      = module.k3s.kubeconfig_path
  environment          = var.environment
  repo_url             = var.repo_url
  target_revision      = var.target_revision
  argocd_chart_version = var.argocd_chart_version

  # Argo CD cannot be installed before the API server answers.
  depends_on = [module.k3s]
}
