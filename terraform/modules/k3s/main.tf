# Installs k3s over SSH. This is deliberately not a cloud-specific module: a
# homelab's nodes are whatever hardware is on the shelf, so the only
# requirement is an SSH-reachable host with a sudo-less root login.
#
# Idempotence comes from the k3s installer itself, which is safe to re-run.
# The triggers below mean a version or flag change re-runs the installer
# rather than silently leaving the old configuration in place.

locals {
  private_key = file(pathexpand(var.ssh_private_key_path))

  server_flags = join(" ", concat(
    var.server_args,
    ["--node-external-ip=${var.advertise_address}"],
  ))
}

resource "null_resource" "server" {
  triggers = {
    host        = var.server.host
    k3s_version = var.k3s_version
    flags       = local.server_flags
    # Changing the token means every node has to be re-bootstrapped.
    token = sha256(var.node_token)
  }

  connection {
    type        = "ssh"
    host        = var.server.host
    user        = var.server.user
    private_key = local.private_key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # INSTALL_K3S_SKIP_START=false is the default; being explicit documents
      # that this both installs and starts the service.
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${var.k3s_version}' K3S_TOKEN='${var.node_token}' INSTALL_K3S_EXEC='server ${local.server_flags}' sh -s -",
      # Wait for the API server rather than assuming the installer's exit code
      # means ready; agents joining too early fail in a confusing way.
      "for i in $(seq 1 60); do k3s kubectl get --raw='/readyz' >/dev/null 2>&1 && break; sleep 5; done",
      "k3s kubectl get --raw='/readyz' >/dev/null",
    ]
  }
}

resource "null_resource" "agents" {
  for_each = { for a in var.agents : a.host => a }

  triggers = {
    host        = each.value.host
    k3s_version = var.k3s_version
    server      = var.advertise_address
    token       = sha256(var.node_token)
  }

  connection {
    type        = "ssh"
    host        = each.value.host
    user        = each.value.user
    private_key = local.private_key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${var.k3s_version}' K3S_URL='https://${var.advertise_address}:6443' K3S_TOKEN='${var.node_token}' sh -s -",
    ]
  }

  depends_on = [null_resource.server]
}

# Pull the kubeconfig off the server and rewrite the server address, which k3s
# writes as 127.0.0.1 and which is therefore useless from anywhere else.
resource "null_resource" "fetch_kubeconfig" {
  triggers = {
    server_id = null_resource.server.id
    path      = var.kubeconfig_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      umask 077
      ssh -i '${pathexpand(var.ssh_private_key_path)}' \
          -o StrictHostKeyChecking=accept-new \
          -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
          '${var.server.user}@${var.server.host}' \
          'cat /etc/rancher/k3s/k3s.yaml' \
        | sed 's#https://127.0.0.1:6443#https://${var.advertise_address}:6443#' \
        > '${var.kubeconfig_path}'
      chmod 600 '${var.kubeconfig_path}'
    EOT
  }

  depends_on = [null_resource.server]
}
