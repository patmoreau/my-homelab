# 🚀 Antigravity & Yubikey Persistence Setup

This configuration optimizes your remote workflow for stability. It prevents Antigravity agents from dying when your laptop sleeps and eliminates "Yubikey fatigue" by reusing your authenticated session.

---

## 1. Local SSH Configuration (~/.ssh/config)

This enables **SSH Multiplexing**. Once you touch your Yubikey once, the connection stays "authorized" in the background for 4 hours.

**File:** `~/.ssh/config`
**Action:** `mkdir -p ~/.ssh/sockets`

```text
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 4h
    PubkeyAcceptedAlgorithms +sk-ssh-ed25519@openssh.com
```

---

## 2. Remote tmux Configuration (~/.tmux.conf)

Install tmux on your remote VM:

```bash
sudo apt update && sudo apt install tmux -y
```

Copy this to your **Remote VM** to keep your agents alive if the connection drops.

**File:** `~/.tmux.conf`

```text
# Enable mouse support
set -g mouse on

# --- Status Bar Styling ---
set -g status-style bg=black,fg=white
set -g status-left-length 30
set -g status-left "#[fg=green]🛡️  #H #[default]"
set -g status-right "#[fg=cyan]Antigravity Session #[fg=yellow]%H:%M #[default]"

# Highlight active window
set-window-option -g window-status-current-style bg=blue,fg=white,bold
```

---

## 3. The "Instant Resume" Workflow

To connect (or reconnect after your laptop wakes up), use this command. It will automatically attach to your existing session or start a new one if none exists.

**Local Alias (.zshrc or .bashrc):**

```bash
alias av-work='ssh -t <your-vm-ip-or-hostname> "tmux a || tmux"'
```

---

## Why this is better

1. **Lid-Close Protection:** If the Wi-Fi drops, `tmux` keeps your Antigravity agents running on the server.
2. **One Touch Rule:** You only touch your Yubikey once every 4 hours.
3. **Zero Battery Impact:** The background socket is a passive file handle.
