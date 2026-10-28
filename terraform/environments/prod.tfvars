environment = "prod"

server = {
  host = "10.0.0.10"
  user = "root"
  # Set when nodes reach the server on a different address than you do.
  advertise_address = "10.0.0.10"
}

agents = [
  { host = "10.0.0.11" },
  { host = "10.0.0.12" },
  { host = "10.0.0.13" },
]

ssh_private_key_path = "~/.ssh/id_ed25519"
kubeconfig_path      = "./kubeconfig-prod"

# Pin a tag in production so a push to main cannot change the cluster.
target_revision = "main"
