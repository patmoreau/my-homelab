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
      DISK=${each.value.disk_name}
      SIZE=${each.value.size}
      DISK_NAME="vm-$VMID-$DISK"
      MNT="/tmp/terraform_mnt_$VMID"

      PVESM="/usr/sbin/pvesm"
      MKFS="/usr/sbin/mkfs.ext4"

      HOST_PATH="/mnt/containers/${each.key}"

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

      # Ensure the volume is mounted on the Proxmox host at a stable path.
      # Containers mount it as a host bind mount so that pct destroy --purge
      # never sees it as a storage volume reference and never calls vdisk_free.
      DISK_PATH=$(sudo $PVESM path $STORAGE:$DISK_NAME)

      # Apply size increases to volumes that already exist, so bumping `size` in
      # storage_volumes is enough to grow them. ext4 grows online, so the mount
      # can stay up. Shrinking is never attempted: it would need an unmount and
      # risks data loss, so a smaller `size` is ignored here and must be done by
      # hand.
      CURRENT_BYTES=$(sudo /usr/sbin/lvs --noheadings --units b --nosuffix -o lv_size $DISK_PATH | tr -d ' ')
      TARGET_BYTES=$(numfmt --from=iec $SIZE)
      if [ "$TARGET_BYTES" -gt "$CURRENT_BYTES" ]; then
          echo "Growing $DISK_NAME to $SIZE..."
          sudo /usr/sbin/lvextend -L $SIZE $DISK_PATH
          sudo /usr/sbin/resize2fs $DISK_PATH
      fi

      sudo mkdir -p $HOST_PATH
      if ! grep -qF "$DISK_PATH $HOST_PATH" /etc/fstab; then
          echo "$DISK_PATH $HOST_PATH ext4 defaults,nofail,x-systemd.requires=pve-lxc-data-volumes.service 0 2" | sudo tee -a /etc/fstab
      fi
      # Ensure the activation service exists and is enabled.
      # It activates all pve LVs (thin volumes not auto-activated otherwise).
      SERVICE=/etc/systemd/system/pve-lxc-data-volumes.service
      if [ ! -f $SERVICE ]; then
          sudo tee $SERVICE << 'SVCEOF'
[Unit]
Description=Activate Proxmox LXC persistent data volumes
DefaultDependencies=no
Before=local-fs.target
After=lvm2-activation.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/vgchange -ay pve

[Install]
WantedBy=local-fs.target
SVCEOF
          sudo systemctl daemon-reload
          sudo systemctl enable pve-lxc-data-volumes.service
      fi
      if ! mountpoint -q $HOST_PATH; then
          sudo lvchange -ay pve/$DISK_NAME
          sudo mount $HOST_PATH
      fi
      EOT
    ]
  }
}
