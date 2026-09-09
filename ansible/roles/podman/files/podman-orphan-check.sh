#!/usr/bin/env bash
# Report leaked netavark state on the podman bridge as node_exporter textfile metrics.
#
# Podman 4.9 can leave a container's netns and veth behind when the container is recreated
# (a Renovate image bump is enough). The Quadlet units pin IP=, so the replacement reuses
# the address the corpse still answers ARP for; the host then reaches the dead netns and
# every connection to the published port is refused while the container itself is healthy.
# The symptom is a Bad Gateway with nothing wrong in the container's own logs, so it is
# worth catching from the outside. See the "Static IPs" note in ansible/README.md.
set -uo pipefail

out_dir=/var/lib/node_exporter/textfile
out="$out_dir/podman_orphans.prom"
tmp="$out.$$"

mkdir -p "$out_dir"

orphans=0
hijacked=0

if command -v podman >/dev/null 2>&1 && ip link show podman0 >/dev/null 2>&1; then
  # Host-side ifindex of every live container's eth0. A veth on podman0 that no live
  # container claims is a leak.
  claimed=""
  for cid in $(podman ps -q 2>/dev/null); do
    pid=$(podman inspect "$cid" --format '{{.State.Pid}}' 2>/dev/null)
    [ -n "$pid" ] && [ "$pid" != "0" ] || continue
    idx=$(nsenter -t "$pid" -n ip -o link show eth0 2>/dev/null | sed -n 's/.*eth0@if\([0-9]*\).*/\1/p')
    [ -n "$idx" ] && claimed="$claimed $idx"
  done

  while read -r idx _name; do
    [ -n "$idx" ] || continue
    case " $claimed " in
      *" $idx "*) ;;
      *) orphans=$((orphans + 1)) ;;
    esac
  done < <(ip -o link show master podman0 2>/dev/null | sed -n 's/^\([0-9]*\): \(veth[0-9]*\)@.*/\1 \2/p')

  # A leak only breaks traffic once it answers ARP for an address a live container is
  # using, so count that separately - it is the condition actually worth acting on.
  # Containers sharing a netns report the same address and are counted once each; the
  # metric is a yes/no signal in practice, not an exact interface count.
  for cid in $(podman ps -q 2>/dev/null); do
    cip=$(podman inspect "$cid" --format '{{.NetworkSettings.IPAddress}}' 2>/dev/null)
    cmac=$(podman inspect "$cid" --format '{{.NetworkSettings.MacAddress}}' 2>/dev/null)
    [ -n "$cip" ] && [ -n "$cmac" ] || continue
    # Force resolution: an uncached address is exactly the state where a leak can win.
    ping -c1 -W1 "$cip" >/dev/null 2>&1
    arp=$(ip neigh show "$cip" 2>/dev/null | sed -n 's/.*lladdr \([0-9a-f:]*\).*/\1/p')
    [ -n "$arp" ] && [ "$arp" != "$cmac" ] && hijacked=$((hijacked + 1))
  done
fi

# Written to a temp file and moved into place: the collector can read the directory at
# any moment and a half-written file would scrape as a parse error.
cat > "$tmp" <<METRICS
# HELP podman_orphan_veths Leaked veth interfaces on podman0 with no live container.
# TYPE podman_orphan_veths gauge
podman_orphan_veths $orphans
# HELP podman_arp_hijacked_ips Live container IPs whose ARP entry points at a dead netns.
# TYPE podman_arp_hijacked_ips gauge
podman_arp_hijacked_ips $hijacked
METRICS
chmod 0644 "$tmp"
mv "$tmp" "$out"
