terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.proxmox_node
  vm_id         = var.vm_id
  description   = var.description
  unprivileged  = true
  start_on_boot = true
  started       = true

  initialization {
    hostname = "lxc-${var.name}"

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${var.ip_eth0}/24"
        gateway = var.network_gateway
      }
    }

    ip_config {
      ipv4 {
        address = "${var.ip_eth1}/24"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_dedicated
    swap      = var.memory_swap
  }

  features {
    nesting = true
    # keyctl requires root@pam; configure manually via Proxmox UI if needed
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "ubuntu"
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  network_interface {
    name   = "eth1"
    bridge = "vmbr1"
  }

  lifecycle {
    ignore_changes = [mount_point]
  }
}

locals {
  has_provisioner = length(var.mounts) > 0 || var.gpu_passthrough

  mount_commands = [
    for i, mount in var.mounts :
    "sudo /usr/sbin/pct set ${proxmox_virtual_environment_container.this.vm_id} -mp${i} ${mount.host},mp=${mount.mp}${mount.ro ? ",ro=1" : ""}"
  ]

  gpu_commands = var.gpu_passthrough ? [
    "grep -q 'lxc.cgroup2.devices.allow: c 226:0' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 226:0 rwm' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.cgroup2.devices.allow: c 226:128' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 226:128 rwm' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.mount.entry: /dev/dri' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
  ] : []
}

resource "null_resource" "mounts" {
  count      = local.has_provisioner ? 1 : 0
  depends_on = [proxmox_virtual_environment_container.this]

  triggers = {
    mac_address = proxmox_virtual_environment_container.this.network_interface[0].mac_address
    mounts      = join(",", [for m in var.mounts : "${m.host}:${m.mp}${m.ro ? ":ro" : ""}"])
    gpu         = tostring(var.gpu_passthrough)
  }

  connection {
    type        = "ssh"
    host        = var.proxmox_host_ip
    user        = var.proxmox_ssh_username
    private_key = file(pathexpand(var.terraform_ssh_private_key))
    agent       = false
  }

  provisioner "remote-exec" {
    inline = concat(
      ["sleep 10"],
      local.mount_commands,
      local.gpu_commands,
      [
        "sudo /usr/sbin/pct reboot ${proxmox_virtual_environment_container.this.vm_id}",
        "until sudo /usr/sbin/pct status ${proxmox_virtual_environment_container.this.vm_id} | grep -q 'status: running'; do sleep 2; done",
      ]
    )
  }
}
