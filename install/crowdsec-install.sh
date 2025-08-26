#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/crowdsecurity/crowdsec

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
  gnupg \
  lsb-release \
  wget \
  apt-transport-https \
  ca-certificates \
  git \
  software-properties-common
msg_ok "Installed Dependencies"

# Setup CrowdSec Repository
msg_info "Setting up CrowdSec Repository"
curl -fsSL "https://install.crowdsec.net" | $STD bash
msg_ok "Setup CrowdSec Repository"

# Installing CrowdSec
msg_info "Installing CrowdSec"
$STD apt-get update
$STD apt-get install -y crowdsec
msg_ok "Installed CrowdSec"

# Enabling and Starting CrowdSec Service
msg_info "Enabling and Starting CrowdSec Service"
systemctl enable -q --now crowdsec
msg_ok "CrowdSec Service Enabled and Started"

# Installing CrowdSec Collections
msg_info "Installing CrowdSec Collections"
$STD cscli collections install crowdsecurity/http-cve
$STD cscli collections install crowdsecurity/base-http-scenarios
$STD cscli collections install crowdsecurity/sshd
$STD cscli collections install crowdsecurity/linux
$STD cscli collections install crowdsecurity/appsec-crs
$STD cscli collections install crowdsecurity/appsec-generic-rules
$STD cscli collections install crowdsecurity/appsec-virtual-patching
$STD cscli collections install fulljackz/proxmox
$STD cscli parsers install crowdsecurity/whitelists
systemctl reload crowdsec
msg_ok "Installed CrowdSec Collections"

# Configure Host Log Monitoring
msg_info "Configuring Host Log Monitoring"
if [[ -d /host/var/log ]]; then
  # Create custom acquisition config for host logs
  cat <<EOF >/etc/crowdsec/acquis.d/host-logs.yaml
# Proxmox Host Log Monitoring
---
# Host authentication logs (SSH, sudo, etc.)
source: /host/var/log/auth.log
labels:
  type: syslog
  source: "proxmox-host"
---
# Host system logs
source: /host/var/log/syslog
labels:
  type: syslog
  source: "proxmox-host"
---
# Host kernel logs
source: /host/var/log/kern.log
labels:
  type: syslog
  source: "proxmox-host"
---
# Proxmox VE logs (if available)
source: /host/pve/*.log
labels:
  type: syslog
  source: "proxmox-pve"
EOF

  # Restart CrowdSec to apply new acquisition config
  systemctl restart crowdsec
  
  msg_ok "Configured Host Log Monitoring"
  echo ""
  echo "✅ Host logs detected and configured!"
  echo "   CrowdSec will now monitor Proxmox host logs for security events."
else
  msg_ok "Host Log Monitoring (not configured - no host logs detected)"
  echo ""
  echo "ℹ️  To enable host log monitoring:"
  echo "   1. Stop this container: pct stop <container-id>"
  echo "   2. Add bind mounts: pct set <container-id> -mp0 /var/log,mp=/host/var/log,ro=1"
  echo "   3. Start container: pct start <container-id>"
  echo "   4. Restart CrowdSec: systemctl restart crowdsec"
fi

# Configure UniFi Syslog Listener
msg_info "Configuring UniFi Syslog Listener"
cat <<EOF >/etc/crowdsec/acquis.d/unifi-syslog.yaml
# UniFi Syslog Listener
# Listens for syslog messages from UniFi devices
source: syslog
listen_addr: 0.0.0.0
listen_port: 4242
labels:
 type: unifi
EOF
msg_ok "Configured UniFi Syslog Listener on port 4242"

# Get installed version for update checks
msg_info "Recording CrowdSec Version Information"
RELEASE=$(cscli version | head -n1 | awk '{print $3}' | sed 's/^v//')

# Remove existing version file if it exists
[[ -f /opt/CrowdSec_version.txt ]] && rm -f /opt/CrowdSec_version.txt

echo "${RELEASE}" >/opt/CrowdSec_version.txt
msg_ok "CrowdSec Version Information Recorded"

# Ask user if they want to install UniFi Bouncer
echo ""
read -p "Do you want to install UniFi Bouncer for CrowdSec? (y/N): " install_unifi
if [[ $install_unifi =~ ^[Yy]$ ]]; then
  # Installing Go for UniFi Bouncer
  msg_info "Installing Go"
  GO_VERSION="1.21.5"
  
  # Check if Go is already installed
  if [[ -d "/usr/local/go" ]]; then
    rm -rf /usr/local/go
  fi
  
  $STD wget -O go${GO_VERSION}.linux-amd64.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
  $STD tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
  rm go${GO_VERSION}.linux-amd64.tar.gz
  
  # Add Go to PATH if not already present
  if ! grep -q '/usr/local/go/bin' /etc/profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  fi
  export PATH=$PATH:/usr/local/go/bin
  msg_ok "Installed Go v${GO_VERSION}"

  # Creating System User for UniFi Bouncer
  msg_info "Creating UniFi Bouncer System User"
  if ! id "unifi-bouncer" &>/dev/null; then
    useradd --system --home-dir /opt/cs-unifi-bouncer --create-home --shell /bin/false unifi-bouncer
    msg_ok "Created UniFi Bouncer System User"
  else
    msg_ok "UniFi Bouncer System User Already Exists"
  fi

  # Cloning and Building UniFi Bouncer
  msg_info "Setting up UniFi Bouncer"
  cd /opt || exit
  
  # Remove existing directory if it exists
  if [[ -d "cs-unifi-bouncer" ]]; then
    rm -rf cs-unifi-bouncer
  fi
  
  $STD git clone https://github.com/teifun2/cs-unifi-bouncer.git
  cd cs-unifi-bouncer || exit

  # Get latest release version
  UNIFI_RELEASE=$(curl -fsSL https://api.github.com/repos/teifun2/cs-unifi-bouncer/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')

  # Fallback to main branch if no release found
  if [[ -z "$UNIFI_RELEASE" ]]; then
    echo "No release found, using main branch"
    UNIFI_RELEASE="main"
    $STD git checkout main
  else
    echo "Found release: v${UNIFI_RELEASE}"
    # Try to checkout the release, fallback to main if it fails
    if ! git checkout "v${UNIFI_RELEASE}" 2>/dev/null; then
      echo "Release v${UNIFI_RELEASE} not found, falling back to main branch"
      UNIFI_RELEASE="main"
      $STD git checkout main
    fi
  fi

  # Build with version info
  if [[ "$UNIFI_RELEASE" != "main" ]]; then
    export GOFLAGS="-ldflags=-X=main.version=${UNIFI_RELEASE}"
  else
    export GOFLAGS="-ldflags=-X=main.version=development"
  fi

  # Build the application
  if ! /usr/local/go/bin/go build -o unifi-bouncer; then
    msg_error "Failed to build UniFi Bouncer"
    exit 1
  fi

  # Set permissions
  chown -R unifi-bouncer:unifi-bouncer /opt/cs-unifi-bouncer
  chmod +x unifi-bouncer
  msg_ok "Setup UniFi Bouncer v${UNIFI_RELEASE}"

  # Auto-configure UniFi Bouncer
  msg_info "Auto-configuring UniFi Bouncer"
  
  # Generate CrowdSec API key for UniFi Bouncer
  API_KEY=$(cscli bouncers add unifi-bouncer -o raw)
  
  # Ask for UniFi configuration
  echo ""
  echo "UniFi Controller Configuration (optional during install)"
  echo "======================================================="
  read -p "UniFi Controller URL (e.g., https://unifi.example.com:8443): " unifi_url
  read -p "UniFi API Key (leave empty to configure later): " unifi_api_key
  read -p "Skip TLS verification? (y/N): " skip_tls
  
  # Set defaults if not provided
  if [[ -z "$unifi_url" ]]; then
    unifi_url="https://unifi.example.com:8443"
    UNIFI_CONFIGURED=false
  else
    UNIFI_CONFIGURED=true
  fi
  
  if [[ -z "$unifi_api_key" ]]; then
    unifi_api_key="YOUR_UNIFI_API_KEY_HERE"
    UNIFI_CONFIGURED=false
  fi
  
  if [[ $skip_tls =~ ^[Yy]$ ]]; then
    skip_tls_verify="true"
  else
    skip_tls_verify="false"
  fi
  
  # Create environment configuration with generated API key
  cat <<EOF >/opt/cs-unifi-bouncer/.env
# UniFi Bouncer Environment Configuration
# CrowdSec configuration is auto-configured

# CrowdSec Configuration (Auto-configured)
CROWDSEC_URL=http://localhost:8080
CROWDSEC_BOUNCER_API_KEY=${API_KEY}

# UniFi Controller Configuration
UNIFI_HOST=${unifi_url}
UNIFI_API_KEY=${unifi_api_key}
UNIFI_SITE=default
UNIFI_SKIP_TLS_VERIFY=${skip_tls_verify}

# Bouncer Settings
CROWDSEC_UPDATE_INTERVAL=10s
LOG_LEVEL=1
UNIFI_IPV6=true
UNIFI_MAX_GROUP_SIZE=10000
UNIFI_IPV4_START_RULE_INDEX=22000
UNIFI_IPV6_START_RULE_INDEX=27000
UNIFI_LOGGING=false
UNIFI_ZONE_SRC=External
UNIFI_ZONE_DST=External Internal Vpn Hotspot
EOF
  chown unifi-bouncer:unifi-bouncer /opt/cs-unifi-bouncer/.env
  chmod 600 /opt/cs-unifi-bouncer/.env
  msg_ok "Auto-configured UniFi Bouncer with CrowdSec API key"

  # Creating UniFi Bouncer Service
  msg_info "Creating UniFi Bouncer Service"
  
  # Stop existing service if running
  if systemctl is-active --quiet unifi-bouncer; then
    systemctl stop unifi-bouncer
  fi
  
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
EnvironmentFile=/opt/cs-unifi-bouncer/.env
ExecStart=/opt/cs-unifi-bouncer/unifi-bouncer
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
  if [[ "$UNIFI_CONFIGURED" == "true" ]]; then
    systemctl enable --now unifi-bouncer
    msg_ok "Created and Started UniFi Bouncer Service"
  else
    systemctl enable unifi-bouncer
    msg_ok "Created UniFi Bouncer Service (not started - configure first)"
  fi

  # Recording UniFi Bouncer Version Information
  msg_info "Recording UniFi Bouncer Version Information"
  
  # Remove existing version file if it exists
  [[ -f /opt/UniFi-Bouncer_version.txt ]] && rm -f /opt/UniFi-Bouncer_version.txt
  
  if [[ "$UNIFI_RELEASE" == "main" ]]; then
    echo "development" >/opt/UniFi-Bouncer_version.txt
  else
    echo "${UNIFI_RELEASE}" >/opt/UniFi-Bouncer_version.txt
  fi
  msg_ok "UniFi Bouncer Version Information Recorded"

  UNIFI_INSTALLED=true
else
  UNIFI_INSTALLED=false
fi

# Create configuration information
{
  echo "CrowdSec Installation Complete"
  echo "==============================="
  echo "CrowdSec Version: $RELEASE"
  echo ""
  echo "CrowdSec Commands:"
  echo "- cscli metrics: View CrowdSec metrics"
  echo "- cscli decisions list: View active decisions/blocks"
  echo "- cscli collections list: View installed collections"
  echo "- cscli scenarios list: View installed scenarios"
  echo "- cscli bouncers list: View registered bouncers"
  echo ""
  echo "Pre-installed CrowdSec Collections:"
  echo "- crowdsecurity/http-cve: HTTP CVE detection"
  echo "- crowdsecurity/base-http-scenarios: Base HTTP scenarios"
  echo "- crowdsecurity/sshd: SSH protection"
  echo "- crowdsecurity/linux: Linux system protection"
  echo "- crowdsecurity/appsec-crs: AppSec Core Rule Set"
  echo "- crowdsecurity/appsec-generic-rules: AppSec generic rules"
  echo "- crowdsecurity/appsec-virtual-patching: AppSec virtual patching"
  echo "- fulljackz/proxmox: Proxmox VE specific protection"
  echo "- crowdsecurity/whitelists: Whitelists parser"
  echo ""
  echo "UniFi Syslog Listener:"
  echo "- Listening on port 4242 for UniFi device logs"
  echo "- Configure UniFi devices to send logs to this CrowdSec instance"
  echo ""
  echo "CrowdSec Configuration files:"
  echo "- Main config: /etc/crowdsec/config.yaml"
  echo "- Collections: /etc/crowdsec/collections/"
  echo "- Scenarios: /etc/crowdsec/scenarios/"
  echo ""
  echo "CrowdSec Log files:"
  echo "- CrowdSec: /var/log/crowdsec.log"
  
  # Add host log monitoring info if configured
  if [[ -d /host/var/log ]]; then
    echo ""
    echo "Host Log Monitoring: ✅ ENABLED"
    echo "- Monitoring Proxmox host logs for security events"
    echo "- Host authentication logs: /host/var/log/auth.log"
    echo "- Host system logs: /host/var/log/syslog"
    echo "- Host kernel logs: /host/var/log/kern.log"
    echo "- Proxmox VE logs: /host/pve/*.log"
    echo "- Configuration: /etc/crowdsec/acquis.d/host-logs.yaml"
  else
    echo ""
    echo "Host Log Monitoring: ⚠️ NOT CONFIGURED"
    echo "To enable monitoring of Proxmox host logs:"
    echo "1. Stop container: pct stop <container-id>"
    echo "2. Add bind mounts:"
    echo "   - pct set <container-id> -mp0 /var/log,mp=/host/var/log,ro=1"
    echo "   - pct set <container-id> -mp1 /var/log/pve,mp=/host/pve,ro=1 (if exists)"
    echo "3. Start container: pct start <container-id>"
    echo "4. Restart CrowdSec: systemctl restart crowdsec"
  fi
  
  if [[ "$UNIFI_INSTALLED" == "true" ]]; then
    if [[ "$UNIFI_RELEASE" == "main" ]]; then
      echo ""
      echo "UniFi Bouncer Installation Complete"
      echo "===================================="
      echo "UniFi Bouncer Version: development (main branch)"
    else
      echo ""
      echo "UniFi Bouncer Installation Complete"
      echo "===================================="
      echo "UniFi Bouncer Version: $UNIFI_RELEASE"
    fi
    echo ""
    if [[ "$UNIFI_CONFIGURED" == "true" ]]; then
      echo "UniFi Bouncer Status: STARTED (fully configured)"
      echo ""
      echo "✓ CrowdSec API: Auto-configured"
      echo "✓ UniFi Controller: Configured during installation"
      echo ""
      echo "The UniFi Bouncer is ready and running!"
    else
      echo "UniFi Bouncer Status: READY (CrowdSec configured, UniFi pending)"
      echo ""
      echo "✓ CrowdSec API: Auto-configured"
      echo "⚠ UniFi Controller: CONFIGURATION REQUIRED"
      echo ""
      echo "NEXT STEPS:"
      echo "1. Edit /opt/cs-unifi-bouncer/.env"
      echo "   - Set UNIFI_HOST (your UniFi controller URL)"
      echo "   - Set UNIFI_API_KEY (your UniFi API key)"
      echo "   - Adjust UNIFI_SKIP_TLS_VERIFY if needed"
      echo ""
      echo "2. Start the service:"
      echo "   - systemctl start unifi-bouncer"
      echo "   - systemctl status unifi-bouncer"
    fi
    echo ""
    echo "UniFi Bouncer Commands:"
    echo "- systemctl status unifi-bouncer: Check bouncer status"
    echo "- journalctl -u unifi-bouncer -f: View bouncer logs"
    echo "- systemctl restart unifi-bouncer: Restart bouncer"
    echo ""
    echo "UniFi Bouncer Files:"
    echo "- Environment Config: /opt/cs-unifi-bouncer/.env"
    echo "- Binary: /opt/cs-unifi-bouncer/unifi-bouncer"
    echo "- Service: /etc/systemd/system/unifi-bouncer.service"
    echo ""
    echo "Generated CrowdSec API Key: ${API_KEY}"
    echo ""
    echo "Note: Only UniFi controller settings need configuration!"
  fi
} >>~/CrowdSec.info

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
if [[ "$UNIFI_INSTALLED" == "true" ]]; then
  /usr/local/go/bin/go clean -cache
fi
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
