#!/usr/bin/env bash
# Restart Transmission when its RPC stops answering, and report the state as node_exporter
# textfile metrics.
#
# `systemctl is-active` and `podman ps` are both useless as health signals here. Transmission's
# disk thread can block in an NFS commit (nfs_wb_folio -> __nfs_commit_inode) and the main loop
# waits on the same mutex, so the daemon keeps its listening socket, stops calling accept(), and
# the container reports Up the whole time. Seen in the wild as 45 connections queued on 0.0.0.0:9091
# with the service "active" and nothing in its log. The probe therefore has to be a real request.
#
# It goes through the published host port rather than the container IP, so it also catches the
# other failure mode on this host: a leaked netns hijacking the pinned bridge address, which
# refuses the connection while the container is perfectly healthy.
set -uo pipefail

out_dir=/var/lib/node_exporter/textfile
out="$out_dir/transmission_rpc.prom"
tmp="$out.$$"

state_dir=/var/lib/transmission-rpc-check
fail_file="$state_dir/failures"
last_restart_file="$state_dir/last_restart"
restarts_file="$state_dir/restarts"
nfs_file="$state_dir/nfs_written"

# Three strikes before acting: a single missed probe is a busy daemon or a slow NFS round trip,
# not a wedge, and restarting on one would interrupt downloads for nothing.
threshold=3
# Never restart more often than this. If the NAS is the thing that is down, restarting every few
# minutes fixes nothing and only shreds the resume state.
cooldown=1800

# A wedged daemon and a busy one look identical from the RPC: both stop answering. Transmission
# blocks its whole event loop behind the NFS commit while it copies a finished torrent onto the
# NAS, and on an array that writes at 5-12 MB/s (two members are SMR — see
# docs/nas-smr-write-performance.md) an 8 GB film keeps it unresponsive for many minutes.
#
# Restarting then is worse than doing nothing: it kills the copy in flight and leaves a truncated
# file on the NAS, and the next attempt stalls in exactly the same place. That happened three
# times in one evening before this check existed — 22:08, 23:50 and 00:38 — each one destroying
# ~8 GB of transfer.
#
# So progress is the discriminator. If the NFS mount has taken bytes since the previous probe the
# daemon is working, not wedged, and no number of failed probes justifies a restart.
#
# Bytes alone do not cover everything, though: a thread parked in the NFS commit path can sit
# with no new writes for minutes and still be making progress the counter cannot see. That state
# is visible directly — an uninterruptible (D) thread whose wchan is in NFS, which is exactly what
# the original wedge looked like (nfs_wb_folio -> __nfs_commit_inode). It is deliberately NOT a
# veto: the wedge that started all this sat in precisely that state for hours and a restart was
# the only thing that cleared it. So being blocked in NFS raises the bar rather than removing it.
blocked_threshold=10

mkdir -p "$out_dir" "$state_dir"

url="http://127.0.0.1:${TRANSMISSION_RPC_PORT:-9091}/transmission/rpc"
failures=$(cat "$fail_file" 2>/dev/null || echo 0)

# Server-side write bytes for the NAS mount. Field order on the `bytes:` line is
# read write directread directwrite serverread serverwrite — easy to misread, and reading the
# wrong column here would mean the gate never opens.
nfs_written=$(awk '/mounted on \/media / {m=1} m && /^\tbytes:/ {print $7; exit}' /proc/self/mountstats 2>/dev/null)
nfs_written=${nfs_written:-0}
nfs_prev=$(cat "$nfs_file" 2>/dev/null || echo 0)
echo "$nfs_written" > "$nfs_file"
restarts=$(cat "$restarts_file" 2>/dev/null || echo 0)
restarted=0

# 409 is the healthy answer: every RPC call is rejected once to hand out a session id.
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
  -u "${TRANSMISSION_RPC_USER}:${TRANSMISSION_RPC_PASS}" \
  -X POST -d '{"method":"session-get"}' "$url" 2>/dev/null)

if [ "$code" = "409" ] || [ "$code" = "200" ] || [ "$code" = "401" ]; then
  up=1
  failures=0
else
  up=0
  failures=$((failures + 1))
  logger -t transmission-rpc-check "RPC probe failed (HTTP ${code:-none}), consecutive failures: $failures/$effective_threshold${nfs_blocked:+ (blocked in NFS: $nfs_blocked)}"
fi

# Any thread in uninterruptible sleep inside NFS means the kernel is waiting on the NAS, not that
# the daemon has deadlocked in userspace.
nfs_blocked=0
tpid=$(pgrep -x transmission-da 2>/dev/null | head -1)
if [ -n "$tpid" ]; then
  for task in /proc/"$tpid"/task/*; do
    [ -r "$task/stat" ] || continue
    tstate=$(awk '{print $3}' "$task/stat" 2>/dev/null)
    [ "$tstate" = "D" ] || continue
    twchan=$(cat "$task/wchan" 2>/dev/null)
    case "$twchan" in
      *nfs*|*folio_wait*|*wait_on_commit*|*rpc_wait*) nfs_blocked=1 ;;
    esac
  done
fi

if [ "$nfs_blocked" -eq 1 ]; then
  effective_threshold=$blocked_threshold
else
  effective_threshold=$threshold
fi

if [ "$up" -eq 0 ] && [ "$failures" -ge "$effective_threshold" ] && [ "$nfs_written" -gt "$nfs_prev" ]; then
  logger -t transmission-rpc-check "RPC down after $failures probes but the NAS took $(( (nfs_written - nfs_prev) / 1048576 ))MB since the last one - copying, not wedged, leaving it alone"
  failures=0
elif [ "$up" -eq 0 ] && [ "$failures" -ge "$effective_threshold" ]; then
  now=$(date +%s)
  last=$(cat "$last_restart_file" 2>/dev/null || echo 0)
  if [ $((now - last)) -ge "$cooldown" ]; then
    logger -t transmission-rpc-check "restarting transmission.service after $failures failed probes"
    systemctl restart transmission.service
    echo "$now" > "$last_restart_file"
    restarts=$((restarts + 1))
    echo "$restarts" > "$restarts_file"
    failures=0
    restarted=1

    # Podman 4.9 leaks the old netns on recreate and the corpse keeps answering ARP for the
    # pinned address, so a restart on this host trades one outage for another unless the leak
    # is cleared. The reaper needs two runs by design (it only deletes what it saw unclaimed
    # last time), so both are driven here rather than waiting for its own timer.
    if [ -x /usr/local/bin/podman-orphan-check ]; then
      sleep 10
      /usr/local/bin/podman-orphan-check
      /usr/local/bin/podman-orphan-check
    fi
  else
    logger -t transmission-rpc-check "RPC still down but last restart was $((now - last))s ago, inside the ${cooldown}s cooldown"
  fi
fi

echo "$failures" > "$fail_file"

cat > "$tmp" <<METRICS
# HELP transmission_rpc_up Transmission RPC answered a session-get through the published port.
# TYPE transmission_rpc_up gauge
transmission_rpc_up $up
# HELP transmission_rpc_consecutive_failures Consecutive failed RPC probes.
# TYPE transmission_rpc_consecutive_failures gauge
transmission_rpc_consecutive_failures $failures
# HELP transmission_rpc_restarts Restarts this check has performed since the counter file was created.
# TYPE transmission_rpc_restarts counter
transmission_rpc_restarts $restarts
# HELP transmission_rpc_restarted_now 1 when this run restarted the service.
# TYPE transmission_rpc_restarted_now gauge
transmission_rpc_restarted_now $restarted
# HELP transmission_nfs_blocked A transmission thread is in uninterruptible sleep inside NFS.
# TYPE transmission_nfs_blocked gauge
transmission_nfs_blocked $nfs_blocked
# HELP transmission_nfs_written_bytes Server-side bytes written to the NAS mount, as the probe saw it.
# TYPE transmission_nfs_written_bytes counter
transmission_nfs_written_bytes $nfs_written
METRICS
chmod 0644 "$tmp"
mv "$tmp" "$out"
