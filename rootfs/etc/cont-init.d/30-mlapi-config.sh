#!/usr/bin/with-contenv bash
# shellcheck shell=bash
. "/usr/local/bin/logger"
program_name="mlapi-config"
create(){
  # $1 = 'file' or 'dir'
  # $2 = 'SOURCE path'
  # $3 = 'DESTINATION path' - chekcs if the destination exists, if not it copies SOURCE to DESTINATION
  if [ "${1}" == 'file' ]; then
    if [ ! -f "${3}" ]; then
      echo "Creating ${3}" | init "[${program_name}] "
      s6-setuidgid www-data cp "${2}" "${3}"
    fi
  elif [ "${1}" == 'dir' ]; then
    if [ ! -d "${3}" ]; then
      echo "Creating ${3}" | init "[${program_name}] "
      s6-setuidgid www-data cp -r "${2}" "${3}"
    fi
  else
    echo "create(${1}): Unknown type" | warn "[${program_name}] "
  fi
}

[[ ! -f /config/mlapiconfig.yml ]] && echo "Creating Neo MLAPI configuration file" | init "[${program_name}] "
[[ ! -f /mlapi/mlapi.py ]] && echo "Creating Neo MLAPI' MAIN mlapi.py file from cache - If you want \
to upgrade you must mount the containers /mlapi as a volume and place a newer mlapi.py inside. The final absolute \
path has to be /mlapi/mlapi.py " | init "[${program_name}] "
create 'file' '/mlapi_default/mlapiconfig.yml' '/config/mlapiconfig.yml'
create 'file' '/mlapi_default/mlapisecrets.yml' '/config/mlapisecrets.yml'
create 'file' '/mlapi_default/mlapi_dbuser.py' '/config/mlapi_dbuser.py'
create 'file' '/mlapi_default/mlapi_face_train.py' '/config/mlapi_face_train.py'
create 'file' '/mlapi_default/get_encryption_key.py' '/config/get_encryption_key.py'
create 'file' '/mlapi_default/get_models.sh' '/config/get_models.sh'
create 'file' '/mlapi_default/mlapi.py' '/mlapi/mlapi.py'
create 'dir' '/mlapi_default/known_faces' '/config/known_faces'
create 'dir' '/mlapi_default/unknown_faces' '/config/unknown_faces'
create 'dir' '/mlapi_default/tools' '/config/tools'
create 'dir' '/mlapi_default/models' '/config/models'
create 'dir' '/mlapi_default/db' '/config/db'
create 'dir' '/mlapi_default/examples' '/config/examples'
chown -R www-data:www-data /config

# ML models
if [ ! -f /config/models/coral_edgetpu/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite ]; then
  echo "Grabbing ML models ([Tiny] YOLOv3, [Tiny] YOLOv4, coral TPU models)" | init "[${program_name}] "
  s6-setuidgid www-data cp -r /mlapi_defaults/models /config
fi
## Configure MLAPI
echo "Configuring Neo MLAPI Settings" | info "[${program_name}] "
sed -i "s|#\?base_data_path:.*|base_data_path: /config|" /config/mlapiconfig.yml
sed -i "s|#\?wsgi_server:.*|wsgi_server: bjoern|" /config/mlapiconfig.yml
sed -i "s|#\?log_user:.*|log_user: www-data|" /config/mlapiconfig.yml
sed -i "s|#\?log_group:.*|log_group: www-data|" /config/mlapiconfig.yml
# Always syslog
sed -i "s|#\?log_level_syslog:.*|log_level_syslog: 5|" /config/mlapiconfig.yml

if [ "$MLAPI_DEBUG_ENABLED" -eq 1 ]; then
  echo "Enabling debug logs in 'pyzm_overrides'" | info "[${program_name}] "
  sed -i "s|#\?log_debug:.*|log_debug: True|" /config/mlapiconfig.yml
  sed -i "s|#\?log_debug_target:.*|log_debug_target: _zm_mlapi|" /config/mlapiconfig.yml
  sed -i "s|#\?log_level_debug:.*|log_level_debug: 5|" /config/mlapiconfig.yml
elif [ "$MLAPI_DEBUG_ENABLED" -eq 0 ]; then
  sed -i "s|#\?log_debug:.*|log_debug: False|" /config/mlapiconfig.yml
  sed -i "s|#\?log_debug_target:.*|log_debug_target: ''|" /config/mlapiconfig.yml
  sed -i "s|#\?log_level_debug:.*|log_level_debug: 0|" /config/mlapiconfig.yml
fi
# Always have file logging off
sed -i "s|#\?log_debug_file:.*|log_debug_file: -5|" /config/mlapiconfig.yml
sed -i "s|#\?log_level_file:.*|log_level_file: -5|" /config/mlapiconfig.yml

# db user, ensures there is always at least 1 default user
python3 /config/mlapi_dbuser.py --force -c /config/mlapiconfig.yml -d /config/db -u ${MLAPIDB_USER} -p ${MLAPIDB_PASS}
# If the JWT key is default, create a new one (don't overwrite an existing string)
jwt_needed=$(grep "MLAPI_SECRET_KEY: MAKE me something" < /config/mlapisecrets.yml)
if [ -z "${jwt_needed}" ]; then
  if [ "${USE_SECURE_RANDOM_ORG}" -eq 1 ]; then
      echo "Fetching random secure string for MLAPI JWT signing key from random.org..." | init
      random_string=$(
        wget -qO - \
          "https://www.random.org/strings/?num=4&len=20&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new" \
        | tr -d '\n' \
      )
    else
      echo "Generating standard random string for MLAPI JWT signing key..." | init
      random_string="$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM"
  fi
  sed -i "s|MLAPI_SECRET_KEY:.*|MLAPI_SECRET_KEY: \"${random_string}\"|" /config/mlapisecrets.yml
fi

