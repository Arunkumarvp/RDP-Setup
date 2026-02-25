#!/bin/bash
# ============================================================
# Power-On Auto-Start Setup
# When you press the power button (or system boots), all
# remote access services start automatically:
#   - WireGuard VPN
#   - Apache Guacamole (Docker)
#   - DuckDNS IP updater
#   - XRDP (RDP server)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Run as root: sudo bash $0"
    exit 1
fi

log_step "Setting Up Auto-Start on Boot"

# ── Master startup script ─────────────────────────────────
cat > /usr/local/bin/remote-access-start.sh << 'STARTUP'
#!/bin/bash
# Remote Access Master Startup Script
# Runs at boot to ensure all remote access services are up

LOG="/var/log/remote-access-startup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting remote access services..." >> "$LOG"

# Wait for network to be fully up
for i in {1..30}; do
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        echo "[$TIMESTAMP] Network ready after ${i}s" >> "$LOG"
        break
    fi
    sleep 1
done

# 1. Update DuckDNS IP
if [[ -f /usr/local/bin/duckdns-update.sh ]]; then
    bash /usr/local/bin/duckdns-update.sh
    echo "[$TIMESTAMP] DuckDNS updated" >> "$LOG"
fi

# 2. Start WireGuard
if systemctl list-unit-files | grep -q "wg-quick@wg0"; then
    systemctl start wg-quick@wg0 2>/dev/null || true
    echo "[$TIMESTAMP] WireGuard started" >> "$LOG"
fi

# 3. Start XRDP
systemctl start xrdp 2>/dev/null || true
echo "[$TIMESTAMP] XRDP started" >> "$LOG"

# 4. Start Guacamole via Docker Compose
if [[ -f /opt/guacamole/docker-compose.yml ]]; then
    cd /opt/guacamole
    docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || true
    echo "[$TIMESTAMP] Guacamole started" >> "$LOG"
fi

echo "[$TIMESTAMP] All remote access services started." >> "$LOG"
STARTUP

chmod +x /usr/local/bin/remote-access-start.sh
log_info "Master startup script created."

# ── Create systemd service ────────────────────────────────
log_step "Creating Systemd Auto-Start Service"
cat > /etc/systemd/system/remote-access.service << 'EOF'
[Unit]
Description=Remote Access Services (WireGuard + Guacamole + XRDP + DuckDNS)
After=network-online.target docker.service
Wants=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/remote-access-start.sh
ExecStop=/usr/local/bin/remote-access-stop.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

# ── Create stop script ────────────────────────────────────
cat > /usr/local/bin/remote-access-stop.sh << 'STOP'
#!/bin/bash
# Graceful shutdown of all remote access services
echo "[$(date)] Stopping remote access services..."
cd /opt/guacamole && docker compose down 2>/dev/null || true
systemctl stop xrdp 2>/dev/null || true
systemctl stop wg-quick@wg0 2>/dev/null || true
echo "[$(date)] All remote access services stopped."
STOP
chmod +x /usr/local/bin/remote-access-stop.sh

# ── Enable services ───────────────────────────────────────
log_step "Enabling All Services"
systemctl daemon-reload

# WireGuard
systemctl enable wg-quick@wg0 2>/dev/null || log_warn "WireGuard not configured yet (run 01_wireguard_setup.sh first)"

# XRDP
systemctl enable xrdp 2>/dev/null || log_warn "XRDP not installed yet"

# Docker
systemctl enable docker

# Master service
systemctl enable remote-access.service
log_info "remote-access.service enabled on boot"

# ── Handle suspend/wake (laptop lid open) ────────────────
log_step "Setting Up Wake-from-Sleep Auto-Start"
mkdir -p /etc/systemd/system-sleep/
cat > /etc/systemd/system-sleep/remote-access-wake.sh << 'WAKE'
#!/bin/bash
# Called when system wakes from sleep
case "$1" in
    post)
        echo "[$(date)] System woke from sleep, restarting remote access..."
        systemctl start remote-access.service
        ;;
esac
WAKE
chmod +x /etc/systemd/system-sleep/remote-access-wake.sh
log_info "Wake-from-sleep handler installed."

# ── Show current status ───────────────────────────────────
log_step "Current Service Status"
echo ""
systemctl is-enabled docker       && log_info "Docker:       ENABLED" || log_warn "Docker: not enabled"
systemctl is-enabled xrdp         && log_info "XRDP:         ENABLED" || log_warn "XRDP: not enabled"
systemctl is-enabled duckdns.timer && log_info "DuckDNS:      ENABLED" || log_warn "DuckDNS timer: not enabled"
systemctl is-enabled remote-access && log_info "RemoteAccess: ENABLED" || log_warn "RemoteAccess: not enabled"

echo ""
log_step "Auto-Start Setup Complete!"
echo ""
echo -e "${GREEN}✓ On every boot/power-on, these start automatically:${NC}"
echo "  1. DuckDNS IP update (so domain always points to your IP)"
echo "  2. WireGuard VPN server (UDP 51820)"
echo "  3. XRDP (TCP 3389 — desktop access)"
echo "  4. Apache Guacamole (TCP 8080 — browser access)"
echo ""
echo -e "${YELLOW}To start manually right now:${NC}"
echo -e "  sudo systemctl start remote-access.service"
echo ""
echo -e "${YELLOW}To check status:${NC}"
echo -e "  sudo systemctl status remote-access.service"
echo ""
