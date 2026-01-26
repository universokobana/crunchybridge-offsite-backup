# Crunchy Bridge Off-site Backup (CBOB)

This project syncs the AWS S3 backup repo from [Crunchy Bridge](https://crunchybridge.com/) to a local path as an off-site backup, use it as the [pgBackRest](https://pgbackrest.org/) repository and runs [pgbackrest_auto](https://github.com/vitabaks/pgbackrest_auto) to check the integrity of each Stanza.

An off-site backup is a copy of a business production system data that is stored in a different location than the production system, ussualy in a third-party provider. If you use AWS, you should do off-site backup to Digital Ocean, for example. Doesn't make sense to backup Heroku data (that uses AWS) in AWS S3 for example, because in that case you have a unique point of failure which is AWS. The goal is to have complete control of your data and the restore process without depending on your main provider.

Altough this script was created specific for Crunchy Bridge it can bem adapted to work with any provider that work with pgBackRest.

## What's New in v2.1

- **pgBackRest 2.58+ Required**: Native STS token refresh eliminates manual credential management
- **Simplified Codebase**: Removed ~70 lines of token refresh workaround code
- **More Reliable Long Syncs**: pgBackRest handles token expiration automatically

## What's New in v2

- **Unified CLI**: Single `cbob` command with subcommands for all operations
- **Docker Support**: Run CBOB in containers with docker-compose
- **S3 Destination Support**: Sync backups directly to S3-compatible storage (DigitalOcean Spaces, Hetzner, MinIO, etc.)
- **Metrics & Monitoring**: Performance tracking and heartbeat monitoring
- **Enhanced Security**: Input validation and secure credential storage
- **Parallel Operations**: Sync multiple clusters simultaneously
- **Structured Logging**: JSON logging support for log aggregation
- **Multi-Region Replication**: Cross-region and cross-cloud backup replication
- **PostgreSQL 18 Support**: Full compatibility with PostgreSQL 18

See [MIGRATION.md](MIGRATION.md) for upgrading from v1.

## Quick Start with Docker

```bash
# Clone the repository
git clone https://github.com/UniversoKobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup

# Copy and configure environment
cp .env.example .env
# Edit .env with your Crunchy Bridge API key, cluster IDs, and destination settings

# Start with Docker Compose
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs cbob
```

See [docs/DOCKER.md](docs/DOCKER.md) for detailed Docker usage.

## CBOB Sync

This is the main script that sync from Crunchy Bridge AWS S3 to local path.

### Installation

This script is intended to be installed on a host that has pgBackRest installed. For a reference and how to setup this server, please refer to https://www.cybertec-postgresql.com/en/remote-backup-and-restore-with-pgbackrest/

1.  Clone this project:

        $ git clone https://github.com/UniversoKobana/crunchybridge-offsite-backup.git

2.  Go to the created directory:

        $ cd crunchybridge-offsite-backup

3.  Run the installation script:

        $ sudo ./install.sh

For security reason, read the [installation script source before](https://github.com/universokobana/crunchybridge-offsite-backup/blob/main/install.sh).

After installation finishes you an remove the source

    $ cd .. && rm -Rf crunchybridge-offsite-backup

### Running

With v2 CLI:

    $ sudo -u postgres cbob sync
    
    # With options
    $ sudo -u postgres cbob sync --parallel 4 --dry-run
    
    # Specific clusters
    $ sudo -u postgres cbob sync --cluster cluster1 --cluster cluster2

Legacy v1 command (if not migrated):

    $ sudo cbob_sync

### Configuration

#### Via Config File

The script tries to load the configuration file from `CBOB_CONFIG_FILE` and if it is not defined from the folowing paths, in that order:
`~/.cb_offsite_backup`
`/usr/local/etc/cb_offsite_backup`
`/etc/cb_offsite_backup`

If no files are found it expect to have the environment variables set.

The installation script copies the example file to `/usr/local/etc/cb_offsite_backup`. Edit this file to set the variables:

```
CBOB_CRUNCHY_API_KEY=xxx
CBOB_CRUNCHY_CLUSTERS=xxx
CBOB_DRY_RUN=true
CBOB_TARGET_PATH=/mnt/crunchy_bridge_backups
CBOB_LOG_PATH=/var/log/
CBOB_SLACK_CLI_TOKEN=xoxb-9999999999-9999999999999-xxxxxxxxxxxxxxxxxxxxxxxx
CBOB_SLACK_CHANNEL=#backup-log
CBOB_SYNC_HEARTBEAT_URL=https://myserver.com/path-to-post
```

#### Via Environment Variables

You can set the environment variables using export, ex:

    $ export CBOB_CRUNCHY_API_KEY=xxx

Or passing the variables in the command line, ex:

    $ CBOB_CRUNCHY_API_KEY=xxx /usr/local/bin/crunchybridge_offsite_backup

### Configuration Options

You can set the following options:

#### API Key

`CBOB_CRUNCHY_API_KEY`

The token of Crunchy Bridge API.
To create an API key go to: https://crunchybridge.com/account/api-keys

#### Clusters

`CBOB_CRUNCHY_CLUSTERS`

List of IDs of clusters separated by comma. Ex: `xxxx,yyyy`

#### Target Path

`CBOB_TARGET_PATH`

Path where the files will be synced. Ex: `/mnt/crunchy_bridge_backups/backups`

#### Log Path

`CBOB_LOG_PATH`

Optional. Default is `/var/log`.
The LOG_PATH should contain only the directory, without the name of file.
A file called `cb_offsite_backup.log` will be created inside this directory.

If you want to use logrotate, add the file `/etc/logrotate.d/cb_offsite_backup` with the following content:

```
/var/log/cb_offsite_backup.log {
  weekly
  rotate 10
  copytruncate
  delaycompress
  compress
  notifempty
  missingok
  su admin admin
}
```

It is considering that your `CBOB_LOG_PATH` if set to `/var/log` and the user you are using to run the script is `admin`.

#### Dry run

`CBOB_DRY_RUN`

When set the sync will not execute, good to use at development time

#### Slack Notification

To enable Slack notification you must set the following variables:

`CBOB_SLACK_CLI_TOKEN` with the desired token.

If you want to post from your own account, you need a legacy API token which can be found
[here](https://api.slack.com/custom-integrations/legacy-tokens). If you want to post from a
slackbot, [create one here](https://my.slack.com/services/new/bot). Otherwise, you can create an
app with a [Slack API token](https://api.slack.com/web).

`CBOB_SLACK_CHANNEL` with the channel name ehre the messages will be posted, ex: `#backup-log`

It uses the [slack-cli](https://github.com/rockymadden/slack-cli) that is bundled with this installation.

#### Heartbeat

You can add a `CBOB_SYNC_HEARTBEAT_URL` to the script so a request gets sent every time a backup is made.

#### Timezone

The default timezone is `UTC`. To use your [preferred timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the filename timestamp, set the `TZ` variable when calling the command:

    $ TZ=America/Los_Angeles ./bin/backup

## CBOB Full Check

This is the full solution that sync the Crunchy Bridge AWS S3 repo to local path and runs pgbackrest_auto to check the integrity of each Stanza.

The source is tested on a Debian 11 running on Digital Ocean.

⚠️ Do not run setup script on your local machine or on a PostgreSQL host ⚠️

### Setup

The setup is written for Digital Ocean but you can use it on any linux server.

1.  [Create a new droplet](https://cloud.digitalocean.com/droplets/new) to host the solution

    1. Choose the image `Debian 11 x64`
    2. Choose the size, we recommend Basic > Premium Intel with at least 2 vCPUs and 2GB RAM. Don't worry about disk space (SSD) we will setup a volume to host the backup.
    3. Choose Authentication Method, we recommend `SSH Key` for security.
    4. Choose the hostname, we use `crunchybridge-offsite-backup`

2.  Wait for the Droplet to finish setup and take note of the IP of the new virtual machine. Let's say it is `999.888.777.666` for our examples.

3.  [Create a new volume](https://cloud.digitalocean.com/volumes/new) to be used as the storage for all backups

    1. Choose the size, we recommend at least 20 times the current size of all clusters. This is because we will sync the entire pgBackRest repository that contains all backups Crunchy Bridge has for each cluster.
    2. Select the droptlet to attach choosing the one created on the step below (`crunchybridge-offsite-backup`)
    3. Name the volume, we recommend naming `volume-cbob` and it will be mounted at `/mnt/volume_cbob`
    4. Choose Automatically Format & Mount
    5. Choose the `XFS Filesystem`

4.  Wait for the volume to be created and mounted.

5.  Login into the server, example:

        $ ssh root@999.888.777.666

6.  Install git

        $ apt update && apt install -y git

7.  Clone the project

        $ git clone https://github.com/UniversoKobana/crunchybridge-offsite-backup.git

8.  Go to the created directory:

        $ cd crunchybridge-offsite-backup

9.  Run the setup script:

⚠️ Do not run setup script on your local machine or on a PostgreSQL host ⚠️

    $ ./setup.sh

Note that the setup script is different from installation script.

🔑 Take note of admin password!

1.  Ready! You now can connect to the virtual machine as admin user, example:

        $ ssh admin@999.888.777.666

### Re-configuring

If you need to reconfigure to change the api key, change the slack token or add another cluster you can run setup again.

### Running Manually

#### Sync

To sync Crunchy Bridge pgBackRest full respository from AWS S3 to local path

    $ cbob_sync

#### Sync and Expire

To sync AWS S3 repository and expire old backups based on the configuration on setup

    $ cbob_sync_and_expire

#### Restore Check

To check the integrity os all backups. It will run pgbackrest_auto for each Stanza.

    $ cbob_restore_check

#### Info

To get info from all Stanzas

    $ cbob_info

#### Expire

To expire all backups from local repository keeping the last 7
It is configured on `/etc/pgbackrest/pgbackrest.conf`

    $ cbob_expire

### Restoring to local database

You can also restore all backups to local databases to do whaterver you need.
It is configured out of the box and the PostgreSQL data directory is configured at `/mnt/volume_cbob/postgresql/18/[cluster]` where `[cluster]` is the id of each cluster named by Crunchy Bridge.

We provide the following scripts to help starting and stopping all clusters at same time.

_cbob_postgres_initdb_ - create postgresql data directory for each cluster. It is already called on setup and you don't need to call it again, unless you are hacking something.

_cbob_postgres_start_ - starts all clusters, one for each stanza in a different port

_cbob_postgres_stop_ - stop all clusters

_cbob_postgres_restart_ - restart all clusters

To restore the backup of one cluster, run the following steps:

1.  Stop all clusters

        $ cbob_postgres_stop

2.  Get the repository info just to confirm that pgBackRest is running correctly

        $ sudo -u postgres pgbackrest --stanza=xxxxx info

(where `xxxxx` is the stanza id)

3.  Restore the backup for one specific stanza

        $ sudo -u postgres pgbackrest --stanza=xxxxx restore --force

(where `xxxxx` is the stanza id)

4.  Start all clusters

        $ cbob_postgres_start

5.  Ready!

It is possible that the server won't start for an incompatibility from postgresql instalation and the conf that was restored. If this problem occurs refer to the log.

Tip, run the following command to set the CLUSTER variable and make it easy to work with directories.

    $ export CLUSTER=xxxx

Now run:

    $ sudo tail /mnt/volume_cbob/log/postgresql/postgresql-18-$CLUSTER.log

If needed edit the postgresql configuration for this stanza by running:

    $ sudo nano -w /mnt/volume_cbob/postgresql/18/$CLUSTER/postgresql.conf

## Common Problems

1.  **FATAL: could not access file "pgpodman": No such file or directory**

    Edit `postgresql.conf` and remove `pgpodman` from `shared_library` list.

1.  **FATAL: private key file "server.key" has group or world access**

        $ sudo chmod 0600 /mnt/volume_cbob/postgresql/18/$CLUSTER/server.key

1.  **FATAL: could not map anonymous shared memory: Cannot allocate memory**

    Edit `postgresql.conf` and change the value of `max_connections` to 10.

Remember, you need to do it for each cluster you configured.

### Cron

The setup script automatically install the scripts on crontab.
Everyday the script `cbob_sync_and_expire` will run at 6AM UTC (as configured on `/etc/cron.d/cbob_sync_and_expire`) to sync the repositories and `cbob_restore_check` will run at 6PM UTC (as configured on `/etc/cron.d/cbob_restore_check`) to validate all backups.

If configured correctly, the output of both scripts will be sent do Slack.

## Receiving Report by Email

If you want to receive the restore_check report by email, create the following file with content below:

`/etc/profile.d/pgbackrest_config.sh`

```
export PGBACKREST_AUTO_SMTP_SERVER="localhost:25"
export PGBACKREST_AUTO_MAIL_FROM="me@example.com"
export PGBACKREST_AUTO_MAIL_TO="logs@example.com"
export PGBACKREST_AUTO_ATTACH_REPORT="true"
```

### Logs

All logs are saved at `/mnt/volume_cbob/log`.

- _PostgreSQL_ - `/mnt/volume_cbob/log/postgresql`
- _pgBackRest_ - `/mnt/volume_cbob/log/pgbackrest`
- _Off-site Backup Scripts_ - `/mnt/volume_cbob/log/cbob`

## S3 Destination Support

CBOB v2 can sync backups directly to S3-compatible storage:

```bash
# Configuration example for S3 destination
CBOB_DEST_TYPE=s3
CBOB_DEST_ENDPOINT=https://fra1.digitaloceanspaces.com
CBOB_DEST_BUCKET=my-cbob-backups
CBOB_DEST_ACCESS_KEY=your-access-key
CBOB_DEST_SECRET_KEY=your-secret-key
CBOB_DEST_REGION=fra1
```

Supported providers:
- DigitalOcean Spaces
- Hetzner Object Storage
- MinIO
- Any S3-compatible storage

## Monitoring & Metrics

CBOB v2 provides monitoring capabilities:

- Backup sync duration and success rate
- Storage usage per cluster
- Heartbeat URL notifications
- Slack notifications
- Structured JSON logging

Access status via:
- CLI: `cbob info`
- CLI: `cbob config show`
- Logs: `/var/log/cbob/`

## Testing

Run the test suite:

```bash
# Unit tests
bash tests/test_common.sh

# Integration tests
bash tests/test_integration.sh

# Performance tests
bash tests/test_performance.sh
```

## To be done

- [x] Implement parameters on cbob_sync to make it more versatile
- [x] Move content from cbob\_\* scripts to configuration files
- [x] Create one script called `cbob` with all parameters, and delete cbob\_\*
- [x] Multi-region replication support
- [x] S3 destination support
- [ ] Kubernetes Helm charts
- [ ] Web UI for backup management

PRs are welcome!

## Author

[Rafael Lima](https://github.com/rafaelp) working for [Kobana](https://github.com/UniversoKobana)

## License

The MIT License (MIT)

Copyright (c) 2023 KOBANA INSTITUICAO DE PAGAMENTO LTDA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
