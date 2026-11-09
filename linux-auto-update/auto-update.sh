#!/usr/bin/env bash
#
# auto-update.sh — universal Linux update / upgrade / dist-upgrade
#
# Detects the distro's package manager and performs a full, non-interactive
# system upgrade. Safe to run unattended from cron or a systemd timer.
#
# Supported package managers:
#   apt    (Debian, Ubuntu, Kali, Mint, Raspberry Pi OS)
#   dnf    (Fedora, RHEL 8+, Rocky, Alma)
#   yum    (CentOS 7 / older RHEL)
#   pacman (Arch, Manjaro)
#   zypper (openSUSE, SLE)
#   apk    (Alpine)
#
# "dist-upgrade" is an apt concept; for every other manager this maps to that
# distro's nearest full-upgrade (see per-manager blocks below).
#
# Usage:  sudo ./auto-update.sh
# Logs:   /var/log/auto-update/update-YYYYMMDD-HHMMSS.log
#
set -u
set -o pipefail

LOGDIR="/var/log/auto-update"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/update-$STAMP.log"
LOCK="/run/auto-update.lock"
KEEP_LOGS=30                      # number of log files to retain
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a         # let Debian/Ubuntu auto-restart services

# --- require root (re-exec via sudo if available) ---
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then exec sudo -E "$0" "$@"; fi
  echo "This script must run as root." >&2
  exit 1
fi

mkdir -p "$LOGDIR"

# --- single-instance lock so overlapping runs can't collide ---
exec 9>"$LOCK" || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { echo "Another auto-update run is in progress; exiting."; exit 0; }
fi

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
run() { log "+ $*"; "$@" >>"$LOG" 2>&1; }

log "===== auto-update start on $(hostname) ====="
log "Kernel before: $(uname -r)"
rc=0

if command -v apt-get >/dev/null 2>&1; then
  log "Package manager: apt"
  APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  run apt-get update                     || rc=$?
  run apt-get "${APT_OPTS[@]}" upgrade        || rc=$?
  run apt-get "${APT_OPTS[@]}" dist-upgrade   || rc=$?
  run apt-get -y --purge autoremove      || rc=$?
  run apt-get -y autoclean               || true

elif command -v dnf >/dev/null 2>&1; then
  log "Package manager: dnf"
  run dnf -y upgrade --refresh           || rc=$?
  run dnf -y autoremove                  || rc=$?
  run dnf -y clean all                   || true

elif command -v yum >/dev/null 2>&1; then
  log "Package manager: yum"
  run yum -y update                      || rc=$?
  run yum -y autoremove                  || rc=$?
  run yum clean all                      || true

elif command -v pacman >/dev/null 2>&1; then
  log "Package manager: pacman"
  # Arch only supports full-system upgrades; partial upgrades are unsupported.
  run pacman -Syu --noconfirm            || rc=$?
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  if [ -n "$orphans" ]; then
    # shellcheck disable=SC2086
    run pacman -Rns --noconfirm $orphans || rc=$?
  fi

elif command -v zypper >/dev/null 2>&1; then
  log "Package manager: zypper"
  run zypper --non-interactive refresh   || rc=$?
  if grep -qi tumbleweed /etc/os-release 2>/dev/null; then
    # Tumbleweed is rolling: dist-upgrade (dup) is the correct path.
    run zypper --non-interactive dist-upgrade || rc=$?
  else
    # Leap/SLE: 'update' is the safe choice; 'dup' can cross-grade a fixed release.
    run zypper --non-interactive update       || rc=$?
  fi

elif command -v apk >/dev/null 2>&1; then
  log "Package manager: apk (Alpine)"
  run apk update                         || rc=$?
  run apk upgrade --available            || rc=$?

else
  log "ERROR: no supported package manager found (apt/dnf/yum/pacman/zypper/apk)."
  rc=1
fi

# --- reboot-required notice (this script never reboots on its own) ---
if [ -f /var/run/reboot-required ] \
   || { command -v needs-restarting >/dev/null 2>&1 && ! needs-restarting -r >/dev/null 2>&1; }; then
  log "NOTE: a reboot is required to finish applying these updates."
fi

# --- prune old logs ---
# shellcheck disable=SC2012
ls -1t "$LOGDIR"/update-*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f

log "Kernel after:  $(uname -r)"
log "===== auto-update finished (exit $rc) ====="
exit $rc
