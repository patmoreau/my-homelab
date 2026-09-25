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

# Three strikes before acting: a single missed probe is a busy daemon or a slow NFS round trip,
# not a wedge, and restarting on one would interrupt downloads for nothing.
threshold=3
# Never restart more often than this. If the NAS is the thing that is down, restarting every few
# minutes fixes nothing and only shreds the resume state.
cooldown=1800

mkdir -p "$out_dir" "$state_dir"

url="http://127.0.0.1:${TRANSMISSION_RPC_PORT:-9091}/transmission/rpc"
failures=$(cat "$fail_file" 2>/dev/null || echo 0)
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
  logger -t transmission-rpc-check "RPC probe failed (HTTP ${code:-none}), consecutive failures: $failures"
fi

if [ "$up" -eq 0 ] && [ "$failures" -ge "$threshold" ]; then
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
METRICS
chmod 0644 "$tmp"
mv "$tmp" "$out"
