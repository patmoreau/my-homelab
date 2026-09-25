#!/usr/bin/env bash
# Reap leaked netavark state on the podman bridge, and report what was found as
# node_exporter textfile metrics.
#
# Podman 4.9 can leave a container's netns and veth behind when the container is recreated
# (a Renovate image bump or an ansible run is enough). The Quadlet units pin IP=, so the
# replacement reuses the address the corpse still answers ARP for; the host then reaches
# the dead netns and every connection to the published port is refused while the container
# itself is healthy. The symptom is a Bad Gateway, or a refused scrape, with nothing wrong
# in the container's own logs. See the "Static IPs" note in ansible/README.md.
#
# This used to only count the leaks. Counting them turned out to be the smaller half of the
# job: a leak sat across every host for a day, reported faithfully by the metric below,
# while cAdvisor stayed unreachable everywhere and Grafana re-notified about it every few
# hours. Deleting the orphan veth and flushing the neighbour entry restores the address
# immediately — the live container does not even need restarting.
set -uo pipefail

out_dir=/var/lib/node_exporter/textfile
out="$out_dir/podman_orphans.prom"
tmp="$out.$$"

# Orphans seen on the previous run. A veth is only deleted when it was unclaimed twice in a
# row: a container that is mid-start already has its veth on the bridge but is not yet in
# `podman ps`, and deleting that one would break the very container being started. Two
# strikes costs one timer interval of downtime on a real leak and takes that race away.
state_dir=/var/lib/podman-orphan-check
state="$state_dir/orphans.prev"

mkdir -p "$out_dir" "$state_dir"

orphans=0
reaped=0
hijacked=0
stale_dnat=0
reaped_dnat=0
seen=""

if command -v podman >/dev/null 2>&1 && ip link show podman0 >/dev/null 2>&1; then
  previous=$(cat "$state" 2>/dev/null || true)

  # Host-side ifindex of every live container's eth0. A veth on podman0 that no live
  # container claims is a leak. Containers on the host network report the LXC's own eth0,
  # which is not on podman0 and so never matches a veth here.
  claimed=""
  for cid in $(podman ps -q 2>/dev/null); do
    pid=$(podman inspect "$cid" --format '{{.State.Pid}}' 2>/dev/null)
    [ -n "$pid" ] && [ "$pid" != "0" ] || continue
    idx=$(nsenter -t "$pid" -n ip -o link show eth0 2>/dev/null | sed -n 's/.*eth0@if\([0-9]*\).*/\1/p')
    [ -n "$idx" ] && claimed="$claimed $idx"
  done

  # Identified by index, name and MAC together: the kernel reuses an ifindex, and acting on
  # a stale record from the previous run is exactly how this would delete a live interface.
  while read -r idx name; do
    [ -n "$idx" ] || continue
    case " $claimed " in
      *" $idx "*) continue ;;
    esac

    orphans=$((orphans + 1))
    mac=$(ip -o link show "$name" 2>/dev/null | sed -n 's/.*link\/ether \([0-9a-f:]*\).*/\1/p')
    key="$idx/$name/$mac"

    case " $previous " in
      *" $key "*)
        if ip link delete "$name" 2>/dev/null; then
          reaped=$((reaped + 1))
          logger -t podman-orphan-check "deleted orphan veth $name (ifindex $idx, mac $mac)"
        else
          seen="$seen $key"
        fi
        ;;
      # First sighting: recorded, not touched.
      *) seen="$seen $key" ;;
    esac
  done < <(ip -o link show master podman0 2>/dev/null | sed -n 's/^\([0-9]*\): \(veth[0-9]*\)@.*/\1 \2/p')

  # The stale entry outlives the interface it pointed at, and until it ages out the address
  # still resolves to the corpse.
  [ "$reaped" -gt 0 ] && ip neigh flush dev podman0

  # The other half of the same leak: netavark's hostport DNAT rules outlive the mapping
  # when a container stops publishing a port (moved to Network=host, port removed, or
  # simply recreated badly). The rule keeps sending the host's own IPv4 traffic to a bridge
  # address nothing answers on, so the port times out — and because the DNAT lives in
  # `table ip nat`, IPv6 to the same port still works, which makes it read like an
  # application bug rather than a firewall one. Published ports of live containers are
  # never touched.
  published=""
  for cid in $(podman ps -q 2>/dev/null); do
    ports=$(podman inspect "$cid" \
      --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}} {{end}}{{end}}' 2>/dev/null)
    published="$published $ports"
  done

  while read -r port handle; do
    [ -n "$port" ] && [ -n "$handle" ] || continue
    case " $published " in
      *" $port "*) continue ;;
    esac

    stale_dnat=$((stale_dnat + 1))
    key="dnat/$port"
    case " $previous " in
      *" $key "*)
        if nft delete rule ip nat NETAVARK-HOSTPORT-DNAT handle "$handle" 2>/dev/null; then
          reaped_dnat=$((reaped_dnat + 1))
          logger -t podman-orphan-check "deleted stale hostport DNAT rule for port $port"
        else
          seen="$seen $key"
        fi
        ;;
      *) seen="$seen $key" ;;
    esac
  done < <(nft -a list chain ip nat NETAVARK-HOSTPORT-DNAT 2>/dev/null |
           sed -n 's/.*dport \([0-9]*\).*# handle \([0-9]*\)/\1 \2/p')

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

  # Written once both passes have contributed their first sightings.
  printf '%s\n' "$seen" > "$state"
fi

# Written to a temp file and moved into place: the collector can read the directory at
# any moment and a half-written file would scrape as a parse error.
cat > "$tmp" <<METRICS
# HELP podman_orphan_veths Leaked veth interfaces on podman0 with no live container.
# TYPE podman_orphan_veths gauge
podman_orphan_veths $orphans
# HELP podman_orphan_veths_reaped Leaked veth interfaces deleted on this run.
# TYPE podman_orphan_veths_reaped gauge
podman_orphan_veths_reaped $reaped
# HELP podman_stale_hostport_dnat Hostport DNAT rules whose port no live container publishes.
# TYPE podman_stale_hostport_dnat gauge
podman_stale_hostport_dnat $stale_dnat
# HELP podman_stale_hostport_dnat_reaped Stale hostport DNAT rules deleted on this run.
# TYPE podman_stale_hostport_dnat_reaped gauge
podman_stale_hostport_dnat_reaped $reaped_dnat
# HELP podman_arp_hijacked_ips Live container IPs whose ARP entry points at a dead netns.
# TYPE podman_arp_hijacked_ips gauge
podman_arp_hijacked_ips $hijacked
METRICS
chmod 0644 "$tmp"
mv "$tmp" "$out"
