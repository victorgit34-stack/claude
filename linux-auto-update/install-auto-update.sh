#!/usr/bin/env bash
#
# install-auto-update.sh — installs auto-update.sh and schedules it nightly.
# Prefers a systemd timer (survives downtime via Persistent=true); falls back
# to cron if systemd isn't the init.
#
# Usage:
#   sudo ./install-auto-update.sh            # default: nightly at 00:00 (midnight)
#   sudo ./install-auto-update.sh 12:00      # noon
#   sudo ./install-auto-update.sh 03:30      # any HH:MM
#
set -eu

TIME="${1:-00:00}"                                   # HH:MM, 24-hour
HR="${TIME%%:*}"
MIN="${TIME##*:}"
DEST=/usr/local/sbin/auto-update.sh
RAW_BASE="https://raw.githubusercontent.com/victorgit34-stack/claude/main/linux-auto-update"

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

# Find auto-update.sh next to this installer; otherwise fetch it from the repo
# (so `curl -fsSL .../install-auto-update.sh | sudo bash` works).
SELF_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/auto-update.sh" ]; then
  install -m 0755 "$SELF_DIR/auto-update.sh" "$DEST"
else
  echo "Fetching auto-update.sh from $RAW_BASE ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_BASE/auto-update.sh" -o "$DEST"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$DEST" "$RAW_BASE/auto-update.sh"
  else
    echo "Need curl or wget to fetch auto-update.sh." >&2; exit 1
  fi
  chmod 0755 "$DEST"
fi
echo "Installed $DEST"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat >/etc/systemd/system/auto-update.service <<EOF
[Unit]
Description=Universal system update/upgrade/dist-upgrade
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$DEST
EOF

  cat >/etc/systemd/system/auto-update.timer <<EOF
[Unit]
Description=Run auto-update nightly at $TIME

[Timer]
OnCalendar=*-*-* $HR:$MIN:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now auto-update.timer
  echo "Scheduled via systemd timer at $TIME (±5 min jitter)."
  systemctl list-timers auto-update.timer --no-pager || true
else
  printf '%s %s * * * root %s\n' "$MIN" "$HR" "$DEST" >/etc/cron.d/auto-update
  chmod 0644 /etc/cron.d/auto-update
  echo "Scheduled via cron at $TIME: $(cat /etc/cron.d/auto-update)"
fi
