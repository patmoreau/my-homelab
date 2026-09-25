# NAS write performance: two array members are SMR

## Hardware

`MorindinVault` (192.168.8.109 on the LAN, **192.168.50.1** on the storage VLAN) is a
4-bay QNAP. All four disks are in one RAID5 array, `md1`:

| Port | Device     | Model                  | Recording |
| ---- | ---------- | ---------------------- | --------- |
| 1    | `/dev/sda` | `WDC WD40EFAX-68JH4N1` | **SMR**   |
| 2    | `/dev/sdb` | `WDC WD40EFAX-68JH4N1` | **SMR**   |
| 3    | `/dev/sdc` | `WDC WD40EFRX-68WT0N0` | CMR       |
| 4    | `/dev/sdd` | `WDC WD40EFRX-68WT0N0` | CMR       |

`WD40EFAX` is the shingled (SMR) WD Red from the batch WD shipped without disclosing the
change; `WD40EFRX` is the older conventional (CMR) Red. The array is **healthy** —
`[4/4] [UUUU]`, no rebuild — this is not a fault, it is what the hardware does.

## What it looks like from a client

Measured from lxc-media over NFS (`dd`, 2026-09-25):

| Operation                     | Throughput   |
| ----------------------------- | ------------ |
| read, 512 MB, `iflag=direct`  | **251 MB/s** |
| write, 512 MB, `oflag=direct` | **5.0 MB/s** |
| write, 128 MB, `oflag=direct` | 11–12 MB/s   |
| write, 512 MB, buffered+fsync | 56 MB/s      |
| (same host) local NVMe write  | 4.4 GB/s     |

Reads run at full line rate, so a slow copy is never the network, the switch or the MTU —
checking those is wasted time. Writes collapse because an SMR drive has a small CMR cache
zone: short bursts land there fast, and once it fills the drive must read-modify-write
whole shingled zones. RAID5 compounds it, since a partial-stripe write is itself a
read-modify-write across members, and every parity write runs at the speed of the slowest
member. Numbers vary between runs with the cache-zone flush cycle.

## How it shows up as a bug

A zone rewrite can block a single write for many seconds, which surfaces as an NFS COMMIT
that never returns. On 2026-09-25 that wedged Transmission: its disk thread sat in
`nfs_wb_folio -> __nfs_commit_inode` in `D` state, the main loop waited on the same mutex,
and the daemon kept its listening socket while never calling `accept()` — 45 connections
queued on `0.0.0.0:9091` with `systemctl` reporting `active`, `podman ps` reporting
`Up 37 hours`, and an empty log. It also caught a completion move mid-flight and left a
truncated episode in the library. See the transmission notes in `ansible/README.md`.

So: **when something on the NAS hangs rather than merely runs slowly, suspect this first.**

## Who writes to the NAS

Cumulative NFS counters, 18 days (`/proc/self/mountstats`, `bytes:` line — fields are
`read write directread directwrite serverread serverwrite`, which is easy to misread):

| Mount              | Written | Read     | Notes                                  |
| ------------------ | ------- | -------- | -------------------------------------- |
| `/media`           | 707 GB  | 1 167 GB | ~39 GB/day, the dominant writer        |
| `/mnt/nas-backups` | 12 GB   | 0 GB     | PBS datastore, modest                  |
| `/photos`          | 3 GB    | 2 952 GB | Immich — read-heavy, which SMR is fine with |
| `/media/books`     | 1 GB    | 29 GB    |                                        |

Host-level counters do **not** capture container writes through bind mounts; read them
inside each container.

## What has been done about it

Transmission's in-progress downloads moved to a local NVMe volume (`media-downloads`,
mounted `/downloads`). This does not reduce the bytes the NAS eventually receives — a
finished file is still written once — but it changes their shape from random piece writes
to one sequential write per completed file, which is the pattern SMR handles acceptably.

## The actual fix

Replace the two `WD40EFAX` drives with CMR: WD Red Plus (`WD40EFPX` / `WD40EFZX`) or
Seagate IronWolf. One at a time, letting RAID5 rebuild in between. A rebuild writes the
full 3.6 TB to the replacement and will be slow while any SMR member remains, so the array
gets faster with each swap. Until then it stays healthy — just slow at sustained writes.

## Getting a shell on the NAS

The key at `/opt/docker/service-watcher/.ssh/id_ed25519_qnap_monitor` on lxc-media is
restricted to a forced command that reports md operation state only (`IDLE` when no
check/resync/recovery is running) — it cannot run arbitrary commands. For a real shell use
the admin account with password auth, and disable pubkey auth or the agent offers too many
keys and the NAS drops the connection with `Too many authentication failures`:

```bash
ssh -o IdentitiesOnly=yes -o PubkeyAuthentication=no <admin>@192.168.8.109
```

`smartctl` is not shipped. QNAP's own tools are in `/usr/local/sbin`: `qcli_storage -d`
lists disks with models (that is where the SMR models above came from), `get_hd_smartinfo`
reads SMART, and `cat /proc/mdstat` shows array health.
