data "local_file" "ssh_public_key" {
  filename = pathexpand("~/.ssh/id_ed25519_homelab.pub")
}

module "docker_vm" {
  source = "../modules/proxmox-vm"

  name      = var.name
  node_name = var.node_name

  vmbr0_ipv4 = var.vmbr0_ipv4
  vmbr0_gw   = var.vmbr0_gw
  vmbr1_ipv4 = var.vmbr1_ipv4
  vmbr1_gw   = var.vmbr1_gw

  memory    = var.memory
  vcpu      = var.vcpu
  disk_size = var.disk_size
  vm_user   = var.vm_user

  ssh_public_key = data.local_file.ssh_public_key.content

  machine_type = var.machine_type
  hostpci = var.gpu_mapping != null ? {
    mapping = var.gpu_mapping
    pcie    = true
    rombar  = true
    xvga    = false
  } : null

  # Override filenames to match the historically created ones so Terraform doesn't replace them
  vendor_data_file_name = "docker-vm-vendor-data.yaml"
  image_file_name       = "noble-server-cloudimg-amd64.qcow2"
}

# --- State Migration Blocks ---
# These blocks ensure Terraform moves the existing single VM into the module's state

moved {
  from = proxmox_virtual_environment_vm.docker_vm
  to   = module.docker_vm.proxmox_virtual_environment_vm.this
}

moved {
  from = proxmox_virtual_environment_file.cloud_init_vendor_data
  to   = module.docker_vm.proxmox_virtual_environment_file.cloud_init_vendor_data
}

moved {
  from = proxmox_virtual_environment_download_file.ubuntu_cloud_image
  to   = module.docker_vm.proxmox_virtual_environment_download_file.ubuntu_cloud_image
}
