#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/brianbento/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/crowdsecurity/crowdsec

# App Default Values
APP="CrowdSec"
var_tags="${var_tags:-security;intrusion-detection}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if CrowdSec installation is present
  if [[ ! -f /usr/bin/cscli ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Update CrowdSec
  msg_info "Checking CrowdSec Updates"
  RELEASE=$(curl -fsSL https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping CrowdSec Service"
    systemctl stop crowdsec
    msg_ok "Stopped CrowdSec Service"

    msg_info "Creating CrowdSec Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /etc/crowdsec /var/lib/crowdsec
    msg_ok "Backup Created"

    msg_info "Updating CrowdSec to v${RELEASE}"
    $STD apt-get update
    $STD apt-get upgrade -y crowdsec
    msg_ok "Updated CrowdSec to v${RELEASE}"

    msg_info "Starting CrowdSec Service"
    systemctl start crowdsec
    msg_ok "Started CrowdSec Service"

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "CrowdSec Update Successful"
  else
    msg_ok "CrowdSec is already at v${RELEASE}"
  fi

  # Update UniFi Bouncer if installed
  if [[ -f /opt/cs-unifi-bouncer/unifi-bouncer ]]; then
    msg_info "Checking UniFi Bouncer Updates"
    UNIFI_RELEASE=$(curl -fsSL https://api.github.com/repos/teifun2/cs-unifi-bouncer/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
    
    # Fallback to main if no release found
    if [[ -z "$UNIFI_RELEASE" ]]; then
      UNIFI_RELEASE="main"
    fi
    
    if [[ "${UNIFI_RELEASE}" != "$(cat /opt/UniFi-Bouncer_version.txt)" ]] || [[ ! -f /opt/UniFi-Bouncer_version.txt ]]; then
      msg_info "Stopping UniFi Bouncer"
      systemctl stop unifi-bouncer
      msg_ok "Stopped UniFi Bouncer"

      msg_info "Creating UniFi Bouncer Backup"
      tar -czf "/opt/UniFi-Bouncer_backup_$(date +%F).tar.gz" /opt/cs-unifi-bouncer/config.yaml /opt/cs-unifi-bouncer/unifi-bouncer
      msg_ok "Backup Created"

      msg_info "Updating UniFi Bouncer to v${UNIFI_RELEASE}"
      cd /opt/cs-unifi-bouncer || exit
      $STD git fetch --tags
      
      if [[ "$UNIFI_RELEASE" == "main" ]]; then
        $STD git checkout main
        $STD git pull origin main
        export GOFLAGS="-ldflags=-X=main.version=development"
      else
        if ! git checkout "v${UNIFI_RELEASE}" 2>/dev/null; then
          UNIFI_RELEASE="main"
          $STD git checkout main
          $STD git pull origin main
          export GOFLAGS="-ldflags=-X=main.version=development"
        else
          export GOFLAGS="-ldflags=-X=main.version=${UNIFI_RELEASE}"
        fi
      fi
      
      $STD go build -o unifi-bouncer
      chown unifi-bouncer:unifi-bouncer unifi-bouncer
      chmod +x unifi-bouncer
      
      msg_info "Starting UniFi Bouncer"
      systemctl start unifi-bouncer
      msg_ok "Started UniFi Bouncer"

      if [[ "$UNIFI_RELEASE" == "main" ]]; then
        echo "development" >/opt/UniFi-Bouncer_version.txt
        msg_ok "Updated UniFi Bouncer to development version"
      else
        echo "${UNIFI_RELEASE}" >/opt/UniFi-Bouncer_version.txt
        msg_ok "Updated UniFi Bouncer to v${UNIFI_RELEASE}"
      fi
    else
      if [[ "$UNIFI_RELEASE" == "main" ]]; then
        msg_ok "UniFi Bouncer is already at development version"
      else
        msg_ok "UniFi Bouncer is already at v${UNIFI_RELEASE}"
      fi
    fi
  else
    msg_info "UniFi Bouncer not installed, skipping update"
  fi

  # Cleaning up
  msg_info "Cleaning Up"
  $STD apt-get -y autoremove
  $STD apt-get -y autoclean
  if [[ -f /usr/local/go/bin/go ]]; then
    /usr/local/go/bin/go clean -cache
  fi
  msg_ok "Cleanup Completed"

  exit
}

start
build_container

# Ask user about host log monitoring
echo ""
read -p "Enable host log monitoring? (Monitor Proxmox host logs for security events) (Y/n): " enable_host_logs

if [[ ! $enable_host_logs =~ ^[Nn]$ ]]; then
  msg_info "Configuring Host Log Monitoring"
  
  # Add bind mounts for host log monitoring
  pct set "$CTID" -mp0 /var/log,mp=/host/var/log,ro=1
  pct set "$CTID" -mp1 /var/log/auth.log,mp=/host/auth.log,ro=1  
  pct set "$CTID" -mp2 /var/log/syslog,mp=/host/syslog,ro=1
  pct set "$CTID" -mp3 /var/log/pve,mp=/host/pve,ro=1
  
  msg_ok "Configured Host Log Monitoring"
  echo ""
  echo "✅ Host log monitoring enabled!"
  echo "   CrowdSec will monitor Proxmox host logs for security events."
  HOST_MONITORING_ENABLED=true
else
  echo ""
  echo "ℹ️  Host log monitoring skipped."
  echo "   You can enable it later using the commands in the README."
  HOST_MONITORING_ENABLED=false
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} CrowdSec Commands (with security collections pre-installed):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}cscli metrics${CL} - View CrowdSec metrics"
echo -e "${TAB}${GATEWAY}${BGN}cscli decisions list${CL} - View active decisions"
echo -e "${TAB}${GATEWAY}${BGN}cscli collections list${CL} - View installed collections"
echo -e "${TAB}${GATEWAY}${BGN}cscli bouncers list${CL} - View registered bouncers"
if [[ "$HOST_MONITORING_ENABLED" == "true" ]]; then
  echo -e "${INFO}${YW} Host Log Monitoring: ✅ ENABLED${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}Monitoring Proxmox host logs automatically${CL}"
else
  echo -e "${INFO}${YW} Host Log Monitoring: ⚠️ DISABLED${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}pct set $CTID -mp0 /var/log,mp=/host/var/log,ro=1${CL} - Enable host monitoring"
  echo -e "${TAB}${GATEWAY}${BGN}systemctl restart crowdsec${CL} - Apply host log config"
fi
echo -e "${INFO}${YW} UniFi Bouncer (if installed - interactive setup):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}systemctl status unifi-bouncer${CL} - Check bouncer status"
echo -e "${TAB}${GATEWAY}${BGN}journalctl -u unifi-bouncer -f${CL} - View bouncer logs"
echo -e "${TAB}${GATEWAY}${BGN}nano /opt/cs-unifi-bouncer/config.yaml${CL} - Edit configuration"
