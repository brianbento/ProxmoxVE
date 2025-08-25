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
  ca-certificates
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

# Installing CrowdSec Firewall Bouncer
msg_info "Installing CrowdSec Firewall Bouncer"
$STD apt-get install -y crowdsec-firewall-bouncer-iptables
msg_ok "Installed CrowdSec Firewall Bouncer"

# Enabling and Starting Services
msg_info "Enabling and Starting Services"
systemctl enable -q --now crowdsec
systemctl enable -q --now crowdsec-firewall-bouncer
msg_ok "Services Enabled and Started"

# Get installed version for update checks
msg_info "Recording Version Information"
RELEASE=$(cscli version | head -n1 | awk '{print $3}' | sed 's/^v//')
echo "${RELEASE}" >/opt/CrowdSec_version.txt
msg_ok "Version Information Recorded"

# Create basic configuration note
{
  echo "CrowdSec Installation Complete"
  echo "==============================="
  echo "Version: $RELEASE"
  echo ""
  echo "Useful Commands:"
  echo "- cscli metrics: View CrowdSec metrics"
  echo "- cscli decisions list: View active decisions/blocks"
  echo "- cscli collections list: View installed collections"
  echo "- cscli scenarios list: View installed scenarios"
  echo ""
  echo "Configuration files:"
  echo "- Main config: /etc/crowdsec/config.yaml"
  echo "- Collections: /etc/crowdsec/collections/"
  echo "- Scenarios: /etc/crowdsec/scenarios/"
  echo ""
  echo "Log files:"
  echo "- CrowdSec: /var/log/crowdsec.log"
  echo "- Firewall bouncer: /var/log/crowdsec-firewall-bouncer.log"
} >>~/CrowdSec.info

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
