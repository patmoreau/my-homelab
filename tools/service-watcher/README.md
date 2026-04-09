# service-watcher

Monitors the QNAP NAS via SSH and automatically pauses I/O-intensive Docker containers during RAID operations (resync, recovery, repair, reshape). Resumes them when the operation finishes. Exposes status via a REST API and Prometheus metrics.

## How it works

1. Every 60 seconds, SSHes into the QNAP and reads `/proc/mdstat`
2. If a RAID operation is detected, configured containers are paused
3. When the operation finishes, containers are resumed

## QNAP setup

Generate a dedicated SSH key on the LXC host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_qnap_monitor -C "qnap-monitor"
```

Add a restricted entry to `~/.ssh/authorized_keys` on the QNAP (replace `YOUR_PUB_KEY`):

```
command="if grep -qE 'check|resync|repair|recovery|reshape' /proc/mdstat; then grep -E 'check|resync|repair|recovery|reshape' /proc/mdstat; else echo 'IDLE'; fi",no-port-forwarding,no-x11-forwarding,no-agent-forwarding YOUR_PUB_KEY
```

> Enable **Home Service** in QNAP Control Panel so `authorized_keys` persists across reboots.

## API

| Endpoint        | Description                |
| --------------- | -------------------------- |
| `GET /api/qnap` | Current QNAP state as JSON |
| `GET /metrics`  | Prometheus metrics         |

## Key metrics

| Metric                         | Description                      |
| ------------------------------ | -------------------------------- |
| `qnap_reachable`               | `1` = SSH reachable              |
| `qnap_raid_active`             | `1` = RAID operation in progress |
| `qnap_raid_progress_percent`   | Operation progress (0–100)       |
| `qnap_state_info{state="..."}` | Current state label              |

## Useful QNAP commands

```bash
cat /proc/mdstat                              # check RAID status
echo check > /sys/block/md1/md/sync_action   # trigger a consistency check
echo idle  > /sys/block/md1/md/sync_action   # stop current operation
```
