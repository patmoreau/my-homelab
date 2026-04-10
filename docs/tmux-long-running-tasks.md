# Running Long-Running Tasks via SSH with tmux

When running tasks like `immich-go` on a remote LXC container, your Mac may drop the SSH connection if you step away. `tmux` keeps the session alive on the server so you can detach and reattach at any time.

## Install tmux (if not present)

```bash
ssh -i ~/.ssh/terraform_homelab root@192.168.8.46
apt install -y tmux
```

## Start a named session

```bash
tmux new -s immich-go
```

You are now inside a tmux session. Any command you run here survives SSH disconnects.

## Run your task

> **Note:** Do not pipe TUI apps (like `immich-go`) through `tee`. Piping removes the TTY, which breaks the interactive UI and fills the log file with raw ANSI escape codes. Use one of the logging options below instead.

### Option 1 — Use immich-go's built-in log file (recommended)

Check if the subcommand supports `--log-file`:

```bash
immich-go upload from-google-photos --help | grep -i log
```

If available:

```bash
immich-go upload from-google-photos \
  --server http://localhost:2283 \
  --api-key "$IMMICH_API_KEY" \
  --log-file /opt/docker/immich/immich-go.log \
  /photos/takeout/
```

The TUI renders normally in the terminal while structured logs go to the file.

### Option 2 — Capture via tmux pipe-pane

From a second tmux window or pane, start capturing the session output:

```bash
tmux pipe-pane -t immich-go -o 'cat >> /opt/docker/immich/immich-go.log'
```

Stop capturing (e.g. after the task finishes):

```bash
tmux pipe-pane -t immich-go
```

### Option 3 — Rely on tmux scrollback (simplest)

No extra setup needed. After the task finishes, scroll back through all output with `Ctrl+B` then `[`.

## Detach from the session (leave it running)

Press `Ctrl+B`, then `D`.

Your SSH connection can now be closed — the task keeps running on the server.

## Reattach to the session

```bash
ssh -i ~/.ssh/terraform_homelab root@192.168.8.46
tmux attach -t immich-go
```

You'll see live output as if you never left.

## Scroll through output inside tmux

1. Press `Ctrl+B`, then `[` to enter scroll mode
2. Use arrow keys (or `PgUp`/`PgDn`) to scroll
3. Press `q` to exit scroll mode

## Review the log after the task completes

If you used option 1 or 2 above:

```bash
cat /opt/docker/immich/immich-go.log
# or search for errors:
grep -i "error\|fail\|skip" /opt/docker/immich/immich-go.log
```

If you relied on tmux scrollback (option 3), enter scroll mode and page through the output:

Press `Ctrl+B` then `[`, use `PgUp`/`PgDn` or arrow keys, press `q` to exit.

## What about Grafana / Loki?

Grafana is not useful for one-off CLI tasks like this:

- `immich-go` is a short-lived process — it exposes no Prometheus metrics while running
- The TUI progress bars exist only in the terminal; they are not emitted as structured data
- Loki _could_ ingest the log file via Promtail, but only once you have a `--log-file` and a Promtail scrape job configured for it

If you ever run immich-go on a **recurring schedule** (cron/systemd timer), it's worth adding a Promtail scrape job for `/opt/docker/immich/immich-go.log` so import history shows up in Grafana. For a one-time run, tmux + `--log-file` is the right tool.

## Kill a finished session

Once the task is done and you no longer need the session:

```bash
tmux kill-session -t immich-go
```

## Quick reference

| Action            | Command / Keys                |
| ----------------- | ----------------------------- |
| New session       | `tmux new -s <name>`          |
| Detach            | `Ctrl+B` then `D`             |
| List sessions     | `tmux ls`                     |
| Attach to session | `tmux attach -t <name>`       |
| Kill session      | `tmux kill-session -t <name>` |
| Enter scroll mode | `Ctrl+B` then `[`             |
| Exit scroll mode  | `q`                           |
