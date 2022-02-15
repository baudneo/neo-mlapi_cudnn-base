#!/usr/bin/with-contenv bash
# shellcheck shell=bash
. "/usr/local/bin/logger"
program_name="log-config"

echo "Configuring log rotation with a maximum of ${MAX_LOG_NUMBER} logs and a max log size \
of ${MAX_LOG_SIZE_BYTES} bytes" | info "[${program_name}] "
echo -n "n${MAX_LOG_NUMBER} s${MAX_LOG_SIZE_BYTES} 1" > /var/run/s6/container_environment/S6_LOGGING_SCRIPT
