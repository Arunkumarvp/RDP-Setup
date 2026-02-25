#!/bin/bash
# ============================================================
# Apache Guacamole Docker Setup Script
# Access your Kali desktop from ANY browser — no client needed!
# URL: http://<your-duckdns>:8080/guacamole
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

# ── Configuration ─────────────────────────────────────────
GUAC_DATA_DIR="/opt/guacamole"
GUAC_PORT=8080
GUAC_VERSION="1.5.5"

# PostgreSQL credentials (used internally by Guacamole)
POSTGRES_DB="guacamole_db"
POSTGRES_USER="guacamole_user"
POSTGRES_PASS="Gu4c4m0le_S3cur3!"

# Guacamole admin credentials (change after first login!)
GUAC_ADMIN_USER="admin"
GUAC_ADMIN_PASS="Admin@Kali2025!"

DUCKDNS_DOMAIN="devkali-slave.duckdns.org"

log_step "Apache Guacamole Docker Setup"
log_info "Guacamole Port : $GUAC_PORT"
log_info "Data Dir       : $GUAC_DATA_DIR"
log_info "Access URL     : http://$DUCKDNS_DOMAIN:$GUAC_PORT/guacamole"

# ── Create directories ────────────────────────────────────
log_step "Creating Directories"
mkdir -p "$GUAC_DATA_DIR"/{init,drive,record}
chmod -R 777 "$GUAC_DATA_DIR"

# ── Install Docker Compose if missing ──────────────────
log_step "Checking Docker Compose"
if ! command -v docker-compose &>/dev/null; then
    log_info "Installing docker-compose..."
    apt-get install -y docker-compose
fi
DC_CMD="docker-compose"
log_info "Docker Compose ready: $($DC_CMD --version | head -1)"

# ── Install xrdp for RDP access to Kali desktop ──────────
log_step "Installing XRDP (RDP server for Kali desktop)"
apt-get install -y xrdp xorgxrdp
# Allow xrdp to access X session
adduser xrdp ssl-cert 2>/dev/null || true

# Make sure xrdp starts on boot
systemctl enable xrdp
systemctl restart xrdp
log_info "XRDP running on port 3389"

# ── Install VNC server as alternative ────────────────────
log_step "Installing TigerVNC (optional VNC access)"
apt-get install -y tigervnc-standalone-server tigervnc-common || true
log_info "VNC installed."

# ── Generate Guacamole DB init SQL ───────────────────────
log_step "Generating Guacamole DB Init Script"
# Pull the init SQL from the guacamole image
docker run --rm guacamole/guacamole:${GUAC_VERSION} \
    /opt/guacamole/bin/initdb.sh --postgresql > "$GUAC_DATA_DIR/init/initdb.sql" 2>/dev/null || \
docker run --rm guacamole/guacamole \
    /opt/guacamole/bin/initdb.sh --postgresql > "$GUAC_DATA_DIR/init/initdb.sql"
log_info "DB init SQL generated."

# ── Write Docker Compose file ─────────────────────────────
log_step "Writing Docker Compose Configuration"
cat > "$GUAC_DATA_DIR/docker-compose.yml" << 'DOCKEREOF'
version: "3.9"

networks:
  guacnet:
    driver: bridge

services:

  # ── PostgreSQL Database ─────────────────────────────────
  guac-postgres:
    image: postgres:15-alpine
    container_name: guac-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB:       ${POSTGRES_DB}
      POSTGRES_USER:     ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
    volumes:
      - ./init:/docker-entrypoint-initdb.d:ro
      - postgres_data:/var/lib/postgresql/data
    networks:
      - guacnet

  # ── Guacamole Daemon (guacd) ────────────────────────────
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped
    volumes:
      - ./drive:/drive
      - ./record:/record
    networks:
      - guacnet

  # ── Guacamole Web App ───────────────────────────────────
  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      - guac-postgres
      - guacd
    environment:
      GUACD_HOSTNAME:    guacd
      POSTGRES_HOSTNAME: guac-postgres
      POSTGRES_DATABASE: ${POSTGRES_DB}
      POSTGRES_USER:     ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
    ports:
      - "8080:8080"
    networks:
      - guacnet

volumes:
  postgres_data:
DOCKEREOF

# ── Write .env file ───────────────────────────────────────
cat > "$GUAC_DATA_DIR/.env" << EOF
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASS=$POSTGRES_PASS
EOF
chmod 600 "$GUAC_DATA_DIR/.env"
log_info "Docker Compose file written."

# ── Start Guacamole stack ─────────────────────────────────
log_step "Starting Guacamole Stack"
cd "$GUAC_DATA_DIR"
$DC_CMD down 2>/dev/null || true
$DC_CMD up -d
log_info "Guacamole stack starting..."

sleep 10

# ── Verify containers are running ────────────────────────
log_step "Verifying Containers"
docker ps | grep -E "guac|postgres" | while read -r line; do
    log_info "$line"
done

# ── Open firewall ─────────────────────────────────────────
log_step "Opening Firewall Ports"
if command -v ufw &>/dev/null; then
    ufw allow 8080/tcp
    ufw allow 3389/tcp
    log_info "UFW: Opened ports 8080 (Guacamole) and 3389 (RDP)"
fi

# ── Add Guacamole connection via API ──────────────────────
# Wait for Guacamole to fully start
log_step "Waiting for Guacamole to Initialize (30s)"
sleep 30

log_step "Login Instructions"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          GUACAMOLE IS READY!                             ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  URL:      http://$DUCKDNS_DOMAIN:8080/guacamole  ║${NC}"
echo -e "${GREEN}║  Username: guacadmin                                     ║${NC}"
echo -e "${GREEN}║  Password: guacadmin  (CHANGE THIS IMMEDIATELY!)        ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  After login, add a connection:                          ║${NC}"
echo -e "${GREEN}║  → Settings → Connections → New Connection               ║${NC}"
echo -e "${GREEN}║  → Protocol: RDP                                         ║${NC}"
echo -e "${GREEN}║  → Hostname: 172.17.0.1  (Docker host IP)                ║${NC}"
echo -e "${GREEN}║  → Port: 3389                                            ║${NC}"
echo -e "${GREEN}║  → Username: dev  (your Kali username)                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
