#!/bin/bash
# ============================================================
# DuckDNS IP Update Script
# Updates devkali-slave.duckdns.org with your current
# public IP every 5 minutes via cron and systemd
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

# ── FILL IN YOUR DUCKDNS TOKEN HERE ──────────────────────
# Accept token as argument $1 or from env var DUCKDNS_TOKEN
if [[ -n "$1" ]]; then
    DUCKDNS_TOKEN="$1"
fi
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-REPLACE_WITH_YOUR_TOKEN}"
DUCKDNS_SUBDOMAIN="devkali-slave"  # just the subdomain, no .duckdns.org

# Validate token
if [[ "$DUCKDNS_TOKEN" == "REPLACE_WITH_YOUR_TOKEN" ]]; then
    echo ""
    echo -e "${RED}ERROR: You must set your DuckDNS token!${NC}"
    echo ""
    echo "  1. Go to: https://www.duckdns.org"
    echo "  2. Log in and copy your token"
    echo "  3. Run this script with your token:"
    echo ""
    echo -e "     ${YELLOW}DUCKDNS_TOKEN='your-token-here' sudo bash $0${NC}"
    echo ""
    exit 1
fi

log_step "DuckDNS Auto-Update Setup"
log_info "Domain   : ${DUCKDNS_SUBDOMAIN}.duckdns.org"
log_info "Token    : ${DUCKDNS_TOKEN:0:8}... (hidden)"

# ── Create the updater script ─────────────────────────────
UPDATER_SCRIPT="/usr/local/bin/duckdns-update.sh"

cat > "$UPDATER_SCRIPT" << SCRIPT
#!/bin/bash
# DuckDNS IP Update — runs every 5 minutes
DUCKDNS_TOKEN="$DUCKDNS_TOKEN"
DUCKDNS_SUBDOMAIN="$DUCKDNS_SUBDOMAIN"
LOG_FILE="/var/log/duckdns.log"

RESULT=\$(curl -s "https://www.duckdns.org/update?domains=\${DUCKDNS_SUBDOMAIN}&token=\${DUCKDNS_TOKEN}&ip=&ipv6=&verbose=true")
TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
PUBLIC_IP=\$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null)

echo "[\$TIMESTAMP] IP: \$PUBLIC_IP | Result: \$(echo \$RESULT | head -c 50)" >> "\$LOG_FILE"
SCRIPT

chmod +x "$UPDATER_SCRIPT"
log_info "Updater script created at $UPDATER_SCRIPT"

# ── Test it once now ──────────────────────────────────────
log_step "Testing DuckDNS Update Now"
bash "$UPDATER_SCRIPT"
CURRENT_IP=$(curl -s -4 --max-time 5 ifconfig.me)
DNS_RESULT=$(curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=&verbose=true")
log_info "Current IP  : $CURRENT_IP"
log_info "DuckDNS says: $(echo $DNS_RESULT | head -c 100)"

# ── Create systemd service ────────────────────────────────
log_step "Creating Systemd Service"
cat > /etc/systemd/system/duckdns.service << EOF
[Unit]
Description=DuckDNS IP Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$UPDATER_SCRIPT
StandardOutput=journal
StandardError=journal
EOF

# ── Create systemd timer (every 5 minutes) ────────────────
cat > /etc/systemd/system/duckdns.timer << EOF
[Unit]
Description=Run DuckDNS Update every 5 minutes
After=network-online.target

[Timer]
OnBootSec=30sec
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable duckdns.timer
systemctl start duckdns.timer
log_info "DuckDNS systemd timer enabled (runs every 5 minutes)"

# ── Also add to cron as backup ────────────────────────────
log_step "Adding Cron Backup"
CRON_LINE="*/5 * * * * $UPDATER_SCRIPT"
(crontab -l 2>/dev/null | grep -v duckdns-update; echo "$CRON_LINE") | crontab -
log_info "Cron job added as backup."

# ── Summary ───────────────────────────────────────────────
log_step "DuckDNS Setup Complete"
echo ""
echo -e "${GREEN}Domain    : devkali-slave.duckdns.org${NC}"
echo -e "${GREEN}Public IP : $CURRENT_IP${NC}"
echo -e "${GREEN}Update    : Every 5 minutes (systemd timer + cron)${NC}"
echo -e "${GREEN}Log file  : /var/log/duckdns.log${NC}"
echo ""
echo -e "Check status: ${YELLOW}systemctl status duckdns.timer${NC}"
echo -e "View logs   : ${YELLOW}tail -f /var/log/duckdns.log${NC}"
echo ""
