#!/usr/bin/with-contenv bash
# shellcheck shell=bash
. "/usr/local/bin/logger"
program_name="mlapi-config"

if [ ! -f /config/mlapi_dbuser.py ]; then
  echo "/config/mlapi_dbuser.py not found, creating base config..." | init "[${program_name}]"
  s6-setuidgid www-data cp /mlapi/mlapi_dbuser.py /config
  s6-setuidgid www-data cp /mlapi/mlapi_face_train.py /config
  s6-setuidgid www-data cp /mlapi/get_encryption_key.py /config
  s6-setuidgid www-data cp /mlapi/get_models.sh /config
  s6-setuidgid www-data cp /mlapi/mlapiconfig.yml /config
  s6-setuidgid www-data cp /mlapi/mlapisecrets.yml /config
  s6-setuidgid www-data cp -r /mlapi/images/ /config
  s6-setuidgid www-data cp -r /mlapi/known_faces/ /config
  s6-setuidgid www-data cp -r /mlapi/unknown_faces/ /config
  s6-setuidgid www-data cp -r /mlapi/tools/ /config
  s6-setuidgid www-data cp -r /mlapi/models /config
  s6-setuidgid www-data cp -r /mlapi/logs/ /config
  s6-setuidgid www-data cp -r /mlapi/db/ /config
  s6-setuidgid www-data cp -r /mlapi/examples/ /config
  s6-setuidgid www-data cp -r /mlapi/tools/ /config
  chown -R www-data:www-data /config
fi

## Configure MLAPI and ES for communication
echo "Configuring Neo MLAPI Settings" | info "[${program_name}] "
sed -i "s|base_data_path:.*|base_data_path: /config|" /config/mlapiconfig.yml
sed -i "s|#wsgi_server: bjoern|wsgi_server: bjoern|" /config/mlapiconfig.yml
sed -i "s|#log_user:.*|log_user: www-data|" /config/mlapiconfig.yml
sed -i "s|#log_group:.*|log_group: www-data|" /config/mlapiconfig.yml
sed -i "s|#log_path:.*|log_path: /log|" /config/mlapiconfig.yml
sed -i "s|#log_name:.*|log_name: mlapi-service|" /config/mlapiconfig.yml
# db user, ensures there is always at least 1 default user
python3 /config/mlapi_dbuser.py --force -c /config/mlapiconfig.yml -d /config/db -u ${MLAPIDB_USER} -p ${MLAPIDB_PASS}
# If the JWT key is default, create a new one (dont need to create one every restart)
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


