# Importing Photos with immich-go

`immich-go` is a CLI tool installed on `lxc-immich` at `/usr/local/bin/immich-go`.
It supports importing Google Takeout archives and other sources directly into Immich.

## Prerequisites

- Immich is running on `lxc-immich` (http://localhost:2283 from inside the container)
- An Immich API key (Account Settings → API Keys → New API Key)
- NAS photos share is mounted at `/photos` inside the container

## SSH into the container

```bash
ssh -i ~/.ssh/terraform_homelab root@192.168.8.46
```

## Get an Immich API Key

1. Open the Immich web UI: **http://192.168.8.46:2283** (or via Traefik reverse proxy)
2. Click your avatar (top-right) → **Account Settings**
3. Scroll to **API Keys** → click **New API Key**
4. Give it a name (e.g. `immich-go`)
5. Set the following **permissions** (or select **All** for simplicity):

   | Permission       | Why it's needed                             |
   | ---------------- | ------------------------------------------- |
   | `asset.read`     | Check existing assets to avoid duplicates   |
   | `asset.create`   | Upload new photos and videos                |
   | `asset.update`   | Update asset metadata (dates, descriptions) |
   | `album.read`     | List existing albums                        |
   | `album.create`   | Create albums from Takeout album structure  |
   | `album.addAsset` | Add uploaded assets to albums               |

6. Click **Create** and copy the key — it is only shown once

Export it in the container shell so you don't have to repeat it:

```bash
export IMMICH_API_KEY="<paste-your-key-here>"
```

Then use `$IMMICH_API_KEY` in all commands below instead of `--api-key <your-api-key>`.

## Google Takeout Import

### 1. Download your Takeout archives

In Google Takeout, select **Google Photos** only and export as ZIP.
Download the resulting files (e.g. `takeout-*.zip` or `takeout-*.tgz`) to `/photos/takeout/` on the NAS.

### 2. Identify the archive format

```bash
file /photos/takeout/takeout-*.zip
```

- **ZIP files** (magic bytes `50 4b`) → immich-go handles these natively, no extraction needed.
- **Gzip/tar files** (magic bytes `1f 8b`, usually `.tgz`) → must be extracted first (see below).

### 3a. Import ZIP archives directly (recommended path)

immich-go can read Takeout ZIPs without extracting them:

```bash
immich-go upload google-photos \
  --server http://localhost:2283 \
  --api-key <your-api-key> \
  /photos/takeout/
```

### 3b. Import gzip tarballs (.tgz)

If your archives are real gzip tarballs, extract them first.

**Check available disk space before extracting:**

```bash
df -h /photos
```

Each `.tgz` expands to roughly the same size uncompressed — plan accordingly.

**Extract all archives:**

```bash
cd /photos/takeout
for f in *.tgz; do
  echo "Extracting $f ..."
  tar -xzf "$f"
done
```

The extracted directory tree will be at `/photos/takeout/Takeout/Google Photos/`.

**Run the import:**

```bash
immich-go upload google-photos \
  --server http://localhost:2283 \
  --api-key <your-api-key> \
  "/photos/takeout/Takeout/Google Photos"
```

### Useful import flags

| Flag                | Description                                                  |
| ------------------- | ------------------------------------------------------------ |
| `--dry-run`         | Preview what would be uploaded without making changes        |
| `--create-albums`   | Create albums matching Takeout album structure (default: on) |
| `--no-progress`     | Suppress progress bar for cleaner logs                       |
| `--log-level debug` | Verbose logging for troubleshooting                          |
| `--skip-duplicates` | Skip files already present in Immich                         |

### Dry run first

Always do a dry run to verify what will be imported:

```bash
immich-go upload google-photos \
  --server http://localhost:2283 \
  --api-key <your-api-key> \
  --dry-run \
  /photos/takeout/
```

## Importing from a local directory

To import photos from any directory (not Google Takeout):

```bash
immich-go upload \
  --server http://localhost:2283 \
  --api-key <your-api-key> \
  /photos/my-folder/
```

## Version

The installed version is pinned in `ansible/host_vars/lxc-immich.yaml`:

```yaml
immich_go_version: "v0.31.0"
```

Check the installed version:

```bash
immich-go version
```

To upgrade, update `immich_go_version` and re-run the Immich playbook:

```bash
ansible-playbook -i inventory/hosts.yaml site.yaml --limit lxc-immich
```

## References

- [immich-go GitHub](https://github.com/simulot/immich-go)
- [Immich API key docs](https://immich.app/docs/features/command-line-interface#obtain-the-api-key)
