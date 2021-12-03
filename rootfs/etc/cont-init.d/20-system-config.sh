#!/usr/bin/with-contenv bash
# shellcheck shell=bash
. "/usr/local/bin/logger"
program_name="system-config"

## Configure Timezone
echo "Setting system timezone to ${TZ}" | info "[${program_name}] "
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime

