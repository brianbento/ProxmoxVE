#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/brianbento/ProxmoxVE/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: dave-yap (dave-yap)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://zitadel.com/

APP="Zitadel"
var_tags="${var_tags:-identity-provider}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/zitadel.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zitadel" "zitadel/zitadel"; then
    msg_info "Stopping Service"
    systemctl stop zitadel
    msg_ok "Stopped Service"

    rm -f /usr/local/bin/zitadel
    fetch_and_deploy_gh_release "zitadel" "zitadel/zitadel" "prebuild" "latest" "/usr/local/bin" "zitadel-linux-amd64.tar.gz"

    msg_info "Updating Zitadel"
    $STD zitadel setup --masterkeyFile /opt/zitadel/.masterkey --config /opt/zitadel/config.yaml --init-projections=true
    msg_ok "Updated Zitadel"

    msg_info "Starting Service"
    systemctl start zitadel
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start

# Prompt for domain configuration (runs on Proxmox host, before build)
echo ""
read -p "Enter your external domain (or press Enter to use auto-detected IP): " ZITADEL_DOMAIN
ZITADEL_DOMAIN=${ZITADEL_DOMAIN:-auto}

read -p "Enter external port (default: 443): " ZITADEL_PORT
ZITADEL_PORT=${ZITADEL_PORT:-443}

read -p "Are you using SSL? (y/n, default: y): " USE_SSL
USE_SSL=${USE_SSL:-y}
if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
  ZITADEL_SECURE="true"
else
  ZITADEL_SECURE="false"
fi

# Export for install script
export ZITADEL_DOMAIN
export ZITADEL_PORT
export ZITADEL_SECURE

build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"

# Read configuration from config.yaml inside the container
EXTERNAL_DOMAIN=$(pct exec "$CTID" -- grep "ExternalDomain:" /opt/zitadel/config.yaml | awk '{print $2}')
EXTERNAL_PORT=$(pct exec "$CTID" -- grep "ExternalPort:" /opt/zitadel/config.yaml | awk '{print $2}')
EXTERNAL_SECURE=$(pct exec "$CTID" -- grep "ExternalSecure:" /opt/zitadel/config.yaml | awk '{print $2}')

# Determine protocol
if [[ "$EXTERNAL_SECURE" == "true" ]]; then
  PROTOCOL="https"
else
  PROTOCOL="http"
fi

# Determine if port should be shown in URL
if [[ ("$EXTERNAL_SECURE" == "true" && "$EXTERNAL_PORT" == "443") || ("$EXTERNAL_SECURE" == "false" && "$EXTERNAL_PORT" == "80") ]]; then
  PORT_DISPLAY=""
else
  PORT_DISPLAY=":${EXTERNAL_PORT}"
fi

echo -e "${TAB}${GATEWAY}${BGN}${PROTOCOL}://${EXTERNAL_DOMAIN}${PORT_DISPLAY}/ui/console${CL}"
echo ""
echo -e "${INFO}${YW} Default Admin Credentials:${CL}"

# Read admin credentials from container using awk for reliable extraction
CREDS=$(pct exec "$CTID" -- bash -c "awk '/^Default Admin Credentials$/,/^Password:/' /root/zitadel.creds")
ADMIN_USERNAME=$(echo "$CREDS" | grep "^Username:" | awk '{print $2}')
ADMIN_PASSWORD=$(echo "$CREDS" | grep "^Password:" | awk '{print $2}')

echo -e "${TAB}${HOSTNAME}${YW} Username: ${GN}${ADMIN_USERNAME}${CL}"
echo -e "${TAB}${INFO}${YW} Password: ${GN}${ADMIN_PASSWORD}${CL}"
echo ""
echo -e "${INFO}${YW} All credentials saved in container: ${BL}/root/zitadel.creds${CL}"
