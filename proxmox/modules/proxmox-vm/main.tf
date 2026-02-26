terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.46.1"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name

  stop_on_destroy = var.stop_on_destroy

  agent {
    enabled = true
  }

  cpu {
    cores = var.vcpu
  }

  memory {
    dedicated = var.memory
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vmbr0_ipv4
        gateway = var.vmbr0_gw
      }
    }

    ip_config {
      ipv4 {
        address = var.vmbr1_ipv4
        gateway = var.vmbr1_gw
      }
    }

    vendor_data_file_id = proxmox_virtual_environment_file.cloud_init_vendor_data.id

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key)]
    }
  }

  disk {
    datastore_id = var.disk_datastore_id
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size
  }

  network_device {
    bridge = "vmbr0"
  }

  network_device {
    bridge = "vmbr1"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_vendor_data" {
  content_type = "snippets"
  datastore_id = var.proxmox_snippets_datastore
  node_name    = var.node_name

  source_raw {
    file_name = coalesce(var.vendor_data_file_name, "${var.name}-vendor-data.yaml")
    data      = <<-EOF
      #cloud-config
      packages:
        - qemu-guest-agent
        - nfs-common
        - ca-certificates
        - curl
      mounts:
        - [192.168.50.1:/Books, /mnt/nas-books, nfs, "defaults,nfsvers=3,soft,bg,_netdev,async,timeo=150,retrans=3,rw", "0", "0"]
        - [192.168.50.1:/Multimedia, /mnt/nas-media, nfs, "defaults,nfsvers=3,soft,bg,_netdev,async,timeo=150,retrans=3,rw", "0", "0"]
        - [192.168.50.1:/docker-data, /mnt/nas-docker-data, nfs, "defaults,nfsvers=3,soft,bg,_netdev,async,timeo=150,retrans=3,rw", "0", "0"]
      runcmd:
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - mkdir -p /mnt/nas-books /mnt/nas-media /mnt/nas-docker-data
        - mount -a
        - install -m 0755 -d /etc/apt/keyrings
        - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        - chmod a+r /etc/apt/keyrings/docker.asc
        - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
        - apt-get update
        - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        - systemctl enable docker
        - systemctl start docker
        - usermod -aG docker ${var.vm_user}
    EOF
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = coalesce(var.image_file_name, "${var.name}-noble-server-cloudimg-amd64.qcow2")
}
