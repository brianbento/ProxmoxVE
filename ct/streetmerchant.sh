#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/brianbento/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bbento
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jef/streetmerchant

# App configuration
APP="Streetmerchant"
var_tags="shopping;automation;bot"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="13"
var_unprivileged="1"

# App info
variables
color
catch_errors

function header_info {
cat <<"EOF"
   _____ __               __                         __          __
  / ___// /_________  ___/ /_   ____ ___  ___  _____/ /_  ____ _/ /___
  \__ \/ __/ ___/ _ \/ __  __/ / __ `__ \/ _ \/ ___/ __ \/ __ `/ __/ /
 ___/ / /_/ /  /  __/ /_/ /_  / / / / / /  __/ /  / / / / /_/ / /_/ /_
/____/\__/_/   \___/\__/\__/ /_/ /_/ /_/\___/_/  /_/ /_/\__,_/\__/_(_)

EOF
}

header_info
echo -e "\n Loading..."

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/streetmerchant ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/jef/streetmerchant/releases/latest | \
    grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')

  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop streetmerchant
    msg_ok "Stopped ${APP}"

    msg_info "Backing up configuration"
    if [[ -f /opt/streetmerchant/.env ]]; then
      cp /opt/streetmerchant/.env /tmp/.env.backup
    fi
    msg_ok "Configuration backed up"

    msg_info "Updating ${APP} to v${RELEASE}"
    cd /opt/streetmerchant || exit
    git fetch --all
    git checkout "v${RELEASE}"
    npm install --production
    msg_ok "Updated ${APP} to v${RELEASE}"

    msg_info "Restoring configuration"
    if [[ -f /tmp/.env.backup ]]; then
      cp /tmp/.env.backup /opt/streetmerchant/.env
      rm /tmp/.env.backup
    fi
    msg_ok "Configuration restored"

    msg_info "Starting ${APP}"
    systemctl start streetmerchant
    msg_ok "Started ${APP}"

    echo "${RELEASE}" > /opt/${APP}_version.txt
    msg_ok "Update completed successfully"
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
echo -e "${INFO}${YW} Access the web interface using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Configuration file location:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/streetmerchant/.env${CL}"
