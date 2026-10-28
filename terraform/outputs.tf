output "kubeconfig_path" {
  description = "Path to the fetched kubeconfig."
  value       = module.k3s.kubeconfig_path
}

output "server_host" {
  description = "Control-plane address."
  value       = local.advertise_address
}

output "node_token" {
  description = "k3s node token used by agents to join."
  value       = random_password.node_token.result
  sensitive   = true
}

output "next_steps" {
  description = "What to do once apply finishes."
  value       = <<-EOT
    export KUBECONFIG=${abspath(var.kubeconfig_path)}

    kubectl get nodes
    kubectl -n argocd get applications

    # Argo CD admin password:
    kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d; echo

    kubectl -n argocd port-forward svc/argocd-server 8080:443
  EOT
}
