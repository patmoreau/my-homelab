#!/usr/bin/env bash
# Manage ansible vault: encrypt/decrypt group_vars/all/vault.yaml <-> group_vars/all/vault.yaml.vault
set -euo pipefail

VAULT_PLAIN="group_vars/all/vault.yaml"
VAULT_ENC="group_vars/all/vault.yaml.vault"
VAULT_PASS_FILE=".vault_pass"

cd "$(dirname "$0")"

require_pass_file() {
  if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "Error: $VAULT_PASS_FILE not found."
    echo "Create it with your vault password (it is gitignored):"
    echo "  echo 'your-password' > ansible/$VAULT_PASS_FILE"
    exit 1
  fi
}

case "${1:-}" in
  encrypt)
    require_pass_file
    if [[ ! -f "$VAULT_PLAIN" ]]; then
      echo "Error: $VAULT_PLAIN not found. Nothing to encrypt."
      exit 1
    fi
    ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" \
      --encrypt-vault-id default \
      --output "$VAULT_ENC" "$VAULT_PLAIN"
    echo "Encrypted: $VAULT_PLAIN -> $VAULT_ENC"
    ;;

  decrypt)
    require_pass_file
    if [[ ! -f "$VAULT_ENC" ]]; then
      echo "Error: $VAULT_ENC not found. Nothing to decrypt."
      exit 1
    fi
    ansible-vault decrypt --vault-password-file "$VAULT_PASS_FILE" \
      --output "$VAULT_PLAIN" "$VAULT_ENC"
    echo "Decrypted: $VAULT_ENC -> $VAULT_PLAIN"
    ;;

  edit)
    require_pass_file
    # Decrypt to plain, open editor, re-encrypt
    if [[ -f "$VAULT_ENC" ]] && [[ ! -f "$VAULT_PLAIN" ]]; then
      ansible-vault decrypt --vault-password-file "$VAULT_PASS_FILE" \
        --output "$VAULT_PLAIN" "$VAULT_ENC"
    fi
    "${EDITOR:-vi}" "$VAULT_PLAIN"
    ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" \
      --encrypt-vault-id default \
      --output "$VAULT_ENC" "$VAULT_PLAIN"
    echo "Saved and re-encrypted to $VAULT_ENC"
    ;;

  status)
    echo "Plain:     $([ -f "$VAULT_PLAIN" ] && echo "exists" || echo "missing")"
    echo "Encrypted: $([ -f "$VAULT_ENC" ] && echo "exists" || echo "missing")"
    echo "Pass file: $([ -f "$VAULT_PASS_FILE" ] && echo "exists (gitignored)" || echo "missing")"
    ;;

  *)
    echo "Usage: $0 {encrypt|decrypt|edit|status}"
    echo ""
    echo "  encrypt  Encrypt group_vars/vault.yaml -> group_vars/vault.yaml.vault (commit this)"
    echo "  decrypt  Decrypt group_vars/vault.yaml.vault -> group_vars/vault.yaml (gitignored)"
    echo "  edit     Decrypt, open in \$EDITOR, re-encrypt"
    echo "  status   Show which files exist"
    exit 1
    ;;
esac
