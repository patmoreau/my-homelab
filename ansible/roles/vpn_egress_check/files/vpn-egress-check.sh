#!/usr/bin/env bash
# Report which public address this host's traffic actually leaves on, as node_exporter
# textfile metrics.
#
# The VPN is enforced on the router by a per-MAC policy, not on this host. The router's
# kill switch should block traffic when the tunnel drops, but nothing on the host can tell
# whether it did: if it ever fails, everything here silently falls back to the home ISP
# address and keeps going — torrent peer traffic included. This asks an external service
# what address the traffic arrives from and exports the answer, so a leak is visible.
#
# Nothing here decides what counts as a leak. The same check runs on a host outside the
# VPN policy (side=baseline), and the Grafana rule fires when a protected host reports the
# same exit address as the baseline — so VPN exit rotations, a new home IP or a new ISP
# need no configuration change.
set -uo pipefail

side="${1:?side required (protected or baseline)}"
url="${2:?lookup URL required}"

out_dir=/var/lib/node_exporter/textfile
out="$out_dir/vpn_egress.prom"
tmp="$out.$$"

mkdir -p "$out_dir"

success=0
ip=""

# --max-time covers the case that matters most: with the tunnel half-up the request can
# hang rather than fail, and a check that never returns reports nothing at all.
if body=$(curl -fsS --max-time 20 "$url" 2>/dev/null); then
  ip=$(printf '%s' "$body" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  # Only an address-shaped answer is trusted; anything else would land in a label.
  if printf '%s' "$ip" | grep -Eq '^[0-9A-Fa-f.:]+$'; then
    success=1
  else
    ip=""
  fi
fi

# Written to a temp file and moved into place: the collector can read the directory at
# any moment and a half-written file would scrape as a parse error.
{
  echo "# HELP vpn_egress_check_success Whether the last exit-address lookup returned an answer."
  echo "# TYPE vpn_egress_check_success gauge"
  echo "vpn_egress_check_success{side=\"$side\"} $success"
  echo "# HELP vpn_egress_ip_info Public address this host's traffic leaves on (value is always 1)."
  echo "# TYPE vpn_egress_ip_info gauge"
  # Omitted on a failed lookup, so a stale address is never compared.
  if [ "$success" = 1 ]; then
    echo "vpn_egress_ip_info{side=\"$side\",ip=\"$ip\"} 1"
  fi
  echo "# HELP vpn_egress_check_timestamp_seconds Unix time of the last completed check."
  echo "# TYPE vpn_egress_check_timestamp_seconds gauge"
  echo "vpn_egress_check_timestamp_seconds{side=\"$side\"} $(date +%s)"
} > "$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$out"
