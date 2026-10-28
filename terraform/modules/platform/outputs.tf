output "argocd_namespace" {
  description = "Namespace Argo CD was installed into."
  value       = helm_release.argocd.namespace
}

output "root_application" {
  description = "Root Application manifest that was applied."
  value       = "bootstrap/root/${var.environment}.yaml"
  depends_on  = [null_resource.root_application]
}
