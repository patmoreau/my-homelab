# Verification failures on the local PBS datastore (2026-09-28)

## What happened

The first-ever run of `nas-backups-verify` failed:

```
2026-09-28T00:00:00: Starting datastore verify job 'nas-backups:nas-backups-verify'
2026-09-28T00:18:20: TASK ERROR: verification failed - please check the log for details
```

13 distinct snapshots failed, across 6 hosts:

| host | failed snapshots |
| --- | --- |
| lxc-holefeeder | 4 |
| lxc-homeassistant | 3 |
| lxc-immich | 3 |
| lxc-essere | 2 |
| lxc-monitoring | 1 |
| lxc-vault | 1 |

404 checks passed in the same run.

**The failure indicator was new; the damage was not.** The verify job was created on
2026-09-27. Before that nothing ever re-read the stored chunks, so a damaged snapshot showed
green indefinitely. Verification did not cause this — it is the first thing that could see it.

## What the error actually says

```
verify nas-backups:host/lxc-essere/2026-09-18T02:03:53Z/data.pxar.didx failed:
  wrong size (111310753 != 128220680)
verify nas-backups:host/lxc-holefeeder/2026-09-12T02:20:34Z/data.pxar.didx failed:
  wrong size (1516625018 != 155222414)
```

This is the **index** file, not the chunks. PBS recomputes the total size from the entries in
the `.didx` and compares it against the size recorded in the snapshot manifest. A mismatch
means the index no longer describes what the manifest says it should — the chunk data itself
never got as far as being checked.

Note the two directions: one index computes ~17 MB short, another computes 1.5 GB against an
expected 155 MB. Not drift in one direction, which is what makes random bit rot an awkward
explanation.

## Ruled out

**The HBS two-way sync writing stale files back.** This was the leading theory — the Google
Drive job was a *two-way* sync of `backups/datastore` with hidden files excluded, so it
covered exactly the visible manifests and index files while never touching `.chunks`. A
write-back of an older index over a newer one would produce precisely this error.

It is wrong. Every failing index has an mtime matching its own snapshot to within seconds:

```
snapshot 2026-09-18T02:03:53Z → data.pxar.didx mtime 2026-09-18 02:03:58
snapshot 2026-09-12T02:20:34Z → data.pxar.didx mtime 2026-09-12 02:20:41
snapshot 2026-08-02T02:27:55Z → data.pxar.didx mtime 2026-08-02 02:28:04
```

The sync ran at 05:00 daily. None of these files has been rewritten since it was created.

## What is intact

- **Every post-encryption snapshot passed.** No failure is dated 2026-09-27 or later.
- **The offsite copy passed clean**: `r2-offsite-verify` finished `TASK OK`, 7/7 groups, 0
  errors — and it only holds encrypted snapshots, so the damaged ones were never synced.
- Current backups therefore exist intact in two places.

Failures span 2026-04-26 to 2026-09-26, so the damage accumulated over roughly five months
without anything noticing.

## Leading hypothesis

**The datastore lives on NFS, which Proxmox advises against for exactly this class of
problem** — locking and write-consistency semantics that a local filesystem provides and a
network filesystem does not guarantee. This array has independently demonstrated the failure
mode that would expose it: sustained write stalls, and NFS commits blocking long enough to
wedge a client for hours (see `nas-smr-write-performance.md`).

An index written during a stalled or partially-committed write would land wrong and stay
wrong, with an mtime from when it was written — which matches the evidence better than bit
rot does.

This is a hypothesis, not a conclusion. It has not been proven.

## The discriminator

Whether the **next** verify pass finds failures among post-encryption snapshots.

- Only the same 13 old snapshots fail → historical damage, already stopped, nothing to fix
  beyond removing them.
- New failures appear in snapshots created after 2026-09-27 → the datastore's location is the
  active problem, and it needs to move off NFS.

## Remediation

1. Delete the damaged snapshots (done by hand — they are all older plaintext ones that the
   prune policy would age out within a fortnight anyway).
2. Run garbage collection on `nas-backups` afterwards, or the chunks are not reclaimed.
3. Re-run `nas-backups-verify` and confirm it comes back clean, so that the next failure is
   unambiguously new rather than a repeat of these.

## If it recurs

Moving the datastore off NFS is the real fix, and it is not free: lxc-pbs has no volume of its
own today (it is absent from `storage_volumes` in `terraform/persistent-storage`), and its
rootfs is 7.8 GB. A local datastore would need a dedicated LVM volume sized for the retention
policy — currently ~27 GB of chunks, so 100 GB would be comfortable.

The cheaper interim position is the one that already exists: R2 holds an independently
verified copy, and its verify job runs weekly. If the local datastore proves untrustworthy,
the offsite copy is the authority rather than the backup of last resort.

## Verify state on the offsite copy is inherited, and was misleading

A snapshot's verification result lives in its manifest, and a sync copies the manifest — so
snapshots in `r2-offsite` inherit whatever `nas-backups-verify` concluded about the local copy.
Measured on 2026-09-28: of 8 stamped snapshots offsite, 7 carried a UPID from
`nas-backups-verify` and only 1 from `r2-offsite-verify`, later syncs having overwritten the
rest.

Two consequences:

- **The verify column for `r2-offsite` is not evidence the offsite copy was checked.** It can
  read "ok" purely because the local copy passed. The authoritative signal is the
  `r2-offsite-verify` task result.
- **With `--ignore-verified true` the offsite job skipped that inherited work**, so chunks that
  had never been read out of R2 could go unverified for up to `outdated-after` days while the
  UI showed green. For the copy that exists to survive losing the datastore it inherits its
  state from — in the same week that datastore produced 13 damaged snapshots — that is exactly
  backwards.

`r2-offsite-verify` therefore runs with `--ignore-verified false`: every run re-reads
everything from the bucket. Egress is free on R2 and the reads sit well inside the free tier.
The local job keeps `--ignore-verified true`, having no inherited state to be fooled by and no
reason to re-read the whole store weekly on SMR disks.

Snapshots showing no verify state at all are simply newer than the last verify pass — last
night's backups sync at 04:00, after the 00:00 verify window — and are picked up on the next
run.
