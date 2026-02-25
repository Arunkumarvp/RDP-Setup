# Kali Linux Remote Access Architecture & Setup Guide

This document outlines the architecture, components, and step-by-step setup required to build a highly resilient, ISP-agnostic remote access solution for Kali Linux.

## 🎯 Objective
To establish a seamless, secure, web-based Remote Desktop (RDP) access to a physical Kali Linux machine that works from anywhere in the world on any device, even if the Internet Service Provider (ISP) uses strict Carrier-Grade NAT (CGNAT) or blocks all inbound ports.

It also enables "headless" boots where turning on the computer automatically connects the internet, starts all services, and leaves the physical screen securely locked and turned off.

---

## 🏗️ Architecture Overview

The system relies on a chain of services working together to bypass network restrictions and provide access.

1. **Auto-Login & Display Manager (`lightdm.conf`)**: Automatically logs into the Kali system on physical boot. This ensures Wi-Fi/Ethernet connects, user-specific config loads, and display servers start. 
2. **Auto-Lock (`xflock4` & `xset dpms force off`)**: Immediately locks the physical session and turns off the monitor once autologin finishes. A custom GUI prompt asks the user whether to turn off remote services if a physical user is present.
3. **XRDP Server**: Captures the Kali XFCE desktop environment and serves it over the RDP protocol locally.
4. **Apache Guacamole (Dockerized)**: Plugs into the local XRDP server and translates the RDP protocol into HTML5, making the desktop accessible directly within standard web browsers.
5. **Serveo SSH Reverse Tunnel**: Since ISPs frequently block inbound port forwarding (e.g., port 8080 or 51820), an outbound reverse SSH tunnel connects Kali to `serveo.net`, assigning a persistent public HTTPS URL (e.g., `https://guac-devkali.serveousercontent.com`).
6. **DuckDNS**: (Optional Backup/VPN path) Continuously updates the system's public IP address in case direct Port Forwarding or WireGuard is available.
7. **WireGuard VPN**: (Optional Backup path) Sets up an encrypted tunnel to the network for CLI access if firewall rules allow.

---

## 📂 Project Structure

All scripts are modular and reside in a `setup/` directory.

- `install_all.sh`: The master orchestrator script. Runs all subsequent scripts in the correct order.
- `01_wireguard_setup.sh`: Installs `wireguard-tools`, generates keys, configures `wg0`, and manages routing configs.
- `02_guacamole_setup.sh`: Installs `docker-compose` and configures the Apache Guacamole stack (`guacd`, `guac-postgres`, `guacamole`) to proxy the desktop.
- `03_duckdns_setup.sh`: Sets up a systemd timer/cron to hit DuckDNS APIs and update the home IP every 5 minutes.
- `04_autostart_setup.sh`: Configures core services to run automatically on system boot.
- `05_serveo_tunnel.sh`: Generates persistent SSH keys and sets up the auto-reconnecting systemd service linking port 8080 to the web.

---

## 🛠️ Step-by-Step Setup Guide

### Phase 1: Preparation
1. Clone or copy the setup directory onto the Kali machine.
2. Obtain a [DuckDNS token](https://www.duckdns.org/) (useful for direct IPs, even if using the tunnel).

### Phase 2: Master Installation
Run the master installation script to configure Docker, PostgreSQL, WireGuard APIs, and Guacamole. You must supply your DuckDNS token.

```bash
sudo bash install_all.sh 'your-duckdns-token-here'
```
*Note: Due to how `sudo` strips environment variables, passing the token as an argument directly to the orchestrator script is required.*

### Phase 3: Bypassing the ISP (Serveo Tunnel)
If the local router or ISP blocks HTTP(80) or Proxy(8080) ports, execute the Serveo Tunnel configuration script:

```bash
sudo bash 05_serveo_tunnel.sh
```
This drops a permanent background service (`serveo-tunnel.service`) tracking `localhost:8080`.
**Important**: Register the generated SSH key (`/etc/serveo/tunnel_key.pub`) on the Serveo Console to claim a custom persistent domain name.

### Phase 4: Configure the Display & Boot
1. Edit `/etc/lightdm/lightdm.conf` to enable autologin.
   ```ini
   autologin-user=YOUR_USERNAME
   autologin-user-timeout=0
   ```
2. Inject a custom `ask_rdp.sh` GUI prompt utilizing `Zenity` into the user's `autostart` configuration. This will prompt the user on boot. If left untouched, it executes `sleep 2 && xflock4 && sleep 2 && xset dpms force off`.
3. In `/home/YOUR_USERNAME/.xsession`, specify the desktop environment so XRDP can attach without crashing. For Kali:
   ```bash
   unset DBUS_SESSION_BUS_ADDRESS
   unset XDG_RUNTIME_DIR
   export XDG_CURRENT_DESKTOP=XFCE
   exec /usr/bin/startxfce4
   ```

### Phase 5: Hooking Guacamole to XRDP
1. Access the newly created Serveo Tunnel link (or local `http://IP:8080/guacamole`).
2. Log in using the admin credentials specified in Guacamole's Postgres environment setup (`Guacamole_S3cur3`).
3. Create a New Connection -> Protocol `RDP`.
4. Define parameters:
   - Hostname: `172.17.0.1` (Docker bridge traversing back to host Machine XRDP)
   - Port: `3389`
   - Ignore Cert: True
   - Resize Method: `Display-update` (for dynamic browser-resizing capability)

---

## 🚨 Troubleshooting & Key "Gotchas"

1. **Guacamole PostgreSQL Empty String Error**: 
   When writing Guacamole `docker-compose.yml`, the environment variables provided to the `guacamole` container relating to the database must use the syntax `POSTGRESQL_*` (with the QL affix) rather than `POSTGRES_*`. Failure to do so throws a `SCRAM-based Authentication empty password` exception.
2. **Container Networking to Host**:
   When mapping Guacamole from within Docker to the host machines XRDP server, do not use `localhost`. Instead, use the Docker gateway `172.17.0.1` inside the connection settings.
3. **CGNAT/ISP Blocks**:
   Indian Fiber networks routinely deploy CGNAT. The only reliable bridge to host applications without utilizing corporate SD-WAN setups like `Cloudflared` (sometimes blocked or overkill for raw RDP latency requirements) or paying for cloud VPS is a Raw Reverse SSH Tunnel mapped dynamically to `serveo.net`.

## 🔄 Daily Workflow
1. The Remote computer powers on.
2. The User remotely navigates to `https://[fixed-subdomain].serveousercontent.com/guacamole`.
3. Browser auto-scales the remote workspace, maintaining low RDP latency without additional local clients.
