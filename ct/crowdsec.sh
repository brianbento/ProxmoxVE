#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/brianbento/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/crowdsecurity/crowdsec

# App Default Values
APP="CrowdSec"
var_tags="${var_tags:-security;intrusion-detection}"
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

  # Check if CrowdSec installation is present
  if [[ ! -f /usr/bin/cscli ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Check for new version using GitHub API
  RELEASE=$(curl -fsSL https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    # Stopping CrowdSec service
    msg_info "Stopping $APP"
    systemctl stop crowdsec
    msg_ok "Stopped $APP"

    # Creating Backup
    msg_info "Creating Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /etc/crowdsec /var/lib/crowdsec
    msg_ok "Backup Created"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"
    $STD apt-get update
    $STD apt-get upgrade -y crowdsec
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting CrowdSec service
    msg_info "Starting $APP"
    systemctl start crowdsec
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    $STD apt-get -y autoremove
    $STD apt-get -y autoclean
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
echo -e "${INFO}${YW} Access it using the following commands:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}cscli metrics${CL} - View metrics"
echo -e "${TAB}${GATEWAY}${BGN}cscli decisions list${CL} - View active decisions"
