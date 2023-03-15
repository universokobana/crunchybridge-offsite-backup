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
    read -re -p 'Slack channel to send logs: ' -i '#backup_log' CBOB_SLACK_CHANNEL
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

if [[ -z "$CBOB_BASE_PATH" ]]; then
  read -re -p 'Path where Crunchy Bridge Offsite Backup data will reside: ' -i '/mnt/volume_pgbackrest_backups' CBOB_BASE_PATH
  echo "Crunchy Bridge Offsite Backup repository path: $CBOB_BASE_PATH"
fi

# info "Creating admin user"
# if id "admin" &>/dev/null; then
#   info "  User admin already exists!"
# else
#   sudo useradd admin
# fi

info "Adding Postgresql repository"
if [[ -z /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg ]]; then
  info "  Dowloading Postgresql GPG"
  sudo apt install -y curl ca-certificates gnupg
  curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
fi
if [[ $(cat /etc/apt/sources.list.d/pgdg.list |grep apt.postgresql.org) == "" ]]; then
  info "  Adding repo on source list"
  sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  sudo apt update
fi

info "Installing Packages"
sudo apt install -y postgresql-15 postgresql-client-15 postgresql-15-pgaudit libdbd-pg-perl pgbackrest

info "Installing pgbackrest_auto with the latest version"
sudo wget -q https://raw.githubusercontent.com/universokobana/pgbackrest_auto/patched/pgbackrest_auto
sudo mv pgbackrest_auto /usr/local/bin/pgbackrest_auto
sudo chown postgres:postgres /usr/local/bin/pgbackrest_auto
sudo chmod 750 /usr/local/bin/pgbackrest_auto

info "Creating pgBackRest config files & directories"
sudo mkdir -p -m 770 /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest
sudo mkdir -p /etc/pgbackrest/conf.d
sudo chown postgres:postgres -R /etc/pgbackrest
sudo mkdir -p /tmp/pgbackrest
sudo chown postgres:postgres -R /tmp/pgbackrest

info "Checking if repo_path is a external volume"
if cat /etc/fstab | grep " $CBOB_BASE_PATH "; then
  info "Checking if external volume is mounted"
  if mountpoint -q $CBOB_BASE_PATH; then
    info "  External volume already mounted"
  else
    info "  Mounting external volume"
    mkdir -p $CBOB_BASE_PATH
    sudo mount $CBOB_BASE_PATH
  fi
else
  info "  Path is not for external volume"
fi

info "Creating directory for Crunchy Bridge sync"
sudo mkdir -p $CBOB_BASE_PATH/crunchybridge
sudo chmod 750 $CBOB_BASE_PATH/crunchybridge
sudo chown postgres:postgres -R $CBOB_BASE_PATH/crunchybridge

info "Creating directory for restores (used by pgbackrest_auto)"
sudo mkdir -p $CBOB_BASE_PATH/restores
sudo chmod 750 $CBOB_BASE_PATH/restores
sudo chown postgres:postgres -R $CBOB_BASE_PATH/restores

info "Creating directory for postgresql data"
sudo mkdir -p $CBOB_BASE_PATH/postgresql/15
sudo chmod 750 $CBOB_BASE_PATH/postgresql/15
sudo chown postgres:postgres -R $CBOB_BASE_PATH/postgresql

info "Creating directory for pgbackrest configs"
sudo mkdir -p $CBOB_BASE_PATH/pgbackrest
sudo chmod 750 $CBOB_BASE_PATH/pgbackrest
sudo chown postgres:postgres -R $CBOB_BASE_PATH/pgbackrest

info "Creating directory for CBOB logs"

sudo mkdir -p $CBOB_BASE_PATH/log
sudo chmod 750 $CBOB_BASE_PATH/log
sudo mkdir -p $CBOB_BASE_PATH/log/cbob
sudo chmod 750 $CBOB_BASE_PATH/log/cbob
sudo mkdir -p $CBOB_BASE_PATH/log/pgbackrest
sudo chmod 750 $CBOB_BASE_PATH/log/pgbackrest
sudo mkdir -p $CBOB_BASE_PATH/log/postgresql
sudo chmod 750 $CBOB_BASE_PATH/log/postgresql
sudo chown postgres:postgres -R $CBOB_BASE_PATH/log

info "Adding Crunchy Bridge API Tokent to /etc/profile.d"
sudo echo "export CRUNCHY_API_KEY=$CBOB_CRUNCHY_API_KEY" > /etc/profile.d/cbob_crunchybridge

info "Installing scripts e config files"
info "  Copying ./bin/cbob_sync to /usr/local/bin/cbob_sync"
sudo cp ./bin/cbob_sync /usr/local/bin/cbob_sync
sudo chown postgres:postgres /usr/local/bin/cbob_sync

info "  Copying ./bin/slack to /usr/local/bin/slack"
sudo cp -n ./bin/slack /usr/local/bin/slack
sudo chown postgres:postgres /usr/local/bin/slack

info "  Creating config at /usr/local/etc/cb_offsite_backup"
echo "CBOB_CRUNCHY_API_KEY=$CBOB_CRUNCHY_API_KEY
CBOB_CRUNCHY_CLUSTERS=$CBOB_CRUNCHY_CLUSTERS
CBOB_TARGET_PATH=$CBOB_BASE_PATH
CBOB_LOG_PATH=$CBOB_BASE_PATH/log/cbob" > /usr/local/etc/cb_offsite_backup
if [ -n "${CBOB_SLACK_CLI_TOKEN}" ]; then
  echo "CBOB_SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN
  CBOB_SLACK_CHANNEL=$CBOB_SLACK_CHANNEL" >> /usr/local/etc/cb_offsite_backup
fi

info "  Copying ./etc/logrotate.d/cb_offsite_backup to /etc/logrotate.d/"
sudo cp -n ./etc/logrotate.d/cb_offsite_backup /etc/logrotate.d/

info "  Linking /usr/local/bin/crunchybridge_offsite_backup to /etc/cron.daily"
sudo ln -sf /usr/local/bin/crunchybridge_offsite_backup /etc/cron.daily/crunchybridge_offsite_backup

info "Stopping postgresql clusters"
cbob_postgres_stop || true

info "Generating dynamic scripts and configuration files"
TMP_PATH="/tmp/cbob-generated-configs"
mkdir -p $TMP_PATH
mkdir -p $TMP_PATH/bin

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_cron"
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
  info "  -> Stanza $STANZA"

  info "  Initializing database for cluster $CLUSTER_ID"
  sudo -u postgres rm -rf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID
  sudo -u postgres /usr/lib/postgresql/15/bin/initdb -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID

  info "  Updating postgresql.com cluster $CLUSTER_ID"
  sudo mv $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.default.conf

  sudo cp ./etc/postgresql.template.conf $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  sed -i -e "s/{{stanza}}/$STANZA/g" $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  sed -i -e "s/{{port}}/$port_counter/g" $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf
  sudo chown postgres:postgres $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID/postgresql.conf

  info "  Adding cluster $CLUSTER_ID to script files"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log start" >> "$TMP_PATH/bin/cbob_postgres_start"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log stop" >> "$TMP_PATH/bin/cbob_postgres_stop"
  echo "sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-15-$CLUSTER_ID.log restart" >> "$TMP_PATH/bin/cbob_postgres_restart"
  echo "pgbackrest_auto --from=$STANZA --to=$CBOB_BASE_PATH/restores/$STANZA --checkdb --clear --config=$CBOB_BASE_PATH/pgbackrest/pgbackrest.$STANZA.full.conf" >> "$TMP_PATH/bin/cbob_cron"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA check --config=$CBOB_BASE_PATH/pgbackrest/pgbackrest.$STANZA.full.conf"  >> "$TMP_PATH/bin/cbob_check"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA info --config=$CBOB_BASE_PATH/pgbackrest/pgbackrest.$STANZA.full.conf"  >> "$TMP_PATH/bin/cbob_info"
  echo "sudo -u postgres pgbackrest --stanza=$STANZA expire --config=$CBOB_BASE_PATH/pgbackrest/pgbackrest.$STANZA.full.conf"  >> "$TMP_PATH/bin/cbob_expire"

  echo "[global]
start-fast=y
log-level-file=detail
log-path=$CBOB_BASE_PATH/log/pgbackrest
repo1-retention-full=7
" > "$TMP_PATH/pgbackrest.conf"

  echo "[$STANZA]
pg1-path=$CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID
pg1-port=$port_counter
repo-path=$CBOB_BASE_PATH/crunchybridge/$CLUSTER_ID/$STANZA
" > "$TMP_PATH/pgbackrest.$STANZA.part.conf"

  echo "[$STANZA]
pg1-path=$CBOB_BASE_PATH/postgresql/15/$CLUSTER_ID
pg1-port=$port_counter

[global]
start-fast=y
log-level-file=detail
log-path=$CBOB_BASE_PATH/log/pgbackrest
repo1-retention-full=7
repo1-path=$CBOB_BASE_PATH/crunchybridge/$CLUSTER_ID/$STANZA
" > "$TMP_PATH/pgbackrest.$STANZA.full.conf"

  ((port_counter++))
done

info "Installing generated files"
sudo chown postgres:postgres $TMP_PATH/*
sudo chmod +x $TMP_PATH/bin/*
sudo cp $TMP_PATH/bin/* /usr/local/bin/
sudo cp $TMP_PATH/pgbackrest.conf /etc/pgbackrest/pgbackrest.conf
sudo cp $TMP_PATH/pgbackrest.*.part.conf /etc/pgbackrest/conf.d/
sudo cp $TMP_PATH/pgbackrest.*.full.conf $CBOB_BASE_PATH/pgbackrest/

info "Adding automatic restore to cron"
rm -f /etc/cron.d/cbob
sudo echo "# Crunchy Data Offsite Backup" >> /etc/cron.d/cbob
sudo echo "00 16 * * * postgres /usr/local/bin/cbob_cron" >> /etc/cron.d/cbob

info "Removing tmp files"
rm -f $TMP_PATH/cbob_cron
rm -f $TMP_PATH/cbob_check
rm -f $TMP_PATH/cbob_info
rm -f $TMP_PATH/cbob_expire
rm -f $TMP_PATH/cbob_postgres_start
rm -f $TMP_PATH/cbob_postgres_stop
rm -f $TMP_PATH/cbob_postgres_restart
rm -f $TMP_PATH/pgbackrest.*.conf

info "Setting chown to postgres"
sudo chown postgres:postgres /usr/local/bin/cbob*

info "Disabling postgresql service from start on boot"
sudo systemctl disable postgresql

info "Starting postgresql clusters"
cbob_postgres_start
