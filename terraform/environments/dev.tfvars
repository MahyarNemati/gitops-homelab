environment = "dev"

server = {
  host = "192.168.1.10"
  user = "root"
}

agents = [
  { host = "192.168.1.11" },
  { host = "192.168.1.12" },
]

ssh_private_key_path = "~/.ssh/id_ed25519"
kubeconfig_path      = "./kubeconfig-dev"
target_revision      = "main"
