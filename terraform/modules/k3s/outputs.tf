output "kubeconfig_path" {
  description = "Local path to the rewritten kubeconfig."
  value       = var.kubeconfig_path
  depends_on  = [null_resource.fetch_kubeconfig]
}

output "server_id" {
  description = "Identity of the server provisioning run, for ordering."
  value       = null_resource.server.id
}
