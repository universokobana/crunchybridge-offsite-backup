#!/bin/bash

echo "Copying ./bin/cbob_sync to /usr/local/bin/cbob_sync"
sudo cp ./bin/cbob_sync /usr/local/bin/cbob_sync

echo "Copying ./bin/slack to /usr/local/bin/slack"
sudo cp -n ./bin/slack /usr/local/bin/slack

echo "Copying ./etc/cb_offsite_backup_example.env to /usr/local/etc/cb_offsite_backup"
sudo cp -n ./etc/cb_offsite_backup_example.env /usr/local/etc/cb_offsite_backup

echo "Copying ./etc/logrotate.d/cb_offsite_backup to /etc/logrotate.d/"
sudo cp -n ./etc/logrotate.d/cb_offsite_backup /etc/logrotate.d/

echo "Linking /usr/local/bin/cbob_sync to /etc/cron.daily"
sudo ln -sf /usr/local/bin/cbob_sync /etc/cron.daily/cbob_sync

echo "Done!"