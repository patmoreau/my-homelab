# Proxmox Infrastructure

## Initial Setup (one-time)

### Install Proxmox VE

https://pve.proxmox.com/wiki/Installation

### Create the Ubuntu 24.04 Template (VM 9000)

Run in the Proxmox shell:

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -P /var/lib/vz/template/iso/

sudo qm create 9000 --name "ubuntu-2404-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
sudo qm importdisk 9000 /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img local-lvm
sudo qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
sudo qm set 9000 --ide2 local-lvm:cloudinit
sudo qm set 9000 --boot c --bootdisk scsi0 --serial0 socket --vga serial0
sudo qm set 9000 --citype nocloud
sudo qm template 9000
```

### Proxmox API Token

In the Proxmox UI:

1. **Datacenter → Permissions → Users** — create `terraform-user@pve`
2. **Datacenter → Permissions → API Tokens** — generate a token, uncheck "Privilege Separation"
3. **Datacenter → Permissions** — assign `Administrator` role on `/` to the token

### PAM User for SSH (required for cloud-init snippets upload)

In the Proxmox UI: **Datacenter → Permissions → Users → Add** (Realm: `PAM`, e.g. `terraform-admin`), then assign `Administrator` at `/`.

Authorize your SSH key on the Proxmox host:

```bash
mkdir -p /home/terraform-admin/.ssh
echo "YOUR_PUBLIC_KEY" >> /home/terraform-admin/.ssh/authorized_keys
chmod 700 /home/terraform-admin/.ssh
chmod 600 /home/terraform-admin/.ssh/authorized_keys
chown -R terraform-admin:terraform-admin /home/terraform-admin/.ssh
```

Grant passwordless sudo for snippets upload:

```bash
echo "terraform-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/terraform
```

### Enable Snippets Storage

**Datacenter → Storage → local → Edit** — check "Snippets"

## Deploying VMs

```bash
cd proxmox/<vm-folder>
cp terraform.tfvars.example terraform.tfvars
# fill in values
terraform init
terraform plan
terraform apply
```

### terraform.tfvars keys

```hcl
proxmox_token_id     = "terraform-user@pve!token-id"
proxmox_token_secret = "00000000-0000-0000-0000-000000000000"
proxmox_ssh_username = "terraform-admin"
# proxmox_snippets_datastore = "local"  # default
```

> SSH keys via 1Password / ssh-agent are picked up automatically (`agent = true` is the default in the provider).

## Reminders

- **Multiple NICs**: one `network_device` block + one `ip_config` block per adapter, in order (`net0`, `net1`, …). Secondary interfaces don't need a gateway.
- **QEMU guest agent**: enabled in the VM resource (`agent { enabled = true }`) and installed via a cloud-init vendor data snippet (`vendor_data_file_id`, not `user_data_file_id`).
- **NFS mounts**: use the `mounts` directive in the vendor data snippet; include `nfs-common` in `packages`.

## Configure GPU sharing with VM

run the script on the Proxmox:

```bash
scp proxmox/scripts/check_passthrough.sh pmoreau@192.168.8.10:/tmp/ && \
  ssh -t pmoreau@192.168.8.10 'sudo bash /tmp/check_passthrough.sh'
```

Here are the 3 files you need to verify on the Proxmox Host:

1. The Bootloader (/etc/default/grub)
   Ensure this line exists:
   GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
   Then run:

   ```bash
   sudo update-grub
   ```

2. The Modules (/etc/modules)
   Add these to the bottom of the file:

   ```text
   vfio
   vfio_iommu_type1
   vfio_pci
   ```

3. Check the address

   ```bash
    lspci | grep VGA
   ```

4. The Binding (/etc/modprobe.d/vfio.conf)
   You need to tell Proxmox to "reserve" the GPU for the VM. Use the IDs found by the script (likely 1002:1900 for your 780M):

   ```bash
   echo "options vfio-pci ids=1002:1900 disable_vga=1" | sudo tee /etc/modprobe.d/vfio.conf
   sudo update-initramfs -u
   ```
