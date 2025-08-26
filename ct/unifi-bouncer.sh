#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/brianbento/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/teifun2/cs-unifi-bouncer

# App Default Values
APP="UniFi-Bouncer"
var_tags="${var_tags:-network;security}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

function header_info() {
  echo -e "${BL}
 _   _       _ ______ _   ____                                  
| | | |     (_)  ____(_) |  _ \                                 
| | | |_ __  _| |__   _  | |_) | ___  _   _ _ __   ___ ___ _ __  
| | | | '_ \| |  __| | | |  _ < / _ \| | | | '_ \ / __/ _ \ '__| 
| |_| | | | | | |    | | | |_) | (_) | |_| | | | | (_|  __/ |    
 \___/|_| |_|_|_|    |_| |____/ \___/ \__,_|_| |_|\___\___|_|    
${CL}"
}

header_info
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if UniFi Bouncer installation is present
  if [[ ! -f /opt/cs-unifi-bouncer/unifi-bouncer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Check for new version using GitHub API
  RELEASE=$(curl -fsSL https://api.github.com/repos/teifun2/cs-unifi-bouncer/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
  
  # Fallback to main if no release found
  if [[ -z "$RELEASE" ]]; then
    RELEASE="main"
  fi
  
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    # Stopping UniFi Bouncer service
    msg_info "Stopping $APP"
    systemctl stop unifi-bouncer
    msg_ok "Stopped $APP"

    # Creating Backup
    msg_info "Creating Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/cs-unifi-bouncer/config /opt/cs-unifi-bouncer/unifi-bouncer
    msg_ok "Backup Created"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"
    cd /opt/cs-unifi-bouncer || exit
    $STD git fetch --tags
    
    # Handle different release types
    if [[ "$RELEASE" == "main" ]]; then
      $STD git checkout main
      $STD git pull origin main
      export GOFLAGS="-ldflags=-X=main.version=development"
    else
      # Try to checkout the release, fallback to main if it fails
      if ! git checkout "v${RELEASE}" 2>/dev/null; then
        echo "Release v${RELEASE} not found, falling back to main branch"
        RELEASE="main"
        $STD git checkout main
        $STD git pull origin main
        export GOFLAGS="-ldflags=-X=main.version=development"
      else
        export GOFLAGS="-ldflags=-X=main.version=${RELEASE}"
      fi
    fi
    
    $STD go build -o unifi-bouncer
    chown unifi-bouncer:unifi-bouncer unifi-bouncer
    chmod +x unifi-bouncer
    if [[ "$RELEASE" == "main" ]]; then
      msg_ok "Updated $APP to development version"
    else
      msg_ok "Updated $APP to v${RELEASE}"
    fi

    # Starting UniFi Bouncer service
    msg_info "Starting $APP"
    systemctl start unifi-bouncer
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    $STD go clean -cache
    msg_ok "Cleanup Completed"

    # Update version file
    if [[ "$RELEASE" == "main" ]]; then
      echo "development" >/opt/${APP}_version.txt
    else
      echo "${RELEASE}" >/opt/${APP}_version.txt
    fi
    msg_ok "Update Successful"
  else
    if [[ "$RELEASE" == "main" ]]; then
      msg_ok "No update required. ${APP} is already at development version"
    else
      msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Configuration required:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Edit /opt/cs-unifi-bouncer/config.yaml${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Configure UniFi controller settings${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Register with CrowdSec: cscli bouncers add unifi-bouncer${CL}"
