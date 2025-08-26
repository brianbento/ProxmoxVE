#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/teifun2/cs-unifi-bouncer

# Import Functions and Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git \
  wget \
  ca-certificates \
  gnupg \
  software-properties-common
msg_ok "Installed Dependencies"

# Installing Go
msg_info "Installing Go"
GO_VERSION="1.21.5"
$STD wget -O go${GO_VERSION}.linux-amd64.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
$STD tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
export PATH=$PATH:/usr/local/go/bin
msg_ok "Installed Go v${GO_VERSION}"

# Creating System User
msg_info "Creating System User"
useradd --system --home-dir /opt/cs-unifi-bouncer --create-home --shell /bin/false unifi-bouncer
msg_ok "Created System User"

# Cloning and Building UniFi Bouncer
msg_info "Setting up UniFi Bouncer"
cd /opt || exit
$STD git clone https://github.com/teifun2/cs-unifi-bouncer.git
cd cs-unifi-bouncer || exit

# Get latest release version
RELEASE=$(curl -fsSL https://api.github.com/repos/teifun2/cs-unifi-bouncer/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
$STD git checkout "v${RELEASE}"

# Build with version info (same as workflow)
export GOFLAGS="-ldflags=-X=main.version=${RELEASE}"
$STD /usr/local/go/bin/go build -o unifi-bouncer

# Set permissions
chown -R unifi-bouncer:unifi-bouncer /opt/cs-unifi-bouncer
chmod +x unifi-bouncer
msg_ok "Setup UniFi Bouncer v${RELEASE}"

# Creating Configuration Directory
msg_info "Creating Configuration"
mkdir -p /opt/cs-unifi-bouncer/config
cat <<EOF >/opt/cs-unifi-bouncer/config.yaml
# UniFi Bouncer Configuration
# Configure your UniFi controller and CrowdSec settings here

# CrowdSec Configuration
crowdsec_lapi_url: "http://localhost:8080"
crowdsec_lapi_key: "YOUR_API_KEY_HERE"

# UniFi Controller Configuration  
unifi_url: "https://unifi.example.com:8443"
unifi_username: "admin"
unifi_password: "password"
unifi_site_id: "default"

# Bouncer Settings
update_frequency: "10s"
log_level: "info"
EOF
chown unifi-bouncer:unifi-bouncer /opt/cs-unifi-bouncer/config.yaml
chmod 600 /opt/cs-unifi-bouncer/config.yaml
msg_ok "Created Configuration"

# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/unifi-bouncer.service
[Unit]
Description=UniFi Bouncer for CrowdSec
Documentation=https://github.com/teifun2/cs-unifi-bouncer
After=network.target crowdsec.service
Wants=crowdsec.service

[Service]
Type=simple
User=unifi-bouncer
Group=unifi-bouncer
ExecStart=/opt/cs-unifi-bouncer/unifi-bouncer -c /opt/cs-unifi-bouncer/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=unifi-bouncer

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/cs-unifi-bouncer

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable unifi-bouncer
msg_ok "Created Service"

# Recording Version Information
msg_info "Recording Version Information"
echo "${RELEASE}" >/opt/UniFi-Bouncer_version.txt
msg_ok "Version Information Recorded"

# Create setup information
{
  echo "UniFi Bouncer for CrowdSec Installation Complete"
  echo "================================================"
  echo "Version: $RELEASE"
  echo ""
  echo "IMPORTANT: Configuration Required!"
  echo ""
  echo "1. Configure CrowdSec API:"
  echo "   - Generate API key: cscli bouncers add unifi-bouncer"
  echo "   - Copy the API key to config.yaml"
  echo ""
  echo "2. Configure UniFi Controller:"
  echo "   - Edit /opt/cs-unifi-bouncer/config.yaml"
  echo "   - Set your UniFi controller URL, username, password"
  echo "   - Set the site ID (usually 'default')"
  echo ""
  echo "3. Start the service:"
  echo "   - systemctl start unifi-bouncer"
  echo "   - systemctl status unifi-bouncer"
  echo ""
  echo "4. Check logs:"
  echo "   - journalctl -u unifi-bouncer -f"
  echo ""
  echo "Configuration file: /opt/cs-unifi-bouncer/config.yaml"
  echo "Service logs: journalctl -u unifi-bouncer"
  echo ""
  echo "Note: Ensure CrowdSec is installed and running!"
} >>~/UniFi-Bouncer.info

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
/usr/local/go/bin/go clean -cache
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
