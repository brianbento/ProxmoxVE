#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: dave-yap
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://zitadel.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt install -y ca-certificates
msg_ok "Installed Dependecies"

PG_VERSION="17" setup_postgresql

msg_info "Installing Postgresql"
DB_NAME="zitadel"
DB_USER="zitadel"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
DB_ADMIN_USER="root"
DB_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
systemctl start postgresql
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE USER $DB_ADMIN_USER WITH PASSWORD '$DB_ADMIN_PASS' SUPERUSER;"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_ADMIN_USER;"
{
  echo "Application Credentials"
  echo "DB_NAME: $DB_NAME"
  echo "DB_USER: $DB_USER"
  echo "DB_PASS: $DB_PASS"
  echo "DB_ADMIN_USER: $DB_ADMIN_USER"
  echo "DB_ADMIN_PASS: $DB_ADMIN_PASS"
} >>~/zitadel.creds
msg_ok "Installed PostgreSQL"

fetch_and_deploy_gh_release "zitadel" "zitadel/zitadel" "prebuild" "latest" "/usr/local/bin" "zitadel-linux-amd64.tar.gz"

msg_info "Configuring Domain Settings"
# Use environment variables passed from CT script
EXTERNAL_DOMAIN="${ZITADEL_DOMAIN:-auto}"
EXTERNAL_PORT="${ZITADEL_PORT:-443}"
EXTERNAL_SECURE="${ZITADEL_SECURE:-true}"

# If domain is "auto", use container IP
if [[ "$EXTERNAL_DOMAIN" == "auto" ]]; then
  EXTERNAL_DOMAIN=$(ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
fi
msg_ok "Domain configured: $EXTERNAL_DOMAIN:$EXTERNAL_PORT (SSL: $EXTERNAL_SECURE)"

msg_info "Setting up Zitadel Environments"
mkdir -p /opt/zitadel
echo "/opt/zitadel/config.yaml" >"/opt/zitadel/.config"
head -c 32 < <(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9') >"/opt/zitadel/.masterkey"
{
  echo "Config location: $(cat "/opt/zitadel/.config")"
  echo "Masterkey: $(cat "/opt/zitadel/.masterkey")"
  echo ""
  echo "Domain Configuration"
  echo "External Domain: $EXTERNAL_DOMAIN"
  echo "External Port: $EXTERNAL_PORT"
  echo "External Secure (SSL): $EXTERNAL_SECURE"
} >>~/zitadel.creds
cat <<EOF >/opt/zitadel/config.yaml
Port: 8080
ExternalPort: ${EXTERNAL_PORT}
ExternalDomain: ${EXTERNAL_DOMAIN}
ExternalSecure: ${EXTERNAL_SECURE}
TLS:
  Enabled: false
  KeyPath: ""
  Key: ""
  CertPath: ""
  Cert: ""

Database:
  postgres:
    Host: localhost
    Port: 5432
    Database: ${DB_NAME}
    User:
      Username: ${DB_USER}
      Password: ${DB_PASS}
      SSL:
        Mode: disable
        RootCert: ""
        Cert: ""
        Key: ""
    Admin:
      Username: ${DB_ADMIN_USER}
      Password: ${DB_ADMIN_PASS}
      SSL:
        Mode: disable
        RootCert: ""
        Cert: ""
        Key: ""
DefaultInstance:
  Features:
    LoginV2:
      Required: false
EOF
msg_ok "Installed Zitadel Enviroments"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/zitadel.service
[Unit]
Description=ZITADEL Identiy Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=zitadel
Group=zitadel
ExecStart=/usr/local/bin/zitadel start --masterkeyFile "/opt/zitadel/.masterkey" --config "/opt/zitadel/config.yaml"
Restart=always
RestartSec=5
TimeoutStartSec=0

# Security Hardening options
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now zitadel
msg_ok "Created Services"

msg_info "Zitadel initial setup"
zitadel start-from-init --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml &>/dev/null &
sleep 60
kill "$(lsof -i | awk '/zitadel/ {print $2}' | head -n1)"
useradd zitadel
msg_ok "Zitadel initialized"

msg_info "Starting Zitadel service"
systemctl stop -q zitadel
$STD zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml
systemctl restart -q zitadel
msg_ok "Zitadel service started"

msg_info "Create zitadel-rerun.sh"
cat <<EOF >~/zitadel-rerun.sh
systemctl stop zitadel
timeout --kill-after=5s 15s zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml
systemctl restart zitadel
EOF
msg_ok "Bash script for rerunning Zitadel after changing Zitadel config.yaml"

msg_info "Installing Node.js for Login V2"
$STD apt-get install -y curl
$STD curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Extracting and setting up Login V2 app"
mkdir -p /usr/local/share/zitadel
LATEST_RELEASE=$(curl -s https://api.github.com/repos/zitadel/zitadel/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -fsSL "https://github.com/zitadel/zitadel/releases/download/${LATEST_RELEASE}/zitadel-login.tar.gz" -o /tmp/zitadel-login.tar.gz
$STD tar -xzf /tmp/zitadel-login.tar.gz -C /usr/local/share/zitadel
rm /tmp/zitadel-login.tar.gz
chown -R zitadel:zitadel /usr/local/share/zitadel
msg_ok "Set up Login V2 app"

msg_info "Creating Login V2 systemd service"
cat <<EOF >/etc/systemd/system/zitadel-login.service
[Unit]
Description=ZITADEL Login V2
Documentation=https://zitadel.com/docs/
After=network-online.target zitadel.service
Wants=zitadel.service

[Service]
User=zitadel
Group=zitadel
AmbientCapabilities=CAP_NET_BIND_SERVICE
Type=simple
ExecStart=/usr/bin/node /usr/local/share/zitadel/apps/login/server.js
Restart=always
RestartSec=5

# Security hardening
ProtectSystem=strict
PrivateTmp=true
ProtectHome=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
ReadWritePaths=/usr/local/share/zitadel

# Environment variables
Environment="ZITADEL_API_URL=http://127.0.0.1:8080"
Environment="NEXT_PUBLIC_BASE_PATH=/ui/v2/login"
Environment="PORT=3000"
Environment="CUSTOM_REQUEST_HEADERS=Host:${EXTERNAL_DOMAIN}"
# Note: ZITADEL_SERVICE_USER_TOKEN can be added if needed for additional security

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q zitadel-login
systemctl start -q zitadel-login
msg_ok "Created and started Login V2 service"

msg_info "Creating Nginx Proxy Manager configuration guide"
CONTAINER_IP=$(ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
cat <<EOF >~/nginx-proxy-manager-setup.md
# Nginx Proxy Manager Configuration for ZITADEL

## Current Configuration

Your ZITADEL instance is configured with:
- External Domain: ${EXTERNAL_DOMAIN}
- External Port: ${EXTERNAL_PORT}
- SSL Enabled: ${EXTERNAL_SECURE}
- Container IP: ${CONTAINER_IP}

## Important Notes

This configuration is based on the solution provided in:
https://github.com/zitadel/zitadel/issues/10526#issuecomment-3679937250

ZITADEL v4+ requires a separate Login V2 service (Next.js app) to handle the
login UI. This guide shows how to configure Nginx Proxy Manager to route
traffic appropriately between the main ZITADEL API and the Login V2 service.

## Prerequisites
- Nginx Proxy Manager installed and accessible
- Domain name pointing to your Nginx Proxy Manager instance

## Setup Instructions

### 1. Create Proxy Host for ZITADEL Main Service

In Nginx Proxy Manager:
1. Go to "Proxy Hosts" and click "Add Proxy Host"

2. **Details Tab:**
   - Domain Names: ${EXTERNAL_DOMAIN}
   - Scheme: http
   - Forward Hostname/IP: ${CONTAINER_IP}
   - Forward Port: 8080
   - ✓ Cache Assets
   - ✓ Block Common Exploits
   - ✓ Websockets Support

3. **Custom Locations Tab:**
   Click "Add Location" and configure:
   - Define Location: \`/ui/v2/login\`
   - Scheme: http
   - Forward Hostname/IP: ${CONTAINER_IP}
   - Forward Port: 3000
   - (Optional) In "Advanced" for this location, add buffer settings:
     \`\`\`nginx
     proxy_buffer_size 128k;
     proxy_buffers 4 256k;
     proxy_busy_buffers_size 256k;
     \`\`\`

4. **SSL Tab:**
   - ✓ Force SSL (if using SSL)
   - ✓ HTTP/2 Support
   - ✓ HSTS Enabled
   - Select or request SSL certificate

5. **(Optional) Advanced Tab:**
   If you need additional buffer settings for the main location:
   \`\`\`nginx
   proxy_buffer_size 128k;
   proxy_buffers 4 256k;
   proxy_busy_buffers_size 256k;
   \`\`\`

6. Save the configuration

**Note:** Using Custom Locations is cleaner than adding raw Nginx config in the 
Advanced tab. NPM will automatically handle the proxy headers and routing for you.

### 2. Update ZITADEL Configuration (if needed)

Your configuration is already set in /opt/zitadel/config.yaml:

\`\`\`yaml
ExternalDomain: ${EXTERNAL_DOMAIN}
ExternalPort: ${EXTERNAL_PORT}
ExternalSecure: ${EXTERNAL_SECURE}
\`\`\`

If you need to change it, edit the file and run:
\`\`\`bash
bash ~/zitadel-rerun.sh
systemctl restart zitadel-login
\`\`\`

### 3. Update Login V2 Service (if needed)

Your Login V2 service is already configured with:
\`\`\`
Environment="CUSTOM_REQUEST_HEADERS=Host:${EXTERNAL_DOMAIN}"
\`\`\`

If you need to change it, edit /etc/systemd/system/zitadel-login.service and restart:
\`\`\`bash
systemctl daemon-reload
systemctl restart zitadel-login
\`\`\`

## Testing

1. Navigate to: $(if [[ "$EXTERNAL_SECURE" == "true" ]]; then echo "https"; else echo "http"; fi)://${EXTERNAL_DOMAIN}$(if [[ "$EXTERNAL_PORT" != "443" && "$EXTERNAL_PORT" != "80" ]]; then echo ":${EXTERNAL_PORT}"; fi)
2. You should be able to access the ZITADEL console
3. Login should redirect to /ui/v2/login and work correctly

## Troubleshooting

- Check ZITADEL logs: \`journalctl -u zitadel -f\`
- Check Login V2 logs: \`journalctl -u zitadel-login -f\`
- Verify services are running: \`systemctl status zitadel zitadel-login\`

## Notes

- The Login V2 service runs on port 3000
- ZITADEL API runs on port 8080
- Nginx Proxy Manager routes /ui/v2/login to the Login V2 service
- All other paths go to the main ZITADEL service

## Optional: Service User Token

For additional security, you can create a service user token in ZITADEL:

1. Log into ZITADEL console
2. Create a service user with appropriate permissions
3. Generate a Personal Access Token (PAT)
4. Add to /etc/systemd/system/zitadel-login.service:
   \`\`\`
   Environment="ZITADEL_SERVICE_USER_TOKEN=<your-token-here>"
   \`\`\`
5. Reload and restart: \`systemctl daemon-reload && systemctl restart zitadel-login\`

## Multiple Instances

If you need multiple ZITADEL instances with different domains, you can:

1. Create additional login service instances using systemd templates:
   - Copy service to: /etc/systemd/system/zitadel-login@.service
   - Create environment files: /etc/default/zitadel-login-domain1
   - Start with: \`systemctl start zitadel-login@domain1\`

2. Each instance should use a different PORT and CUSTOM_REQUEST_HEADERS

See the GitHub issue for more details on multi-instance setup.
EOF
{
  echo ""
  echo "Nginx Proxy Manager Setup Guide: ~/nginx-proxy-manager-setup.md"
} >>~/zitadel.creds
msg_ok "Created Nginx Proxy Manager configuration guide"

motd_ssh
customize
cleanup_lxc
