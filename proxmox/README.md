# Proxmox Platform as Code (PaC) Setup

## Phase 0: Install Proxmox VE

Follow the official documentation to install Proxmox VE on your hardware:

https://pve.proxmox.com/wiki/Installation

## Phase 1: Creating the Golden Image (Template)

This template serves as the base for all future VMs. It uses Ubuntu 24.04 with Cloud-Init pre-installed.

### 1. Download the Cloud Image

Run this in the Proxmox Shell to fetch the official Ubuntu Cloud image:

```bash
wget [https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img) -P /var/lib/vz/template/iso/
```

### 2. Initialize the Template VM

Run these commands in the Proxmox Shell to create VM ID 9000 and configure it as a template:

```bash
# Create the VM container
sudo qm create 9000 --name "ubuntu-2404-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Import the disk (Update 'local-lvm' if your storage name is different)
sudo qm importdisk 9000 /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img local-lvm

# Attach the disk and Cloud-Init drive
sudo qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
sudo qm set 9000 --ide2 local-lvm:cloudinit

# Set boot and serial console (Cloud Images use serial by default)
sudo qm set 9000 --boot c --bootdisk scsi0 --serial0 socket --vga serial0
sudo qm set 9000 --citype nocloud

# Finalize: Convert the VM into a Template
sudo qm template 9000
```

## Phase 2: Setting up Terraform

Before we can stand up virtual machines, we need to configure Terraform to communicate with your Proxmox host.

### 1. Create a Proxmox API Token

Terraform needs an API token to interact with your Proxmox server. Create this in the Proxmox Web UI:

1. Go to **Datacenter -> Permissions -> Users** and create a user (e.g., `terraform-user@pve`).
2. Go to **Datacenter -> Permissions -> API Tokens** and generate a token for this user. Make sure to uncheck "Privilege Separation". Keep the `Token ID` and `Secret` somewhere safe.
3. Go to **Datacenter -> Permissions** and assign at least the `PVEVMAdmin` role (or `Administrator` for ease of use) to the user or API Token on the `/` path.

### 2. Initialize the Provider

Create a directory for your terraform code and create a `provider.tf` file. We will use the officially recommended `bpg/proxmox` provider.

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://<your-proxmox-ip-or-hostname>:8006/"
  # Format is: USERNAME@REALM!TOKENID=UUID
  api_token = "terraform@pve!mytoken=12345678-1234-1234-1234-1234567890ab"
  insecure  = true # Set to true if you are using a self-signed certificate
}
```

_Note: In a real environment, you should use variables or environment variables (like `PROXMOX_VE_API_TOKEN`) instead of hardcoding the token here._

### 3. Create a PAM User for SSH Access

The `bpg/proxmox` provider uses the Proxmox API for most operations, but **uploading cloud-init snippet files requires SSH** — the Proxmox API has no endpoint for this. The SSH user must be a **PAM user** (a real Linux system account), not a PVE-realm user.

> **Note:** `root` SSH login is typically (and should be) disabled. Use a dedicated admin PAM user instead.

#### Create the PAM user in Proxmox

In the Proxmox UI, go to **Datacenter → Permissions → Users → Add**:

- Realm: `PAM`
- Username: e.g. `terraform-admin`

Then assign it the `Administrator` role at the `/` path under **Datacenter → Permissions → Add → User Permission**.

#### Authorize your SSH key for that user

On the Proxmox host (via **Proxmox UI → node → Shell**):

```bash
# Create the user's .ssh directory and add your public key
mkdir -p /home/terraform-admin/.ssh
echo "YOUR_PUBLIC_KEY" >> /home/terraform-admin/.ssh/authorized_keys
chmod 700 /home/terraform-admin/.ssh
chmod 600 /home/terraform-admin/.ssh/authorized_keys
chown -R terraform-admin:terraform-admin /home/terraform-admin/.ssh
```

Verify it works from your machine:

```bash
ssh terraform-admin@<proxmox-host>
```

### 4. Enable Snippets and Grant Write Access

Cloud-init vendor data files are uploaded as snippets. You need to:

1. Enable the `snippets` content type on your datastore — in the Proxmox UI: **Datacenter → Storage → local → Edit → check "Snippets" → OK**

2. Grant your PAM user write access to the snippets directory (run in the Proxmox Shell as root):

```bash
chown root:terraform-admin /var/lib/vz/snippets
chmod 775 /var/lib/vz/snippets
```

### 5. Configure terraform.tfvars

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values:

```hcl
proxmox_token_id     = "terraform-user@pve!token-id"
proxmox_token_secret = "00000000-0000-0000-0000-000000000000"
proxmox_ssh_username = "terraform-admin"   # PAM user with SSH access and snippets write permission
# proxmox_snippets_datastore = "local"     # default: local — must have snippets content type enabled
```

> **SSH keys stored in 1Password or another SSH agent:** Set `agent = true` in the provider's `ssh` block (already the default). Your key will be picked up automatically from the agent — no private key file needed on disk.

## Phase 3: Creating VMs

### VM Configuration Notes

#### QEMU Guest Agent

The QEMU guest agent enables Proxmox to communicate with the VM (shutdown, IP reporting, snapshots, etc.). Two things are required:

1. **Enable it in the VM resource** with `agent { enabled = true }` — tells Proxmox to expect the agent
2. **Install it inside the VM** via a cloud-init vendor data snippet

Use `vendor_data_file_id` (not `user_data_file_id`) to inject the package installation. `user_data_file_id` replaces the entire cloud-init user config and would override the `user_account` block, preventing your SSH key from being injected.

```hcl
resource "proxmox_virtual_environment_file" "cloud_init_vendor_data" {
  content_type = "snippets"
  datastore_id = var.proxmox_snippets_datastore
  node_name    = "homelab"

  source_raw {
    file_name = "docker-vm-vendor-data.yaml"
    data      = <<-EOF
      #cloud-config
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "my_vm" {
  # ...
  agent {
    enabled = true
  }

  initialization {
    vendor_data_file_id = proxmox_virtual_environment_file.cloud_init_vendor_data.id

    user_account {
      username = "ubuntu"
      keys     = [trimspace(data.local_file.ssh_public_key.content)]
    }
  }
}
```

#### Multiple Network Adapters

Add one `network_device` block per adapter. They are assigned in order as `net0`, `net1`, etc.:

```hcl
network_device {
  bridge = "vmbr0"  # net0
}

network_device {
  bridge = "vmbr1"  # net1
}
```

### Running Terraform

```bash
cd proxmox/proxmox-docker-vm
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```
