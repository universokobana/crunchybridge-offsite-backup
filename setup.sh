#!/bin/bash

# Author: Rafael Lima (https://github.com/rafaelp)

# terminate script as soon as any command fails
set -e

function info(){
    msg="$1"
    echo -e "$(date "+%F %T") INFO: $msg"
    logger -p user.notice -t "$(basename "$0")" "$msg"
}
function warning(){
    msg="$1"
    echo -e "$(date "+%F %T") WARNING: $msg"
    logger -p user.notice -t "$(basename "$0")" "$msg"
    return 1
}
function error(){
    msg="$1"
    echo -e "$(date "+%F %T") ERROR: $msg"
    logger -p user.error -t "$(basename "$0")" "$msg"
    exit 1
}

if [[ -z "$CBOB_CRUNCHY_API_KEY" ]]; then
  read -re -p 'Please inform your Crunch Bridge API Key: ' -i '' CBOB_CRUNCHY_API_KEY
  if [ "$CBOB_CRUNCHY_API_KEY" == "" ]; then
    error "Invalid API Key"
  fi
fi

if [[ -z "$CBOB_SLACK_CLI_TOKEN" ]]; then
  read -re -p 'Please inform your Slack CLI Token (leave blank if will not use): ' -i '' CBOB_SLACK_CLI_TOKEN
fi
if [ "$CBOB_SLACK_CLI_TOKEN" == "" ]; then
  warning 'No Slack Token given, this feature will be disabled.'
else
  if [[ -z "$CBOB_SLACK_CHANNEL" ]]; then
    read -re -p 'Slack channel to send logs: ' -i '#backup-log' CBOB_SLACK_CHANNEL
    if [ "$CBOB_SLACK_CHANNEL" == "" ]; then
      error 'A channel must be given'
    fi
  fi
fi

if [[ -z "$CBOB_CRUNCHY_CLUSTERS" ]]; then
  read -re -p 'Please paste the list of cluter ids separated by comma: ' -i '' CBOB_CRUNCHY_CLUSTERS
  if [ "$CBOB_CRUNCHY_CLUSTERS" == "" ]; then
    error "Invalid Cluster IDs"
  fi
fi

if [[ -z "$CBOB_RETENTION_FULL" ]]; then
  read -re -p 'How many full backups you would like to retain: ' -i '7' CBOB_RETENTION_FULL
fi

if [[ -z "$CBOB_BASE_PATH" ]]; then
  read -re -p 'Path where Crunchy Bridge Offsite Backup data will reside: ' -i '/mnt/volume_cbob' CBOB_BASE_PATH
  echo "Crunchy Bridge Offsite Backup repository path: $CBOB_BASE_PATH"
fi

info "Updating and upgrading packages"
apt update && apt upgrade -y

info "Installing dependencies"
apt install software-properties-common apt-transport-https wget curl ca-certificates gnupg jq unzip sendemail -y
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update
rm -Rf ./aws awscliv2.zip

info "Adding Postgresql repository"
if [ ! -f /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg ]; then
  info "  Dowloading Postgresql GPG"
  curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
  # wget -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /usr/share/keyrings/postgresql.gpg
fi
if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
  info "  Adding repo on sources.list"
  sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  # echo deb [arch=amd64,arm64,ppc64el signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main | tee /etc/apt/sources.list.d/postgresql.list
  apt update
fi

info "Installing main packages"
apt install -y postgresql-15 postgresql-client-15 postgresql-15-pgaudit pgbackrest

info "Installing (patched version of) pgbackrest_auto"
wget -q https://raw.githubusercontent.com/universokobana/pgbackrest_auto/patched/pgbackrest_auto
mv pgbackrest_auto /usr/local/bin/pgbackrest_auto
chown postgres:postgres /usr/local/bin/pgbackrest_auto
chmod 750 /usr/local/bin/pgbackrest_auto

info "Creating admin user with sudo privileges"
if id "admin" &>/dev/null; then
  info "  User admin already exists!"
else
  info "Choose the password for admin user"
  adduser --gecos "" admin
  usermod -aG sudo admin
  cp -r ~/.ssh /home/admin
  echo "export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8" >> /home/admin/.bashrc
  chown -R admin:admin /home/admin
fi

info "Creating pgBackRest config files & directories"
mkdir -p -m 770 /var/log/pgbackrest
chown postgres:postgres /var/log/pgbackrest
mkdir -p /etc/pgbackrest
mkdir -p /etc/pgbackrest/conf.d
chown postgres:postgres -R /etc/pgbackrest
mkdir -p /tmp/pgbackrest
chown postgres:postgres -R /tmp/pgbackrest

info "Checking if repo_path is a external volume"
if cat /etc/fstab | grep " $CBOB_BASE_PATH "; then
  info "Checking if external volume is mounted"
  if mountpoint -q $CBOB_BASE_PATH; then
    info "  External volume already mounted"
  else
    info "  Mounting external volume"
    mkdir -p $CBOB_BASE_PATH
    mount $CBOB_BASE_PATH
  fi
else
  info "  Path is not for external volume"
fi

info "Creating directory for sync (used by cbob_sync)"
mkdir -p $CBOB_BASE_PATH/crunchybridge
chmod 750 $CBOB_BASE_PATH/crunchybridge
mkdir -p $CBOB_BASE_PATH/crunchybridge/archive
chmod 750 $CBOB_BASE_PATH/crunchybridge/archive
mkdir -p $CBOB_BASE_PATH/crunchybridge/backup
chmod 750 $CBOB_BASE_PATH/crunchybridge/backup
chown postgres:postgres -R $CBOB_BASE_PATH/crunchybridge

info "Creating directory for restores (used by cbob_restore_check)"
mkdir -p $CBOB_BASE_PATH/restores
chmod 750 $CBOB_BASE_PATH/restores
chown postgres:postgres $CBOB_BASE_PATH/restores

info "Creating directory for postgresql data (used by manual restores)"
mkdir -p $CBOB_BASE_PATH/postgresql/15
chmod 750 $CBOB_BASE_PATH/postgresql/15
chown postgres:postgres -R $CBOB_BASE_PATH/postgresql

info "Creating directory for CBOB logs"
mkdir -p $CBOB_BASE_PATH/log
chmod 750 $CBOB_BASE_PATH/log
mkdir -p $CBOB_BASE_PATH/log/cbob
chmod 750 $CBOB_BASE_PATH/log/cbob
mkdir -p $CBOB_BASE_PATH/log/pgbackrest
chmod 750 $CBOB_BASE_PATH/log/pgbackrest
mkdir -p $CBOB_BASE_PATH/log/postgresql
chmod 750 $CBOB_BASE_PATH/log/postgresql
chown postgres:postgres -R $CBOB_BASE_PATH/log

# info "Adding Crunchy Bridge API Tokent to /etc/profile.d"
# echo "export CRUNCHY_API_KEY=$CBOB_CRUNCHY_API_KEY" > /etc/profile.d/cbob_crunchybridge

info "Adding Slack CLI Token to /etc/profile.d"
rm -f /etc/profile.d/slack_cli.sh
echo "export SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN" >> /etc/profile.d/slack_cli.sh
echo "export SLACK_CHANNEL=$CBOB_SLACK_CHANNEL" >> /etc/profile.d/slack_cli.sh

info "Updating environemnt variables"
export SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN
export SLACK_CHANNEL=$CBOB_SLACK_CHANNEL

info "Installing scripts e config files"
info "  Copying cbob_sync"
cp ./bin/cbob_sync /usr/local/bin/cbob_sync_pg
chown postgres:postgres /usr/local/bin/cbob_sync_pg

info "  Copying slack-cli"
cp -n ./bin/slack /usr/local/bin/slack
chown postgres:postgres /usr/local/bin/slack

info "  Creating config at /usr/local/etc/cb_offsite_backup"
echo "CBOB_CRUNCHY_API_KEY=$CBOB_CRUNCHY_API_KEY
CBOB_CRUNCHY_CLUSTERS=$CBOB_CRUNCHY_CLUSTERS
CBOB_TARGET_PATH=$CBOB_BASE_PATH/crunchybridge
CBOB_LOG_PATH=$CBOB_BASE_PATH/log/cbob" > /usr/local/etc/cb_offsite_backup
if [ -n "${CBOB_SLACK_CLI_TOKEN}" ]; then
  echo "CBOB_SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN
CBOB_SLACK_CHANNEL=$CBOB_SLACK_CHANNEL" >> /usr/local/etc/cb_offsite_backup
fi

info "  Configuring logrotate"
cp -n ./etc/logrotate.d/cb_offsite_backup /etc/logrotate.d/

info "Setting locale"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
dpkg-reconfigure -fnoninteractive locales
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

info "Stopping postgresql clusters"
cbob_postgres_stop || true

info "Generating dynamic scripts and configuration files"
TMP_PATH="/tmp/cbob-generated-configs"
mkdir -p $TMP_PATH
mkdir -p $TMP_PATH/bin

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_sync"
echo "sudo -u postgres cbob_sync_pg"  >> "$TMP_PATH/bin/cbob_sync"

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_sync_and_expire"
echo "cbob_sync"  >> "$TMP_PATH/bin/cbob_sync_and_expire"
echo "cbob_expire"  >> "$TMP_PATH/bin/cbob_sync_and_expire"

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_restore_check"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_check"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_info"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_expire"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_start"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_stop"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_restart"

port_counter=5432

IFS=',' # delimiter
read -ra CLUSTER_IDS <<< "$CBOB_CRUNCHY_CLUSTERS" # str is read into an array as tokens separated by IFS
for CLUSTER_ID in "${CLUSTER_IDS[@]}"; do # access each element of array
  IFS=''

  info "Processing cluster $CLUSTER_ID"
  CREDENTIALS_RESPONSE=$(curl -s -X POST "https://api.crunchybridge.com/clusters/$CLUSTER_ID/backup-tokens" -H "Authorization: Bearer $CBOB_CRUNCHY_API_KEY")
  STANZA=$(echo $CREDENTIALS_RESPONSE | jq -r '.stanza')
  if [ "$STANZA" == "null" ]; then
    error "Missing STANZA for CLUSTER $CLUSTER_ID. Response: $CREDENTIALS_RESPONSE"
  fi

  info "  -> Stanza $STANZA"

  info "  Initializing database for cluster $CLUSTER_ID"
  rm -rf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID
  sudo -u postgres /usr/lib/postgresql/15/bin/initdb -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID

  info "  Updating postgresql.conf cluster $CLUSTER_ID"
  mv $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.default.conf
  cp ./etc/postgresql.template.conf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  sed -i -e "s/{{stanza}}/$STANZA/g" $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  sed -i -e "s/{{port}}/$port_counter/g" $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  chown postgres:postgres $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf

  info "  Adding cluster $CLUSTER_ID to script files"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log start" >> "$TMP_PATH/bin/cbob_postgres_start"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log stop" >> "$TMP_PATH/bin/cbob_postgres_stop"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log restart" >> "$TMP_PATH/bin/cbob_postgres_restart"
  echo "sudo -u postgres pgbackrest_auto --from=$STANZA --to=$CBOB_BASE_PATH/restores/$STANZA --checkdb --clear --report --config=/etc/pgbackrest/pgbackrest.conf" >> "$TMP_PATH/bin/cbob_restore_check"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA check"  >> "$TMP_PATH/bin/cbob_check"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA info"  >> "$TMP_PATH/bin/cbob_info"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA expire"  >> "$TMP_PATH/bin/cbob_expire"

  echo "[global]
start-fast=y
log-level-file=detail
log-path=$CBOB_BASE_PATH/log/pgbackrest
repo1-retention-full=$CBOB_RETENTION_FULL
repo1-path=$CBOB_BASE_PATH/crunchybridge
" > "$TMP_PATH/pgbackrest.conf"

  echo "[$STANZA]
pg1-path=$CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID
pg1-port=$port_counter
" >> "$TMP_PATH/pgbackrest.conf"

  ((port_counter++))
done

info "Installing generated files"
chown postgres:postgres $TMP_PATH/*
chmod +x $TMP_PATH/bin/*
cp $TMP_PATH/bin/* /usr/local/bin/
cp $TMP_PATH/pgbackrest.conf /etc/pgbackrest/pgbackrest.conf

info "Adding automatic sync to cron"
rm -f /etc/cron.d/cbob_sync_and_expire
echo "# Crunchy Data Offsite Backup" >> /etc/cron.d/cbob_sync_and_expire
echo "00 06 * * * root /usr/local/bin/cbob_sync_and_expire" >> /etc/cron.d/cbob_sync_and_expire

info "Adding automatic restore to cron"
rm -f /etc/cron.d/cbob_restore_check
echo "# Crunchy Data Offsite Backup" >> /etc/cron.d/cbob_restore_check
echo "00 18 * * * root /usr/local/bin/cbob_restore_check" >> /etc/cron.d/cbob_restore_check

info "Removing tmp files"
rm -f $TMP_PATH/cbob_restore_check
rm -f $TMP_PATH/cbob_sync
rm -f $TMP_PATH/cbob_sync_and_expire
rm -f $TMP_PATH/cbob_check
rm -f $TMP_PATH/cbob_info
rm -f $TMP_PATH/cbob_expire
rm -f $TMP_PATH/cbob_postgres_start
rm -f $TMP_PATH/cbob_postgres_stop
rm -f $TMP_PATH/cbob_postgres_restart
rm -f $TMP_PATH/pgbackrest.*.conf

info "Setting chown to postgres on executables"
chown postgres:postgres /usr/local/bin/cbob*

info "Disabling postgresql service from start on boot"
systemctl disable postgresql

info "Finished Successfully!"