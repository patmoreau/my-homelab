resource "null_resource" "persistent_volumes" {
  for_each = var.storage_volumes

  triggers = {
    vmid = each.value.vmid
    size = each.value.size
  }

  connection {
    type        = "ssh"
    host        = var.proxmox_host_ip
    user        = var.proxmox_ssh_username
    private_key = file(pathexpand(var.terraform_ssh_private_key))
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      VMID=${each.value.vmid}
      STORAGE=${each.value.storage_name}
      SIZE=${each.value.size}
      DISK_NAME="vm-$VMID-disk-10"
      MNT="/tmp/terraform_mnt_$VMID"

      PVESM="/usr/sbin/pvesm"
      MKFS="/usr/sbin/mkfs.ext4"

      # Verification of idempotence: if the disk already exists, do nothing
      if sudo $PVESM list $STORAGE | grep -q $DISK_NAME; then
          echo "Volume $DISK_NAME already exists. Skipping creation."
      else
          echo "Allocating and formatting $DISK_NAME..."
          sudo $PVESM alloc $STORAGE $VMID $DISK_NAME $SIZE
          
          DISK_PATH=$(sudo $PVESM path $STORAGE:$DISK_NAME)
          sudo $MKFS $DISK_PATH
          
          sudo mkdir -p $MNT
          sudo mount $DISK_PATH $MNT
          sudo chown -R 100000:100000 $MNT
          sudo umount $MNT
          sudo rmdir $MNT
          echo "Successfully initialized $DISK_NAME"
      fi
      EOT
    ]
  }
}
