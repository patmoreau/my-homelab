# Tailscale shadows the LAN route on the Mac

## Symptom

After every Mac reboot, SSH to all homelab hosts fails:

```
connect to address 192.168.8.x port 22: No route to host
```

Hosts are healthy. The Mac's routing table is the problem.

## Cause

`GL-MT6000` (Flint 2) advertises `192.168.8.0/24` as a Tailscale subnet route. The Mac
accepts routes (`RouteAll = true`), so Tailscale installs `192.168.8.0/24` via `utun7`.
That route shadows the `en0` route for the LAN the Mac is already on.

## Diagnose

```bash
netstat -rn -f inet | grep 192.168.8     # two rows: one en0, one utun7 = the signature
tailscale debug prefs | grep RouteAll    # true = accepting routes
tailscale status --json                  # PrimaryRoutes lists 192.168.8.0/24
```

## Wrong turns to avoid

- `pve-homelab` (192.168.8.10) drops ICMP. `ping` fails on a healthy host, so do not judge
  liveness with `ping`. Use `nc -z -w 2 <ip> 22`.
- Results depend on the binary: Apple `/usr/bin/ssh`, `nc`, and `curl` work while Homebrew
  `ssh` fails. Cloned `/32` ARP host routes on `en0` appear as traffic flows, and those beat
  the tunnel route. This timing looks like a macOS Local Network privacy denial. It is not.

## Fix

Immediate, for a deploy:

```bash
sudo route -n delete -net 192.168.8.0/24 -interface utun7
# or
ANSIBLE_SSH_EXECUTABLE=/usr/bin/ssh ansible-playbook ...
```

Permanent fix is a decision: turn off accept-routes on the Mac, or stop advertising
`192.168.8.0/24` from the router. See also `docs/iot-vlan-network.md` for the router setup.
