# linux-auto-update

A universal, unattended Linux updater: it detects the distro's package manager
and runs a full **update → upgrade → dist-upgrade**, then schedules itself to run
every night at **midnight** via a systemd timer (or cron as a fallback).

## Supported package managers

| Manager | Distros | Action |
|---------|---------|--------|
| `apt`   | Debian, Ubuntu, Kali, Mint, Raspberry Pi OS | `update` → `upgrade` → `dist-upgrade` → `autoremove` |
| `dnf`   | Fedora, RHEL 8+, Rocky, Alma | `upgrade --refresh` → `autoremove` |
| `yum`   | CentOS 7 / older RHEL | `update` → `autoremove` |
| `pacman`| Arch, Manjaro | `-Syu` full upgrade + orphan cleanup |
| `zypper`| openSUSE, SLE | `dup` on Tumbleweed, `update` on Leap |
| `apk`   | Alpine | `update` → `upgrade` |

## Quick install (one-liner)

```sh
curl -fsSL https://raw.githubusercontent.com/victorgit34-stack/claude/main/linux-auto-update/install-auto-update.sh | sudo bash
```

This installs `auto-update.sh` to `/usr/local/sbin/` and enables a nightly
midnight run. To pick a different time, pass `HH:MM`:

```sh
curl -fsSL https://raw.githubusercontent.com/victorgit34-stack/claude/main/linux-auto-update/install-auto-update.sh | sudo bash -s -- 03:30
```

## Manual install

```sh
git clone https://github.com/victorgit34-stack/claude.git
cd claude/linux-auto-update
sudo ./install-auto-update.sh          # midnight; or pass HH:MM
```

## Run it once, by hand

```sh
sudo /usr/local/sbin/auto-update.sh
```

## What to expect

- **Non-interactive and safe for unattended runs.** On package config conflicts
  it keeps your existing files; a lock prevents overlapping runs.
- **Logs** to `/var/log/auto-update/` (last 30 runs kept).
- **Never reboots on its own** — it only logs a note when a reboot is required.
- **Within-release only.** It applies rolling/security updates; it does **not**
  perform major release jumps (e.g. Ubuntu 22.04 → 24.04).

## Check the schedule

```sh
systemctl list-timers auto-update.timer     # systemd
# or
cat /etc/cron.d/auto-update                  # cron fallback
```

## Uninstall

```sh
sudo systemctl disable --now auto-update.timer 2>/dev/null
sudo rm -f /etc/systemd/system/auto-update.{service,timer} /etc/cron.d/auto-update /usr/local/sbin/auto-update.sh
sudo systemctl daemon-reload 2>/dev/null
```
