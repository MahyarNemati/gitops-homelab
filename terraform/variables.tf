variable "environment" {
  description = "Which overlay Argo CD should track: dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "server" {
  description = "The k3s control-plane node."
  type = object({
    host = string
    user = optional(string, "root")
    # Address other nodes and your kubeconfig should use. Defaults to host.
    advertise_address = optional(string)
  })
}

variable "agents" {
  description = "Worker nodes that join the server. May be empty for a single-node cluster."
  type = list(object({
    host = string
    user = optional(string, "root")
  }))
  default = []
}

variable "ssh_private_key_path" {
  description = "Private key used to reach every node."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "k3s_version" {
  description = "k3s release channel or pinned version, e.g. v1.31.4+k3s1."
  type        = string
  default     = "v1.31.4+k3s1"
}

variable "k3s_server_args" {
  description = <<-EOT
    Extra flags for the k3s server. The defaults disable the bundled Traefik
    and ServiceLB because this repository installs Traefik through Argo CD --
    leaving both enabled means two ingress controllers fighting over :80.
  EOT
  type        = list(string)
  default = [
    "--disable=traefik",
    "--disable=servicelb",
    "--write-kubeconfig-mode=0644",
  ]
}

variable "kubeconfig_path" {
  description = "Where to write the fetched kubeconfig."
  type        = string
  default     = "./kubeconfig"
}

variable "repo_url" {
  description = "Git repository Argo CD syncs from."
  type        = string
  default     = "https://github.com/MahyarNemati/gitops-homelab.git"
}

variable "target_revision" {
  description = "Branch or tag Argo CD tracks."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version used only to bootstrap Argo CD itself."
  type        = string
  default     = "7.8.2"
}
