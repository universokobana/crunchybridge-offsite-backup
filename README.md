# Crunchy Bridge Offsite Backup

This script sync the AWS S3 backup repo from [Crunchy Bridge](https://crunchybridge.com/) to a local path and use it as the Stanza for [PgBackRest](https://pgbackrest.org/).

This script is intended to be installed on a host that has PgBackRest installed. For a reference and how to setup this server, please refer to https://www.cybertec-postgresql.com/en/remote-backup-and-restore-with-pgbackrest/

## Installation

Clone this project:

    $ git clone https://github.com/UniversoKobana/crunchybridge-offsite-backup.git

Go to the created directory:

    $ cd crunchybridge-offsite-backup

Run the installation script:

    $ sudo ./install.sh

For security reason, read the [installation script source before](https://github.com/universokobana/crunchybridge-offsite-backup/blob/main/install.sh).

## Running

The script will automatically run once a day, but if you need to invoke manually, run:

    $ sudo cbob_sync
## Configuration

### Config File

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
CBOB_HEARTBEAT_URL=https://myserver.com/path-to-post
```

### Environment Variables

You can set the environment variables using export, ex:

    $ export CBOB_CRUNCHY_API_KEY=xxx

Or passing the variables in the command line, ex:

    $ CBOB_CRUNCHY_API_KEY=xxx /usr/local/bin/crunchybridge_offsite_backup 

## Options

You can set the following options:

### API Key

`CBOB_CRUNCHY_API_KEY`

The token of Crunchy Bridge API.
To create an API key go to: https://crunchybridge.com/account/api-keys

### Clusters

`CBOB_CRUNCHY_CLUSTERS`

List of IDs of clusters separated by comma. Ex: `xxxx,yyyy`

### Target Path

`CBOB_TARGET_PATH`

Path where the files will be synced. Ex: `/mnt/crunchy_bridge_backups/backups`

### Log Path

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

### Dry run

`CBOB_DRY_RUN`

When set the sync will not execute, good to use at development time

### Slack Notification

To enable Slack notification you must set the following variables:

`CBOB_SLACK_CLI_TOKEN` with the desired token.

If you want to post from your own account, you need a legacy API token which can be found
[here](https://api.slack.com/custom-integrations/legacy-tokens). If you want to post from a
slackbot, [create one here](https://my.slack.com/services/new/bot). Otherwise, you can create an
app with a [Slack API token](https://api.slack.com/web).

`CBOB_SLACK_CHANNEL` with the channel name ehre the messages will be posted, ex: `#backup-log`

It uses the [slack-cli](https://github.com/rockymadden/slack-cli) that is bundled with this installation.
### Heartbeat

You can add a `CBOB_HEARTBEAT_URL` to the script so a request gets sent every time a backup is made.

### Timezone

The default timezone is `UTC`. To use your [preferred timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the filename timestamp, set the `TZ` variable when calling the command:

    $ TZ=America/Los_Angeles ./bin/backup

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