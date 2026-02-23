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

1. Go to **Datacenter -> Permissions -> Users** and create a user (e.g., `terraform@pve`).
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
