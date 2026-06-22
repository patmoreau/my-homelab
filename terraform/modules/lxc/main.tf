terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
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

    dynamic "ip_config" {
      for_each = var.vlan_interfaces
      content {
        ipv4 {
          address = "dhcp"
        }
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
    type             = var.os_type
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.hwaddr_eth0
  }

  network_interface {
    name   = "eth1"
    bridge = "vmbr1"
  }

  dynamic "network_interface" {
    for_each = var.vlan_interfaces
    content {
      name        = network_interface.value.name
      bridge      = network_interface.value.bridge
      vlan_id     = network_interface.value.vlan
      mac_address = network_interface.value.mac_address
    }
  }

  lifecycle {
    ignore_changes = [mount_point]
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "uid"
      container_id = 0
      host_id      = 100000
      size         = var.nas_idmap.uid
    }
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "uid"
      container_id = var.nas_idmap.uid
      host_id      = coalesce(var.nas_idmap.host_uid, var.nas_idmap.uid)
      size         = 1
    }
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "uid"
      container_id = var.nas_idmap.uid + 1
      host_id      = 100000 + var.nas_idmap.uid + 1
      size         = 65536 - var.nas_idmap.uid - 1
    }
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "gid"
      container_id = 0
      host_id      = 100000
      size         = var.nas_idmap.gid
    }
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "gid"
      container_id = var.nas_idmap.gid
      host_id      = coalesce(var.nas_idmap.host_gid, var.nas_idmap.gid)
      size         = 1
    }
  }

  dynamic "idmap" {
    for_each = var.nas_idmap != null ? [1] : []
    content {
      type         = "gid"
      container_id = var.nas_idmap.gid + 1
      host_id      = 100000 + var.nas_idmap.gid + 1
      size         = 65536 - var.nas_idmap.gid - 1
    }
  }
}

locals {
  has_provisioner = length(var.mounts) > 0 || var.gpu_passthrough || var.nas_idmap != null || var.gpu_render_gid != null

  _idmap_uid = var.nas_idmap != null ? var.nas_idmap.uid : 0
  _idmap_gid = var.nas_idmap != null ? var.nas_idmap.gid : 0


  mount_commands = [
    for i, mount in var.mounts :
    "sudo /usr/sbin/pct set ${proxmox_virtual_environment_container.this.vm_id} -mp${i} ${coalesce(mount.volume, mount.host)},mp=${mount.mp}${mount.ro ? ",ro=1" : ""}${mount.backup ? ",backup=1" : ",backup=0"}"
  ]

  gpu_commands = var.gpu_passthrough ? [
    "grep -q 'lxc.cgroup2.devices.allow: c 235:0' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 235:0 rwm' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.cgroup2.devices.allow: c 226:0' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 226:0 rwm' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.cgroup2.devices.allow: c 226:128' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 226:128 rwm' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.mount.entry: /dev/kfd' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.mount.entry: /dev/dri' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
  ] : []

  gpu_render_idmap_commands = var.gpu_render_gid != null ? [
    # Ensure Proxmox host allows passthrough of the render gid via subgid
    "grep -qF 'root:${var.gpu_render_gid}:1' /etc/subgid || echo 'root:${var.gpu_render_gid}:1' | sudo tee -a /etc/subgid",
    "grep -q 'lxc.idmap: u 0 100000 65536' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.idmap: u 0 100000 65536' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.idmap: g 0 100000 ${var.gpu_render_gid}' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.idmap: g 0 100000 ${var.gpu_render_gid}' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.idmap: g ${var.gpu_render_gid} ${var.gpu_render_gid} 1' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.idmap: g ${var.gpu_render_gid} ${var.gpu_render_gid} 1' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
    "grep -q 'lxc.idmap: g ${var.gpu_render_gid + 1} ${100000 + var.gpu_render_gid + 1} ${65536 - var.gpu_render_gid - 1}' /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf || echo 'lxc.idmap: g ${var.gpu_render_gid + 1} ${100000 + var.gpu_render_gid + 1} ${65536 - var.gpu_render_gid - 1}' | sudo tee -a /etc/pve/lxc/${proxmox_virtual_environment_container.this.vm_id}.conf",
  ] : []

  idmap_commands = var.nas_idmap != null ? [
    # Ensure Proxmox host allows passthrough of these ids via subuid/subgid
    "grep -qF 'root:${coalesce(var.nas_idmap.host_uid, var.nas_idmap.uid)}:1' /etc/subuid || echo 'root:${coalesce(var.nas_idmap.host_uid, var.nas_idmap.uid)}:1' | sudo tee -a /etc/subuid",
    "grep -qF 'root:${coalesce(var.nas_idmap.host_gid, var.nas_idmap.gid)}:1' /etc/subgid || echo 'root:${coalesce(var.nas_idmap.host_gid, var.nas_idmap.gid)}:1' | sudo tee -a /etc/subgid",
  ] : []
}

resource "null_resource" "mounts" {
  count      = local.has_provisioner ? 1 : 0
  depends_on = [proxmox_virtual_environment_container.this]

  triggers = {
    memory               = proxmox_virtual_environment_container.this.memory[0].dedicated
    cores                = proxmox_virtual_environment_container.this.cpu[0].cores
    mac_address          = proxmox_virtual_environment_container.this.network_interface[0].mac_address
    mounts               = join(",", [for i, m in var.mounts : "${coalesce(m.volume, m.host)}:${m.mp}${m.ro ? ":ro" : ""}${m.backup ? ":backup" : ""}"])
    mount_mp_indices     = join(" ", [for i, m in var.mounts : tostring(i)])
    gpu                  = tostring(var.gpu_passthrough)
    gpu_render_gid       = var.gpu_render_gid != null ? tostring(var.gpu_render_gid) : ""
    idmap                = var.nas_idmap != null ? "${var.nas_idmap.uid}:${var.nas_idmap.gid}" : ""
    vm_id                = tostring(var.vm_id)
    proxmox_host_ip      = var.proxmox_host_ip
    proxmox_ssh_username = var.proxmox_ssh_username
    ssh_private_key_path = var.terraform_ssh_private_key
  }

  provisioner "remote-exec" {
    when = destroy
    connection {
      type        = "ssh"
      host        = self.triggers.proxmox_host_ip
      user        = self.triggers.proxmox_ssh_username
      private_key = file(pathexpand(self.triggers.ssh_private_key_path))
      agent       = false
    }
    inline = [
      # Strip all mount mp entries from the LXC conf before pct destroy reads it.
      # This prevents Proxmox from calling vdisk_free on any referenced storage volumes.
      # Bind mounts have no storage to free so stripping them is harmless.
      "if [ -n '${lookup(self.triggers, "mount_mp_indices", "")}' ]; then sudo /usr/sbin/pct stop ${self.triggers.vm_id} 2>/dev/null || true && until sudo /usr/sbin/pct status ${self.triggers.vm_id} | grep -q 'status: stopped'; do sleep 2; done && for IDX in ${lookup(self.triggers, "mount_mp_indices", "")}; do sudo sed -i \"/^mp$${IDX}:/d\" /etc/pve/lxc/${self.triggers.vm_id}.conf; done; fi",
    ]
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = var.proxmox_host_ip
      user        = var.proxmox_ssh_username
      private_key = file(pathexpand(var.terraform_ssh_private_key))
      agent       = false
    }
    inline = concat(
      [
        # Wait for Proxmox to finish initial container startup before we touch it
        "sleep 10",
        "sudo /usr/sbin/pct stop ${proxmox_virtual_environment_container.this.vm_id}",
        "until sudo /usr/sbin/pct status ${proxmox_virtual_environment_container.this.vm_id} | grep -q 'status: stopped'; do sleep 2; done",
      ],
      # All conf modifications happen while the container is stopped so pmxcfs
      # does not overwrite our appended lines during a concurrent pct operation
      local.mount_commands,
      local.gpu_commands,
      local.gpu_render_idmap_commands,
      local.idmap_commands,
      [
        "sudo /usr/sbin/pct start ${proxmox_virtual_environment_container.this.vm_id}",
        "until sudo /usr/sbin/pct status ${proxmox_virtual_environment_container.this.vm_id} | grep -q 'status: running'; do sleep 2; done",
      ]
    )
  }
}
