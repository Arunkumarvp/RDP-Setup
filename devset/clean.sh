#!/bin/bash
# ==============================================================================
# System Cleanup Script for Kali Linux
# Clears temp files, package caches, shared memory, and RAM/Swap cache.
# ==============================================================================

set -e

# --- Colors for logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# --- Must run as root ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[✗] This script must be run as root.${NC}"
   echo "Usage: sudo bash $0"
   exit 1
fi

echo "================================================================="
echo " KALI LINUX SYSTEM CLEANUP UTILITY"
echo "================================================================="

log_step "Cleaning APT Package Caches"
apt-get clean -y > /dev/null
log_info "Removed APT archives."
apt-get autoremove -y > /dev/null
log_info "Removed old and unused packages."

log_step "Cleaning Temporary Directories"
rm -rf /tmp/* /var/tmp/* /dev/shm/* /var/crash/*
log_info "Cleared /tmp, /var/tmp, crash reports, and shared memory (/dev/shm)."

log_step "Cleaning User Caches & Trash"
if [ -n "$SUDO_USER" ]; then
    log_info "Cleaning cache for user: $SUDO_USER"
    rm -rf "/home/$SUDO_USER/.cache/*"
    rm -rf "/home/$SUDO_USER/.local/share/Trash/*" 2>/dev/null || true
fi
rm -rf /root/.cache/*
rm -rf /root/.local/share/Trash/* 2>/dev/null || true
log_info "Cleaned user-level cache directories and Trash bins."

log_step "Cleaning Journald Logs"
journalctl --rotate > /dev/null
journalctl --vacuum-time=1d > /dev/null
log_info "Rotated and vacuumed system journal logs."

log_step "Clearing RAM Cache (PageCache, Dentries, Inodes)"
sync
echo 3 > /proc/sys/vm/drop_caches
log_info "System memory caches have been cleared."

log_step "Clearing Swap Space"
swapoff -a && swapon -a || log_warn "Swap is disabled or not enough free RAM."
log_info "Swap space has been refreshed."

echo ""
echo "================================================================="
echo " SUCCESS: SYSTEM CLEANUP COMPLETE"
echo "================================================================="
echo "Your system should now be a bit cleaner and more responsive."
echo ""