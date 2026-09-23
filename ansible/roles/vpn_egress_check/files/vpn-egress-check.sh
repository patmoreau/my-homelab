#!/usr/bin/env bash
# Report which network this host's traffic actually leaves on, as node_exporter textfile
# metrics.
#
# The VPN is enforced on the router by a per-MAC policy, not on this host, so there is no
# kill switch: if the tunnel drops, everything here silently falls back to the home ISP
# address and keeps going — torrent peer traffic included. Nothing on the host knows.
# This asks an external service what address the traffic arrives from and exports the
# answer, so the leak is visible instead of silent.
set -uo pipefail

expected_asn="${1:?expected ASN required}"
home_asn="${2:?home ASN required}"
url="${3:?lookup URL required}"

out_dir=/var/lib/node_exporter/textfile
out="$out_dir/vpn_egress.prom"
tmp="$out.$$"

mkdir -p "$out_dir"

success=0
on_expected=0
on_home=0

# --max-time covers the case that matters most: with the tunnel half-up the request can
# hang rather than fail, and a check that never returns reports nothing at all.
if body=$(curl -fsS --max-time 20 "$url" 2>/dev/null); then
  org=$(printf '%s' "$body" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$org" ]; then
    success=1
    case "$org" in
      *"$expected_asn"*) on_expected=1 ;;
    esac
    case "$org" in
      *"$home_asn"*) on_home=1 ;;
    esac
  fi
fi

# Written to a temp file and moved into place: the collector can read the directory at
# any moment and a half-written file would scrape as a parse error.
cat > "$tmp" <<METRICS
# HELP vpn_egress_check_success Whether the last exit-address lookup returned an answer.
# TYPE vpn_egress_check_success gauge
vpn_egress_check_success $success
# HELP vpn_egress_on_expected_asn Whether traffic is leaving on the expected VPN ASN.
# TYPE vpn_egress_on_expected_asn gauge
vpn_egress_on_expected_asn $on_expected
# HELP vpn_egress_on_home_asn Whether traffic is leaving on the home ISP ASN (a leak).
# TYPE vpn_egress_on_home_asn gauge
vpn_egress_on_home_asn $on_home
# HELP vpn_egress_check_timestamp_seconds Unix time of the last completed check.
# TYPE vpn_egress_check_timestamp_seconds gauge
vpn_egress_check_timestamp_seconds $(date +%s)
METRICS
chmod 0644 "$tmp"
mv "$tmp" "$out"
