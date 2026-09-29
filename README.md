# TunGuard Installer

One-command installer for [TunGuard](https://github.com/TunGuard/tanguard-binary) — a userspace WireGuard VPN server with a web dashboard and SSH gateway.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TunGuard/get/main/installer.sh | bash
```

# Install TunGuard client

curl -fsSL https://raw.githubusercontent.com/TunGuard/get/main/client.sh | bash

The script will:
1. Detect your OS and architecture (linux/amd64, arm64, or 386)
2. Save a safety backup of your data (if any) to `/var/backups/`
3. Download the latest release binary from GitHub
4. Install it to `/usr/local/bin/tanguard`
5. On a **fresh install**, set up a systemd service to run automatically on boot

## Updating (safe, nothing breaks)

Re-run the same install command to update. The update is **code-only**:

- **Your data is never touched.** Peers, the server key, dashboard login, and SSH host key live in `/var/lib/tanguard` and the installer never modifies that directory.
- **Your service configuration is preserved.** If `/etc/systemd/system/tanguard.service` already exists, the installer keeps it byte-for-byte — custom ports, subnets, and credentials stay exactly as you set them. The service is simply restarted with the new binary.
- **A safety backup** of your data is saved to `/var/backups/tanguard-<timestamp>.tar.gz` before each install.
- Restoring existing peers and keys works automatically because the app reads them from `DATA_DIR` on startup. You can also download/restore a full backup from the web dashboard (Settings → Backup & Restore).

The web dashboard and SSH gateway are **disabled by default**. During a fresh install you'll be asked whether you want to enable them:

```text
Set up as a systemd service? [Y/n] 
Enable the web dashboard? [y/N]    # default: No
Enable the SSH gateway (jump host)? [y/N]  # default: No
```

Answer `y` to any option you want enabled. You can always enable them later by editing the service file (see below).

## What is TunGuard?

TunGuard is a self-contained WireGuard server that runs entirely in userspace — no kernel modules, no `apt install wireguard`, no kernel configuration.

- **Web dashboard** — manage peers, generate configs, scan QR codes from your browser
- **SSH gateway** — SSH into any connected peer through the server
- **HTTP API** — integrate with your own tools (PHP, curl, etc.)
- **Single binary** — statically linked, copy it to any Linux server

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/TunGuard/get/main/installer.sh | bash

# Run manually (if not using systemd)
sudo tanguard

# With the web dashboard:
sudo tanguard -web

# Open http://yourserver:9000
# Login: admin / tanguard
```

## systemd Management

```bash
sudo systemctl start tanguard
sudo systemctl stop tanguard
sudo systemctl restart tanguard
sudo systemctl status tanguard
sudo journalctl -u tanguard -f
```

## Config

Edit the environment variables in `/etc/systemd/system/tanguard.service`, then restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart tanguard
```

| Variable | Default | Description |
|---|---|---|
| `WG_LISTEN_PORT` | `13231` | WireGuard UDP port |
| `WG_ADDRESS` | `10.100.0.1/24` | Server IP on VPN subnet |
| `API_LISTEN` | `:9000` | Web UI + API address |
| `WEB_USERNAME` | `admin` | Dashboard login |
| `WEB_PASSWORD` | `tanguard` | Dashboard password |
| `SSH_USER` | `tanguard` | SSH gateway user |
| `SSH_PASSWORD` | `tanguard` | SSH gateway pass |

See the full [README](https://github.com/TunGuard/tanguard-binary) for all options.

## Uninstall

```bash
sudo systemctl stop tanguard
sudo systemctl disable tanguard
sudo rm /etc/systemd/system/tanguard.service
sudo rm /usr/local/bin/tanguard
sudo systemctl daemon-reload
```
