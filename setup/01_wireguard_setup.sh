#!/bin/bash
# ============================================================
# WireGuard Server Setup Script
# System: Kali Linux Rolling
# Purpose: Set up WireGuard VPN server so you can connect
#          to your home system from anywhere securely
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# ── Must run as root ──────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Run this script as root: sudo bash $0"
    exit 1
fi

# ── Configuration ─────────────────────────────────────────
WG_INTERFACE="wg0"
WG_PORT=51820
WG_NETWORK="10.8.0.0/24"
WG_SERVER_IP="10.8.0.1"
WG_CLIENT_IP="10.8.0.2"
WG_DIR="/etc/wireguard"
SERVER_PUBLIC_IP=$(curl -s -4 --max-time 5 ifconfig.me)
DUCKDNS_DOMAIN="devkali-slave.duckdns.org"

log_step "WireGuard Server Setup"
log_info "Server Public IP : $SERVER_PUBLIC_IP"
log_info "DuckDNS Domain   : $DUCKDNS_DOMAIN"
log_info "WireGuard Port   : $WG_PORT"
log_info "VPN Network      : $WG_NETWORK"

# ── Install WireGuard kernel module if needed ─────────────
log_step "Installing WireGuard"
apt-get update -qq
apt-get install -y wireguard wireguard-tools qrencode iptables resolvconf
log_info "WireGuard installed."

# ── Enable IP Forwarding ──────────────────────────────────
log_step "Enabling IP Forwarding"
# Persist across reboots
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi
sysctl -p /etc/sysctl.conf
log_info "IP forwarding enabled."

# ── Generate Server Keys ──────────────────────────────────
log_step "Generating Server Keys"
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

if [[ -f "$WG_DIR/server_private.key" ]]; then
    log_warn "Server keys already exist. Using existing keys."
else
    wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"
    log_info "Server keys generated."
fi

SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server_private.key")
SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")

# ── Generate Client Keys ──────────────────────────────────
log_step "Generating Client Keys"
if [[ -f "$WG_DIR/client_private.key" ]]; then
    log_warn "Client keys already exist. Using existing keys."
else
    wg genkey | tee "$WG_DIR/client_private.key" | wg pubkey > "$WG_DIR/client_public.key"
    wg genpsk > "$WG_DIR/client_preshared.key"
    chmod 600 "$WG_DIR/client_private.key" "$WG_DIR/client_preshared.key"
    log_info "Client keys generated."
fi

CLIENT_PRIVATE_KEY=$(cat "$WG_DIR/client_private.key")
CLIENT_PUBLIC_KEY=$(cat "$WG_DIR/client_public.key")
CLIENT_PRESHARED_KEY=$(cat "$WG_DIR/client_preshared.key")

# ── Detect main network interface ────────────────────────
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
log_info "Main network interface: $MAIN_IFACE"

# ── Create Server Config ──────────────────────────────────
log_step "Creating WireGuard Server Config"
cat > "$WG_DIR/$WG_INTERFACE.conf" << EOF
[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
DNS = 1.1.1.1, 8.8.8.8

# NAT rules: route VPN traffic to internet
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_IFACE -j MASQUERADE

# ── Client: Phone / Laptop ────────────────────────────────
[Peer]
PublicKey  = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
AllowedIPs = $WG_CLIENT_IP/32
EOF
chmod 600 "$WG_DIR/$WG_INTERFACE.conf"
log_info "Server config created at $WG_DIR/$WG_INTERFACE.conf"

# ── Create Client Config ──────────────────────────────────
log_step "Creating Client Config"
CLIENT_CONF="$WG_DIR/client.conf"
cat > "$CLIENT_CONF" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address    = $WG_CLIENT_IP/32
DNS        = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey    = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
Endpoint     = $DUCKDNS_DOMAIN:$WG_PORT
AllowedIPs   = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "$CLIENT_CONF"
log_info "Client config created at $CLIENT_CONF"

# ── Enable & Start WireGuard ──────────────────────────────
log_step "Starting WireGuard Service"
systemctl enable wg-quick@$WG_INTERFACE
systemctl restart wg-quick@$WG_INTERFACE
sleep 2

if systemctl is-active --quiet wg-quick@$WG_INTERFACE; then
    log_info "WireGuard is RUNNING! ✓"
else
    log_error "WireGuard failed to start. Check: journalctl -u wg-quick@$WG_INTERFACE"
fi

# ── Open firewall port ────────────────────────────────────
log_step "Opening Firewall Port"
if command -v ufw &>/dev/null; then
    ufw allow $WG_PORT/udp
    log_info "UFW: Allowed UDP $WG_PORT"
fi

# ── Show QR Code for mobile client ───────────────────────
log_step "Client QR Code (scan with WireGuard mobile app)"
echo ""
qrencode -t ansiutf8 < "$CLIENT_CONF"
echo ""

# ── Print Summary ─────────────────────────────────────────
log_step "Setup Complete!"
echo ""
echo -e "${GREEN}Server Public Key:${NC} $SERVER_PUBLIC_KEY"
echo -e "${GREEN}Client Config:${NC}    $CLIENT_CONF"
echo -e "${GREEN}WG Interface:${NC}     $WG_INTERFACE ($WG_SERVER_IP)"
echo -e "${GREEN}Listen Port:${NC}      UDP $WG_PORT"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Copy $CLIENT_CONF to your phone/laptop"
echo "  2. Import into WireGuard app"
echo "  3. Or scan the QR code above with WireGuard mobile app"
echo ""
echo -e "  WireGuard status: ${BLUE}sudo wg show${NC}"
echo ""
