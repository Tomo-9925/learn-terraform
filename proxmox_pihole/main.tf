terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "~> 2.9.11"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.pm_api_url
  pm_user = var.pm_user
  pm_password = var.pm_pass
  pm_tls_insecure = true

  pm_log_enable   = true
  pm_log_file     = "terraform-plugin-proxmox.log"
  pm_debug        = true
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}

resource "proxmox_lxc" "pi-hole" {
  target_node = var.pm_node
  vmid = 246
  cores = 1
  memory = 512
  ostemplate = "ds220plus:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz"
  hostname = "Pi-hole"
  unprivileged = true
  password = var.lxc_pass
  ssh_public_keys = file(var.ssh_public_key_path)
  onboot = true
  start = true

  features {
    keyctl = true
    nesting = true
  }

  rootfs {
    storage = "local-lvm"
    size = "8G"
  }

  network {
    name = "eth0"
    bridge = "vmbr0"
    gw = "192.168.3.1"
    ip = "192.168.3.246/24"
    ip6 = "auto"
  }

  network {
    name = "eth1"
    bridge = "vmbr1"
    ip = "10.11.10.1/16"
    ip6 = "auto"
    mtu = 1280
  }
}

resource "local_file" "ansible_inventory" {
  depends_on = [
    proxmox_lxc.pi-hole
  ]
  content = templatefile("${path.module}/host.tmpl", {
    pi-hole_ip_addresses = [split("/", proxmox_lxc.pi-hole.network[0].ip)[0]]
  })
  filename = "staging"
}

resource "null_resource" "ansible-playbook" {
  depends_on = [
    local_file.ansible_inventory
  ]
  provisioner "local-exec" {
    command = format("ansible-playbook -i staging -u root --private-key %s -e 'WEBPASSWORD=%s FTLCONF_LOCAL_IPV4=%s PIHOLE_DNS=1.1.1.1;8.8.8.8' pi-hole.yml",
        var.ssh_private_key_path,
        var.pi-hole_pass,
        split("/", proxmox_lxc.pi-hole.network[0].ip)[0],
      )
  }
}
