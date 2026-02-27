# QNAP RAID Scrub Watcher Implementation

This setup automates the pausing of I/O-intensive Docker containers on the Proxmox/Linux VM when the QNAP NAS begins a RAID scrub.

## 1. QNAP Configuration (Service Key)

To allow the VM to poll the NAS without using your physical security keys, we use a Restricted Service Key.

### Step A: Generate Service Key (On Linux VM)

Run this command in your VM terminal:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_qnap_monitor -C "service-account-qnap-scrub-monitor"

### Step B: Inject Restricted Key into QNAP

Copy the text from your .pub file, then run this echo command on the QNAP terminal (replacing YOUR_PUB_KEY_TEXT with your actual key):

```text
echo "command=\"if grep -E 'check|resync' /proc/mdstat; then grep -E 'check|resync' /proc/mdstat; else echo 'IDLE'; fi\",no-port-forwarding,no-x11-forwarding,no-agent-forwarding YOUR_PUB_KEY_TEXT" >> ~/.ssh/authorized_keys
```

## 2. Docker Implementation (VM Sidecar)

See [docker-compose.yml](./docker-compose.yml).

## 3. Maintenance & Control

### Verification Commands

- Check Logs: docker logs -f qnap_watcher
- Check Health: docker ps (Should show healthy)
- Test Jail: ssh -i ~/.ssh/id_ed25519_qnap_monitor admin@QNAP_IP

### RAID Control (QNAP CLI)

- Trigger Test: echo check > /sys/block/md1/md/sync_action
- Stop Scrub: echo idle > /sys/block/md1/md/sync_action
- Check Status: cat /proc/mdstat

Note: Ensure "Home Service" is enabled in QNAP Control Panel so authorized_keys persists.
