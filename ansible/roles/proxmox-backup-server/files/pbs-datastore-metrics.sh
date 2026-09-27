#!/usr/bin/env bash
# Export PBS datastore size and snapshot counts as node_exporter textfile metrics.
#
# The numbers come out of the nightly garbage-collection task log rather than from `du`.
# That is deliberate: the datastore lives on the NAS, whose array is half SMR, and walking
# ~11k chunk files across 65k directories over NFS costs minutes of metadata round trips for
# a number PBS has already computed while doing its own GC pass. Free is better than accurate
# to the minute — GC runs daily, so these refresh daily, which is the right resolution for a
# growth trend anyway.
#
# Snapshot counts are cheap (a readdir per backup id) and update on every run, so a host that
# silently stops backing up shows up within the hour rather than at the next GC.
set -uo pipefail

datastore_path=${PBS_DATASTORE_PATH:-/mnt/nas-backups/datastore}
datastore_name=${PBS_DATASTORE_NAME:-nas-backups}
out_dir=${PBS_TEXTFILE_DIR:-/var/lib/node_exporter}
out="$out_dir/pbs_datastore.prom"
tmp="$out.$$"

mkdir -p "$out_dir"

ondisk=0; original=0; chunks=0; dedup=0; pending=0; gc_time=0

# Newest *completed* GC task log. Selected by the summary line rather than by filename or by
# the word "garbage_collection": the UPID filename escapes the datastore name
# ("nas\x2dbackups"), and matching the task type also matches PBS's `active` index file, which
# is always the newest and never contains a summary.
#
# No xargs in this pipeline, deliberately. Those filenames contain a literal backslash and
# xargs treats it as an escape, handing `ls` a path spelled "nasx2dbackups" that does not
# exist — which is why the first version reported zeroes for every figure.
gc_log=$(grep -rls "On-Disk usage:" /var/log/proxmox-backup/tasks/ 2>/dev/null |
         while IFS= read -r f; do
           printf '%s\t%s\n' "$(stat -c %Y "$f" 2>/dev/null || echo 0)" "$f"
         done | sort -rn | head -1 | cut -f2-)

# One awk pass does the matching and the KiB/MiB/GiB conversion together, emitting plain
# "key value" lines. An earlier version called a shell function per value and the command
# substitutions came back empty inside the read loop; doing the arithmetic where the parsing
# already happens removes that moving part entirely.
if [ -n "$gc_log" ] && [ -r "$gc_log" ]; then
  gc_time=$(stat -c %Y "$gc_log" 2>/dev/null || echo 0)
  while read -r key value; do
    case "$key" in
      ondisk)   ondisk=$value ;;
      original) original=$value ;;
      pending)  pending=$value ;;
      chunks)   chunks=$value ;;
      dedup)    dedup=$value ;;
    esac
  done < <(awk '
    function tob(v, u,   m) {
      m = (u == "KiB") ? 1024 : (u == "MiB") ? 1048576 : \
          (u == "GiB") ? 1073741824 : (u == "TiB") ? 1099511627776 : 1
      return sprintf("%.0f", v * m)
    }
    /On-Disk usage:/       { print "ondisk",   tob($4, $5) }
    /Original data usage:/ { print "original", tob($5, $6) }
    /Pending removals:/    { print "pending",  tob($4, $5) }
    /On-Disk chunks:/      { print "chunks",   $4 }
    /Deduplication factor:/ { print "dedup",   $4 }
  ' "$gc_log")
fi

{
  echo "# HELP pbs_datastore_ondisk_bytes Datastore size on disk, as the last garbage collection measured it."
  echo "# TYPE pbs_datastore_ondisk_bytes gauge"
  echo "pbs_datastore_ondisk_bytes{datastore=\"$datastore_name\"} $ondisk"
  echo "# HELP pbs_datastore_original_bytes Logical size of everything backed up, before dedup and compression."
  echo "# TYPE pbs_datastore_original_bytes gauge"
  echo "pbs_datastore_original_bytes{datastore=\"$datastore_name\"} $original"
  echo "# HELP pbs_datastore_pending_removal_bytes Garbage awaiting the next collection."
  echo "# TYPE pbs_datastore_pending_removal_bytes gauge"
  echo "pbs_datastore_pending_removal_bytes{datastore=\"$datastore_name\"} $pending"
  echo "# HELP pbs_datastore_chunks Chunk count on disk."
  echo "# TYPE pbs_datastore_chunks gauge"
  echo "pbs_datastore_chunks{datastore=\"$datastore_name\"} $chunks"
  echo "# HELP pbs_datastore_dedup_factor Original bytes divided by on-disk bytes."
  echo "# TYPE pbs_datastore_dedup_factor gauge"
  echo "pbs_datastore_dedup_factor{datastore=\"$datastore_name\"} $dedup"
  echo "# HELP pbs_datastore_gc_timestamp_seconds Modification time of the garbage-collection log these figures came from."
  echo "# TYPE pbs_datastore_gc_timestamp_seconds gauge"
  echo "pbs_datastore_gc_timestamp_seconds{datastore=\"$datastore_name\"} $gc_time"

  echo "# HELP pbs_datastore_snapshots Snapshots held per backup id."
  echo "# TYPE pbs_datastore_snapshots gauge"
  echo "# HELP pbs_datastore_last_snapshot_timestamp_seconds Newest snapshot per backup id."
  echo "# TYPE pbs_datastore_last_snapshot_timestamp_seconds gauge"
  for type_dir in "$datastore_path"/*/; do
    [ -d "$type_dir" ] || continue
    btype=$(basename "$type_dir")
    case "$btype" in .*) continue ;; esac
    for id_dir in "$type_dir"*/; do
      [ -d "$id_dir" ] || continue
      bid=$(basename "$id_dir")
      count=$(find "$id_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
      newest=$(find "$id_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@\n' 2>/dev/null |
               sort -rn | head -1 | cut -d. -f1)
      echo "pbs_datastore_snapshots{datastore=\"$datastore_name\",type=\"$btype\",id=\"$bid\"} $count"
      echo "pbs_datastore_last_snapshot_timestamp_seconds{datastore=\"$datastore_name\",type=\"$btype\",id=\"$bid\"} ${newest:-0}"
    done
  done
} > "$tmp"

chmod 0644 "$tmp"
mv "$tmp" "$out"
