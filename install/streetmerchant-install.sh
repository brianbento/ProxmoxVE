#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jef/streetmerchant

# Load functions
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  git \
  sudo \
  make \
  mc \
  gpg
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js"
NODE_VERSION="18" setup_nodejs
msg_ok "Node.js installed"

msg_info "Installing Streetmerchant"
cd /opt
RELEASE=$(curl -fsSL https://api.github.com/repos/jef/streetmerchant/releases/latest | \
  grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')

$STD git clone --depth 1 --branch "v${RELEASE}" https://github.com/jef/streetmerchant.git
cd streetmerchant
$STD npm install --production
msg_ok "Installed Streetmerchant v${RELEASE}"

msg_info "Creating Configuration"
cat > /opt/streetmerchant/.env <<'EOF'
# Browser Configuration
BROWSER_TRUSTED=true
HEADLESS=true
OPEN_BROWSER=false

# Notification Settings
PAGE_TIMEOUT=30000
RESTART_TIME=0

# Store Configuration
# STORES=bestbuy,amazon,newegg

# Custom Options
# LOG_LEVEL=info
# SCREENSHOT=false
# SLACK_CHANNEL=
# DISCORD_WEBHOOK=
# TELEGRAM_ACCESS_TOKEN=
# TELEGRAM_CHAT_ID=
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_FROM_NUMBER=
# TWILIO_TO_NUMBER=

# Proxy Settings
# PROXY_PROTOCOL=http
# PROXY_ADDRESS=
# PROXY_PORT=
EOF
chown root:root /opt/streetmerchant/.env
chmod 600 /opt/streetmerchant/.env
msg_ok "Configuration created"

msg_info "Creating Systemd Service"
cat > /etc/systemd/system/streetmerchant.service <<'EOF'
[Unit]
Description=Streetmerchant Stock Checker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/streetmerchant
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=10
StandardOutput=append:/var/log/streetmerchant.log
StandardError=append:/var/log/streetmerchant.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now streetmerchant.service
msg_ok "Systemd service created and started"

msg_info "Creating Update Script"
cat > /usr/bin/update-streetmerchant <<'EOF'
#!/bin/bash
set -e

echo "Stopping Streetmerchant..."
systemctl stop streetmerchant

echo "Backing up configuration..."
cp /opt/streetmerchant/.env /tmp/.env.backup

echo "Fetching latest version..."
cd /opt/streetmerchant
git fetch --all
LATEST=$(git describe --tags $(git rev-list --tags --max-count=1))
git checkout "$LATEST"

echo "Installing dependencies..."
npm install --production

echo "Restoring configuration..."
cp /tmp/.env.backup /opt/streetmerchant/.env
rm /tmp/.env.backup

echo "Starting Streetmerchant..."
systemctl start streetmerchant

echo "Update complete! Now running version: $LATEST"
EOF
chmod +x /usr/bin/update-streetmerchant
msg_ok "Update script created"

msg_info "Saving Version Information"
echo "${RELEASE}" > /opt/${APP}_version.txt
msg_ok "Version information saved"

msg_info "Configuring Container"
motd_ssh

# Ensure auto-login is enabled
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat <<EOF >$GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
msg_ok "Configured Container"

customize
cleanup_lxc
