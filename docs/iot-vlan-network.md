# IoT VLAN Network (Flint 2 → Proxmox → LXC)

Carries the IoT network (`192.168.10.x`, VLAN 10) from the Flint 2 router (GL-MT6000) to LXC containers over the **same physical cable** as the main LAN, because the Proxmox host has only two NICs (main LAN on `eth0`/`vmbr0`, direct NAS link on `eth1`/`vmbr1`).

The end result: `lxc-homeassistant` gets an `eth2` on the IoT network and can reach/discover IoT devices, while IoT devices stay isolated from each other and from the main LAN.

## Topology

```text
Flint 2 lan1 (trunk: VLAN 1 untagged + VLAN 10 tagged)
   │
   └─ Proxmox eth0 / vmbr0 (VLAN aware)
        ├─ eth0  → 192.168.8.x  (main LAN, untagged)
        └─ eth2  → 192.168.10.x (IoT, VLAN 10 tagged) [per container]
```

On the Flint 2, VLAN 10 is split off the physical port with an `8021q` subinterface (`lan1.10`) and bridged into the existing IoT bridge (`br-iot`).

## 0. Back up first (Flint 2)

`/tmp` is RAM-only and lost on reboot — write the backup to persistent storage:

```bash
ssh root@192.168.8.1
uci show network > /etc/network-backup.txt
uci show firewall > /etc/firewall-backup.txt
uci show dhcp > /etc/dhcp-backup.txt
```

To revert a section later: re-apply the saved values with `uci set ...`, then `uci commit <config> && service network restart`.

## 1. Identify the Proxmox LAN port (Flint 2)

The trunk must be configured on the port the Proxmox host is physically wired to. BusyBox lacks `xargs -I`, so use `while read`:

```bash
for port in lan1 lan2 lan3 lan4 lan5; do
  echo -n "$port: "
  bridge fdb show dev $port \
    | grep -v "permanent\|33:33\|01:00\|ff:ff\|00:00:00:00" \
    | awk '{print $1}' \
    | while read mac; do ip neigh show | grep -i "$mac"; done \
    | grep -o '192\.[0-9.]*' | head -1 || echo "nothing"
done
```

Proxmox is at `192.168.8.10`. In this homelab it is on **lan1**. Substitute your port everywhere below if different.

## 2. Create the VLAN 10 trunk (Flint 2)

> **Do NOT** use bridge VLAN filtering (`vlan_filtering=1` on `br-lan`) — enabling it without explicitly re-declaring VLAN 1 on every port drops all main-LAN traffic and kills internet. The subinterface approach below avoids filtering entirely.

First find the `br-iot` device index (it is **not** guaranteed to be `@device[7]` on a fresh router):

```bash
uci show network | grep -B1 "name='br-iot'"
# e.g. output: network.@device[7].name='br-iot'  → index is 7
```

Then create `lan1.10` and add it to `br-iot` (replace `[7]` with the index found above):

```bash
uci add network device
uci set network.@device[-1].name='lan1.10'
uci set network.@device[-1].type='8021q'
uci set network.@device[-1].ifname='lan1'
uci set network.@device[-1].vid='10'

uci set network.@device[7].ports='br-lan.10 lan1.10'
uci commit network
service network restart
```

Internet on the main LAN should be unaffected. Verify:

```bash
ip link show lan1.10        # state UP, master br-iot
ip link show master br-iot  # lan1.10 listed
```

## 3. Enable VLAN awareness on vmbr0 (Proxmox)

**UI:** Node → Network → `vmbr0` → Edit → check **VLAN aware** → Apply Configuration.

**CLI:** add `bridge-vlan-aware yes` (and `bridge-vids 2-4094`) to the `vmbr0` stanza in `/etc/network/interfaces`, then:

```bash
ifreload -a
```

## 4. Attach an IoT interface to a container (Terraform)

Add `vlan_interfaces` to the container module in `terraform/lxc-<name>.tf`. Set `mac_address` to pin a static MAC so the DHCP reservation (step 5c) survives container recreation — without it Proxmox generates a new random MAC each time and the reservation no longer matches:

```hcl
vlan_interfaces = [
  { name = "eth2", bridge = "vmbr0", vlan = 10, mac_address = "BC:24:11:00:BF:1F" }
]
```

`terraform apply` detaches/reattaches the interface with the VLAN tag. The `modules/lxc` module configures it for DHCP. Ubuntu 24.04 LXCs use **systemd-networkd**, not netplan — Proxmox writes `/etc/systemd/network/eth2.network` automatically. Verify inside the container:

```bash
networkctl status eth2 | grep Address   # expect 192.168.10.x
```

If it shows no IPv4, force a lease: `networkctl renew eth2`.

## 5. Allow Home Assistant to reach IoT devices (Flint 2)

By default the `iot` firewall zone has `forward=REJECT` (devices isolated from each other) **and** the network suppresses broadcast ARP from non-router clients. Symptom: HA can reach the internet but `ping <iot-device>` returns `Destination Host Unreachable` — its broadcast ARP gets no reply, while the router's unicast ARP does. Confirm with `tcpdump -i br-iot -e arp -n` on the Flint 2 (install via `opkg update && opkg install tcpdump`).

Three pieces are required:

### 5a. Proxy ARP

The router answers ARP on behalf of isolated devices. Plain `proxy_arp` is **not** sufficient because HA and the devices share `br-iot`; `proxy_arp_pvlan` is the one that works for same-interface (private-VLAN) isolation, and it has no UCI option:

```bash
uci set network.iot.proxy_arp='1'
uci commit network

echo 1 > /proc/sys/net/ipv4/conf/br-iot/proxy_arp_pvlan
echo 'net.ipv4.conf.br-iot.proxy_arp_pvlan=1' >> /etc/sysctl.conf
```

Confirmed to survive reboot via `/etc/sysctl.conf` in this setup. After a reboot verify:

```bash
cat /proc/sys/net/ipv4/conf/br-iot/proxy_arp_pvlan   # expect 1
```

### 5b. Firewall rules

Allow traffic both directions. **Must set `proto='all'`** — fw3 defaults new rules to TCP+UDP and silently drops ICMP and other protocols. Scoping by HA's IP only (no per-device IP) covers **all current and future IoT devices**:

```bash
# HA -> any IoT device
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-HA-to-IoT'
uci set firewall.@rule[-1].src='iot'
uci set firewall.@rule[-1].src_ip='192.168.10.167'
uci set firewall.@rule[-1].dest='iot'
uci set firewall.@rule[-1].proto='all'
uci set firewall.@rule[-1].target='ACCEPT'

# Any IoT device -> HA (callbacks, push)
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-IoT-to-HA'
uci set firewall.@rule[-1].src='iot'
uci set firewall.@rule[-1].dest='iot'
uci set firewall.@rule[-1].dest_ip='192.168.10.167'
uci set firewall.@rule[-1].proto='all'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
service firewall restart
```

### 5c. DHCP reservation for HA

The firewall rules are pinned to `192.168.10.167`, so HA must always get that IP. Reserve it by MAC (`bc:24:11:00:bf:1f` is `lxc-homeassistant`'s `eth2`):

```bash
uci add dhcp host
uci set dhcp.@host[-1].name='lxc-homeassistant'
uci set dhcp.@host[-1].mac='bc:24:11:00:bf:1f'
uci set dhcp.@host[-1].ip='192.168.10.167'
uci commit dhcp
service dnsmasq restart
```

## 6. Verify

From `lxc-homeassistant`:

```bash
ping -c3 192.168.10.173   # any IoT device
```

A working ping may print `Redirect Host` messages from `192.168.10.1` — harmless (the router telling HA it can route directly via L3).

## Troubleshooting reference

| Symptom                                                  | Cause                                                           | Fix                                                                       |
| -------------------------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Main LAN loses internet after VLAN change                | `vlan_filtering=1` enabled without VLAN 1 declared on all ports | Revert; use the `8021q` subinterface method (step 2)                      |
| `lan1.10` missing after reboot                           | `bridge vlan add` used instead of UCI                           | Use the UCI `device` config (step 2) — it persists                        |
| `eth2` has no IPv4                                       | DHCP not triggered / VLAN tag mismatch                          | `networkctl renew eth2`; confirm `vmbr0` is VLAN aware and TF `vlan = 10` |
| `Destination Host Unreachable` to IoT device             | broadcast ARP suppressed                                        | `proxy_arp_pvlan=1` on `br-iot` (step 5a)                                 |
| Ping replies but only the router responds to ARP, not HA | `proxy_arp` set but not `proxy_arp_pvlan`                       | set `proxy_arp_pvlan` (same interface needs it)                           |
| TCP works but ping/mDNS doesn't                          | fw3 rule defaulted to TCP+UDP                                   | set `proto='all'` on the rules (step 5b)                                  |
| Rules break after HA IP changes                          | no DHCP reservation                                             | reserve HA's IP by MAC (step 5c)                                          |
