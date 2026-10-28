variable "server" {
  type = object({
    host              = string
    user              = optional(string, "root")
    advertise_address = optional(string)
  })
}

variable "agents" {
  type = list(object({
    host = string
    user = optional(string, "root")
  }))
  default = []
}

variable "ssh_private_key_path" { type = string }
variable "k3s_version" { type = string }
variable "server_args" { type = list(string) }
variable "advertise_address" { type = string }
variable "kubeconfig_path" { type = string }

variable "node_token" {
  type      = string
  sensitive = true
}
