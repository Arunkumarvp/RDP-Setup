#!/bin/bash
# ============================================================
# MASTER INSTALLER — Run This ONE Script
# Sets up everything: WireGuard + Guacamole + DuckDNS + Auto-start
#
# Usage (two options):
#   sudo bash install_all.sh 'your-duckdns-token'
#   sudo -E DUCKDNS_TOKEN='your-token' bash install_all.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     KALI REMOTE ACCESS — COMPLETE SETUP                      ║"
    echo "║     WireGuard VPN + Apache Guacamole + DuckDNS              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_banner

# ── Root check ────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Must run as root!"
    echo ""
    echo -e "  ${YELLOW}DUCKDNS_TOKEN='your-token' sudo bash $0${NC}"
    echo ""
    exit 1
fi

# ── DuckDNS token check ───────────────────────────────────
# Accept token as first argument OR from environment
if [[ -n "$1" ]]; then
    DUCKDNS_TOKEN="$1"
fi

if [[ -z "$DUCKDNS_TOKEN" ]] || [[ "$DUCKDNS_TOKEN" == "REPLACE_WITH_YOUR_TOKEN" ]]; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════╗${NC}"
    echo -e "${RED}║  DuckDNS Token Required!          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════╝${NC}"
    echo ""
    echo "  Run this script like:"
    echo ""
    echo -e "     ${YELLOW}sudo bash $0 'your-duckdns-token'${NC}"
    echo ""
    exit 1
fi

log_info "DuckDNS token found: ${DUCKDNS_TOKEN:0:8}..."

# Export token so sub-scripts can use it
export DUCKDNS_TOKEN

# ── Step 1: WireGuard ─────────────────────────────────────
log_step "Step 1/4 — WireGuard VPN Server"
bash "$SCRIPT_DIR/01_wireguard_setup.sh"

# ── Step 2: Guacamole ─────────────────────────────────────
log_step "Step 2/4 — Apache Guacamole"
bash "$SCRIPT_DIR/02_guacamole_setup.sh"

# ── Step 3: DuckDNS ───────────────────────────────────────
log_step "Step 3/4 — DuckDNS Auto-Updater"
bash "$SCRIPT_DIR/03_duckdns_setup.sh"

# ── Step 4: Auto-start on boot ────────────────────────────
log_step "Step 4/4 — Auto-Start on Boot"
bash "$SCRIPT_DIR/04_autostart_setup.sh"

# ── Final Summary ─────────────────────────────────────────
PUBLIC_IP=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")

echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              🎉  SETUP COMPLETE!  🎉                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  BROWSER ACCESS (Apache Guacamole):                         ║"
echo "║  → http://devkali-slave.duckdns.org:8080/guacamole  ║"
echo "║  → Username: guacadmin                                      ║"
echo "║  → Password: guacadmin  (CHANGE THIS!)                     ║"
echo "║                                                              ║"
echo "║  VPN ACCESS (WireGuard):                                    ║"
echo "║  → Endpoint: devkali-slave.duckdns.org:51820        ║"
echo "║  → Client config: /etc/wireguard/client.conf               ║"
echo "║  → QR code shown above (scan with WireGuard mobile app)    ║"
echo "║                                                              ║"
echo "║  HOW TO CONNECT FROM ANYWHERE:                              ║"
echo "║  Option A (Easy): Open browser →                           ║"
echo "║    devkali-slave.duckdns.org:8080/guacamole         ║"
echo "║  Option B (VPN): Connect WireGuard → then RDP/SSH          ║"
echo "║                                                              ║"
echo "║  ON POWER BUTTON PRESS → Everything starts automatically!  ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}Current Public IP:${NC} $PUBLIC_IP"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT NEXT STEPS:${NC}"
echo "  1. Note your router — open UDP port 51820 for WireGuard"
echo "  2. Open TCP port 8080 for Guacamole (or use Cloudflare tunnel)"
echo "  3. Log into Guacamole and CHANGE the default password!"
echo "  4. In Guacamole: Add RDP connection to 172.17.0.1:3389"
echo "     with your Kali username/password"
echo ""
echo -e "Wireguard status : ${CYAN}sudo wg show${NC}"
echo -e "Guacamole logs   : ${CYAN}docker logs guacamole -f${NC}"
echo -e "DuckDNS log      : ${CYAN}tail -f /var/log/duckdns.log${NC}"
echo -e "All services     : ${CYAN}sudo systemctl status remote-access${NC}"
echo ""
