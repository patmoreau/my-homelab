#!/usr/bin/env bash
#
# backup-state.sh — encrypt Terraform state with age and push it to the NAS.
#
# State files contain secrets (Proxmox token, SSH material), so they are
# encrypted locally with `age` BEFORE leaving this machine. The NAS — and every
# downstream backup of the NAS — only ever sees ciphertext.
#
# Transport goes through the Proxmox host (which already NFS-mounts the NAS at
# /mnt/pve/nas-backups) using the existing terraform_homelab key, so it needs no
# hardware-key touch and the NAS keeps its sk-only SSH lockdown.
#
# One-time setup:
#   brew install age
#   age-keygen -o ~/.config/tf-state-backup/key.txt   # store key.txt in your password manager
#   # copy the printed "Public key: age1..." into RECIPIENT below
#   # (no root needed — terraform-admin creates the NAS dir itself on first run)
#
# Restore:
#   age -d -i ~/.config/tf-state-backup/key.txt backup-...tfstate.age > terraform.tfstate
#
set -euo pipefail

# --- config -----------------------------------------------------------------
RECIPIENT="age1xncssrkjgljzgf3ts6jt0cdxuxz0jme7v0m0ksnntclcnqafnpps03y7nx"   # age public key — safe to commit
PVE="terraform-admin@192.168.8.10"             # Proxmox node (NFS-mounts the NAS)
KEY="$HOME/.ssh/terraform_homelab"
DIR="/mnt/pve/nas-backups/terraform-state"     # on the NAS, via Proxmox mount
KEEP=30                                         # versions to retain per state file
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes)     # pin the key; ignore agent keys

STATES=(
  "terraform.tfstate"
  "persistent-storage/terraform.tfstate"
)
# ----------------------------------------------------------------------------

cd "$(dirname "$0")"

command -v age >/dev/null || { echo "age not found — run: brew install age" >&2; exit 1; }
[[ "$RECIPIENT" == age1REPLACE_* ]] && { echo "Set RECIPIENT to your age public key first." >&2; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)

ssh "${SSH_OPTS[@]}" "$PVE" "mkdir -p '$DIR'"

for f in "${STATES[@]}"; do
  [[ -f "$f" ]] || { echo "skip (missing): $f"; continue; }
  prefix=$(echo "${f%.tfstate}" | tr '/' '-')   # e.g. persistent-storage-terraform
  out="${prefix}-${TS}.tfstate.age"

  echo "backing up $f -> $DIR/$out"
  age -r "$RECIPIENT" "$f" | ssh "${SSH_OPTS[@]}" "$PVE" "cat > '$DIR/$out'"

  # prune old versions, keeping the newest $KEEP for this state file
  ssh "${SSH_OPTS[@]}" "$PVE" \
    "cd '$DIR' && ls -1t ${prefix}-*.tfstate.age 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f"
done

echo "done."
