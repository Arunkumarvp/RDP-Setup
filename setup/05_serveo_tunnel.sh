#!/bin/bash
# ============================================================
# Serveo SSH Reverse Tunnel — Guacamole Public Access
# No Cloudflare. No VPS. No port forwarding needed.
# Works even when ISP blocks all inbound ports.
#
# Creates public HTTPS URL → forwards to Guacamole :8080
# Usage: sudo bash 05_serveo_tunnel.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0"; exit 1
fi

log_step "Setting Up Serveo SSH Reverse Tunnel"

# ── Generate a persistent SSH key for serveo ─────────────
SSH_KEY="/etc/serveo/tunnel_key"
mkdir -p /etc/serveo
if [[ ! -f "$SSH_KEY" ]]; then
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N "" -C "guacamole-tunnel"
    log_info "SSH key generated: $SSH_KEY"
else
    log_info "Using existing SSH key: $SSH_KEY"
fi

# ── Add serveo to known hosts (avoid interactive prompt) ──
if ! grep -q "serveo.net" /root/.ssh/known_hosts 2>/dev/null; then
    mkdir -p /root/.ssh
    ssh-keyscan -H serveo.net >> /root/.ssh/known_hosts 2>/dev/null
    log_info "Serveo.net added to known_hosts"
fi

# ── Create tunnel wrapper script ──────────────────────────
cat > /usr/local/bin/serveo-tunnel.sh << 'TUNNEL'
#!/bin/bash
# Persistent Serveo tunnel with auto-reconnect
LOG="/var/log/serveo-tunnel.log"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Starting tunnel to serveo.net..." >> "$LOG"

    # SSH tunnel: expose localhost:8080 as public HTTPS via serveo.net
    # using fixed custom domain 'guac-devkali'
    ssh -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=15 \
        -i /etc/serveo/tunnel_key \
        -R guac-devkali:80:localhost:8080 \
        serveo.net 2>&1 | tee -a "$LOG"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tunnel dropped. Reconnecting in 5s..." >> "$LOG"
    sleep 5
done
TUNNEL
chmod +x /usr/local/bin/serveo-tunnel.sh

# ── Create systemd service ────────────────────────────────
cat > /etc/systemd/system/serveo-tunnel.service << 'EOF'
[Unit]
Description=Serveo SSH Reverse Tunnel (Guacamole Public Access)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/serveo-tunnel.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable serveo-tunnel.service
systemctl restart serveo-tunnel.service

log_step "Waiting for tunnel to establish (15s)..."
sleep 15

# ── Read the assigned public URL from journal ─────────────
TUNNEL_URL=$(journalctl -u serveo-tunnel.service -n 50 --no-pager 2>/dev/null | grep -oE "https://[a-z0-9]+\.serveo\.net" | tail -1)

if [[ -z "$TUNNEL_URL" ]]; then
    TUNNEL_URL=$(journalctl -u serveo-tunnel.service -n 50 --no-pager 2>/dev/null | grep -oE "[a-z0-9]+\.serveo\.net" | tail -1)
    [[ -n "$TUNNEL_URL" ]] && TUNNEL_URL="https://$TUNNEL_URL"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          🎉 TUNNEL IS LIVE — ACCESS FROM ANYWHERE!           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
if [[ -n "$TUNNEL_URL" ]]; then
echo -e "${GREEN}║  PUBLIC URL: ${TUNNEL_URL}/guacamole${NC}"
else
echo -e "${GREEN}║  PUBLIC URL: Check with: sudo journalctl -u serveo-tunnel -n 20${NC}"
fi
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Username: guacadmin                                         ║${NC}"
echo -e "${GREEN}║  Password: guacadmin  (change after login!)                 ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Auto-starts on every boot — no router config needed!       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Live logs   : ${YELLOW}sudo journalctl -u serveo-tunnel -f${NC}"
echo -e "Tunnel URL  : ${YELLOW}sudo journalctl -u serveo-tunnel -n 30 | grep serveo.net${NC}"
echo ""
