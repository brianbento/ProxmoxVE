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

header_info "$APP"
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
    $STD git checkout "v${RELEASE}"
    export GOFLAGS="-ldflags=-X=main.version=${RELEASE}"
    $STD go build -o unifi-bouncer
    chown unifi-bouncer:unifi-bouncer unifi-bouncer
    chmod +x unifi-bouncer
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting UniFi Bouncer service
    msg_info "Starting $APP"
    systemctl start unifi-bouncer
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    $STD go clean -cache
    msg_ok "Cleanup Completed"

    # Update version file
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
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
