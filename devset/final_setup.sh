#!/bin/bash

# ==============================================================================
# SECURE BROWSER-BASED REMOTE GUI SETUP (CLOUDFLARE + DUCKDNS)
# ==============================================================================

set -e

# Config
TOKEN="eyJhIjoiYTQ4MTlmODU4MzFlZDJkMjhmZGNkZmY2ZGI5ZDMyN2EiLCJ0IjoiYmMxYzkzNDgtYjcwYy00ZTVjLWJiZDgtZjQ3ZDBmM2Q2Yzg2IiwicyI6IlpEbGlObVJrWXpjdE1XRXlNeTAwTnpSbExXSTBNbVF0TkRJME1HUXdaRGN5TUdZeCJ9"
DUCK_DOMAIN="devkali-slave"
DUCK_TOKEN="18acbb18-228f-496c-ab55-f86d51312ae5"

echo "[*] Cleaning up old services..."
systemctl stop cloudflared 2>/dev/null || true
cloudflared service uninstall 2>/dev/null || true
rm -rf /etc/cloudflared/config.yml ~/.cloudflared/*.json

echo "[*] Installing Cloudflared binary..."
wget -q -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/cloudflared

echo "[*] Installing GUI dependencies (XRDP + XFCE4)..."
apt update
apt install -y xrdp xfce4 xfce4-goodies
echo "xfce4-session" > /home/dev/.xsession
chown dev:dev /home/dev/.xsession
systemctl enable --now xrdp

echo "[*] Installing Cloudflare Tunnel Service..."
cloudflared service install "$TOKEN"

echo "[*] Applying Home Wi-Fi Reliability Fix (HTTP2)..."
sed -i 's|tunnel run|tunnel run --protocol http2|' /etc/systemd/system/cloudflared.service
systemctl daemon-reload
systemctl restart cloudflared

echo "[*] Setting up DuckDNS Updater..."
mkdir -p /home/dev/scripts
cat <<EOF > /home/dev/scripts/update_duckdns.sh
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$DUCK_TOKEN&ip=" | curl -K -
EOF
chmod +x /home/dev/scripts/update_duckdns.sh
chown -R dev:dev /home/dev/scripts
(crontab -u dev -l 2>/dev/null; echo "*/5 * * * * /home/dev/scripts/update_duckdns.sh") | crontab -u dev -

echo "================================================================="
echo " SUCCESS: SETUP COMPLETE"
echo "================================================================="
echo "1. Status: $(systemctl is-active cloudflared)"
echo "2. Access your desktop at: https://remote.devkali-slave.duckdns.org"
echo "3. Ensure Cloudflare Dashboard Dashboard has Public Hostname mapped."
echo "================================================================="
