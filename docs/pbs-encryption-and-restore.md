# PBS client-side encryption, key escrow, and restoring without the homelab

## What is encrypted, and where

`proxmox-backup-client` encrypts each chunk **inside the container**, before anything is sent.
The datastore on the NAS therefore holds ciphertext, and every copy made from it inherits that:
the HBS sync to Google Drive, a stolen NAS, any future second target.

This is why encryption belongs here rather than at the QNAP/HBS layer. HBS encryption would
protect only the cloud copy — the 27 GB on the NAS would stay readable — and it would make
decryption depend on QNAP tooling, which is precisely the thing you have lost in the scenario
where you need the backup.

| Threat | HBS encryption | PBS encryption |
| --- | --- | --- |
| Google account compromise | yes | yes |
| NAS stolen, or disks pulled | no | yes |
| QNAP CVE / ransomware | no | yes |
| Misconfigured NFS export | no | yes |
| Restore with no QNAP in the picture | no | yes |

Do **not** enable both. Double encryption buys nothing and complicates restore.

## The key

- Lives in the vault as `vault_pbs_encryption_key` and is deployed by the
  `proxmox-backup-client` role to `/etc/proxmox-backup/encryption-key.json`, mode `0600`.
- `kdf: none` — no passphrase, because an unattended timer cannot type one. The protection is
  file permissions plus the vault.
- Fingerprint `74:5a:e6:d5:48:17:8e:40:...` identifies which key a snapshot needs. The
  fingerprint is not secret; the file is.

**Losing this file means losing every encrypted backup.** There is no recovery path, by design.

### Escrow rules

1. Keep a copy outside the homelab entirely — an external password manager, and ideally a
   printed copy in a drawer.
2. **Not in Vaultwarden.** Vaultwarden is itself backed up by PBS, so a key stored there is
   unreachable in exactly the disaster it exists for.
3. Not in this repository. The vault is encrypted, but `vault.yaml.vault` lives in the same git
   history as everything else and a single leaked vault password would expose it.

Read the key out of the vault when you need to escrow it:

```bash
cd ansible && ./vault.sh decrypt            # if vault.yaml is not already present
grep vault_pbs_encryption_key group_vars/all/vault.yaml
```

## Restoring when the homelab is gone

The case worth rehearsing: no Proxmox, no QNAP, just the Google Drive copy of the datastore and
a laptop. Nothing here needs Proxmox hardware or QNAP software.

```bash
# 1. Any Debian/Ubuntu box. The client is in Proxmox's public repo.
echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" \
  | sudo tee /etc/apt/sources.list.d/pbs-client.list
sudo wget -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg \
  https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
sudo apt update && sudo apt install proxmox-backup-client

# 2. Pull the datastore copy down from Drive to a local directory, then point at it as a
#    filesystem datastore. .chunks MUST be included — see the HBS note below.
export PBS_REPOSITORY=/path/to/restored/datastore

# 3. Put the escrowed key somewhere readable and list what is there.
proxmox-backup-client snapshot list --keyfile /path/to/encryption-key.json

# 4. Restore one archive.
proxmox-backup-client restore host/lxc-vault/<timestamp> data.pxar /path/to/output \
  --keyfile /path/to/encryption-key.json
```

## The HBS job that syncs the datastore offsite

Two settings on the QNAP side decide whether any of the above works:

- **"Exclure les fichiers et dossiers cachés" must be OFF.** A PBS datastore keeps all data in
  `.chunks`, which is hidden. With that filter on, the offsite copy was 7.3 MB of manifests
  pointing at chunks that were never uploaded — an index of nothing. This was the real state of
  the offsite backup until 2026-09-27.
- **Use a one-way backup job, not a two-way sync.** Two-way propagates local deletion and
  corruption to the cloud copy, and lets cloud-side changes write back into the datastore.

Sync runs at 05:00; GC and prune run at midnight, so they do not overlap. Keep it that way — a
sync taken while GC is rewriting the chunk store copies an inconsistent datastore.

## Verification

`nas-backups-verify` runs weekly, skipping snapshots verified in the last 30 days. It re-reads
chunks and checks them against their digests, which is the only thing that catches bit rot
before a restore does. Encrypted chunks verify normally — the digest covers the ciphertext, so
the server needs no key.

## Transition notes

Snapshots taken before 2026-09-27 are unencrypted and stay readable without the key. They do
not dedup against encrypted chunks, so the first encrypted run per host rewrites that host's
archive in full and the datastore grows until the old snapshots age out under the prune policy
(keep-last 7, keep-daily 14).
