# status-ntfy-scripts

Small operational monitoring scripts that publish status changes to ntfy.

The scripts are intentionally simple: run them from `cron`, `systemd`, or another scheduler, and they check one host-local service or hardware state. Most scripts write cache files under `/var/cache` so the same failure does not notify on every run.

## What This Repo Is For

Use this repo when you want lightweight host checks without a full monitoring stack. The scripts are useful for small servers where a direct ntfy push is enough.

Included checks:

- `hp-smart-array-status.sh`: checks HP Smart Array controller, cache, battery/capacitor, logical drives, arrays, physical drives, predictive failures, and exposed spare-drive problems with `ssacli` or `hpssacli`.
- `ipmi-platform-status.sh`: checks IPMI power supply, fan, and temperature sensor status with `ipmitool sensor`.
- `hardware-journal-status.sh`: checks recent journal entries for hardware error signatures such as EDAC, MCE, ECC, I/O errors, and thermal events.
- `filesystem-capacity-status.sh`: checks configured filesystems against warning and high used-percent thresholds.
- `ipmi-sel-status.sh`: watches new IPMI SEL entries since the previous successful run.
- `hp-power-status.sh`: compatibility wrapper for IPMI power-supply checks.
- `hp-raid-status.sh`: compatibility wrapper for HP Smart Array checks.
- `website-escnorge-status.sh`: checks whether `https://escnorge.no` returns HTTP `200`.
- `website-mail-1kb-status.sh`: checks whether `http://mail.1kb.no` returns HTTP `200`.
- `mailcow-health-status.sh`: checks the Mailcow API at `https://mail.1kb.no` and can compare the installed version with the latest upstream release.
- `digitalocean-snapshots.py`: watches a DigitalOcean droplet snapshot list and notifies when snapshots are added or removed.

Example units:

- `hp-power-status.service`
- `mailcow-health-status.service`

## Quick Start

Clone the repo on the host that should run the checks:

```bash
git clone https://github.com/atluxity/status-ntfy-scripts.git
cd status-ntfy-scripts
```

Pick the script that matches the check you want, review its defaults, then run it manually once:

```bash
bash website-mail-1kb-status.sh
```

For host-specific publishing, set the ntfy endpoint at runtime:

```bash
export NTFY_BASE_URL=http://127.0.0.1:8085
bash website-mail-1kb-status.sh
```

To use an explicit topic instead of the generated host topic:

```bash
export NTFY_TOPIC=my-server-status
bash website-mail-1kb-status.sh
```

After the script behaves as expected, schedule it with `cron`, a timer, or one of the included `systemd` service examples.

## Notification Configuration

Most scripts publish to ntfy. By default they use:

```bash
NTFY_BASE_URL=https://ntfy.sh
```

`NTFY_BASE_URL` may be set with or without a trailing slash. Both of these produce the same publish URL:

```bash
export NTFY_BASE_URL=https://ntfy.sh
export NTFY_BASE_URL=https://ntfy.sh/
```

The shell scripts support `NTFY_TOPIC`. If it is not set, they generate a topic from:

- the local hostname, with dots replaced by dashes
- the system serial number from `dmidecode`

Generated topics are lowercased, producing values like:

```text
my-host-serialnumber
```

The generated topic is meant to avoid hardcoded shared topics that can later attract spam. It is not a security boundary. For stronger control, use authenticated publishing or a self-hosted ntfy server.

## Requirements

Common requirements:

- Linux
- `bash`
- `curl`
- `hostname`
- `dmidecode` when using generated shell topics
- write access to `/var/cache` for scripts with alert throttling

Script-specific requirements:

- `hp-smart-array-status.sh` / `hp-raid-status.sh`: `ssacli` or `hpssacli`
- `ipmi-platform-status.sh` / `hp-power-status.sh`: `ipmitool`
- `hardware-journal-status.sh`: `journalctl`
- `filesystem-capacity-status.sh`: `df`
- `ipmi-sel-status.sh`: `ipmitool`
- `mailcow-health-status.sh`: `jq` and a Mailcow `ADMIN_API_KEY`
- `digitalocean-snapshots.py`: Python 3, `requests`, and a `config.json`

The included `systemd` units assume scripts are installed under `/root/status/`. Update `ExecStart` if you install them somewhere else.

## Running The Shell Checks

Run shell scripts as root, or as another user with enough permissions for hardware tools and `/var/cache`:

```bash
bash hp-power-status.sh
bash hp-raid-status.sh
bash hp-smart-array-status.sh --slot 0
bash ipmi-platform-status.sh
bash hardware-journal-status.sh --since "1 hour ago"
bash filesystem-capacity-status.sh --path / --path /home --path /mnt/backups:85:95
bash ipmi-sel-status.sh
bash website-escnorge-status.sh
bash website-mail-1kb-status.sh
```

The hardware scripts notify on failures and recoveries. Use `--no-notify`, `--check`, or `--status-only` to test locally without publishing to ntfy or updating failure/recovery cache state.

### Hardware Checks

The hardware scripts share these options:

```bash
--topic TOPIC
--cache-dir DIR
--env-file FILE
--notify
--no-notify
```

They also read the usual `NTFY_BASE_URL` and `NTFY_TOPIC` environment variables. New hardware scripts default their cache directory to:

```text
/var/cache/hardware-alerts
```

Tool availability is intentionally configurable. Missing optional tools skip cleanly; pass `--required` or set the matching `*_REQUIRED=1` variable when a host is expected to have that hardware source and missing coverage should alert.

Smart Array examples:

```bash
bash hp-smart-array-status.sh --slot 0 --required
SSACLI_BIN=/usr/sbin/ssacli bash hp-smart-array-status.sh --slot 0
```

IPMI platform examples:

```bash
bash ipmi-platform-status.sh --required
bash ipmi-platform-status.sh --power-only
bash hp-power-status.sh --required
```

Journal and filesystem examples:

```bash
HARDWARE_JOURNAL_SINCE="2 hours ago" bash hardware-journal-status.sh
bash filesystem-capacity-status.sh --path /:85:95 --path /home:85:95 --path /mnt/backups:90:95
```

`ipmi-sel-status.sh` stores the last seen SEL event in the cache directory. On the first run it initializes a baseline instead of alerting on historical events.

## Mailcow Check

`mailcow-health-status.sh` reads configuration from environment variables and, by default, from a `.env` file placed next to the script. Environment variables take precedence over values in the file.

Required:

```bash
export ADMIN_API_KEY=your-mailcow-admin-api-key
```

Optional:

```bash
export MAILCOW_URL=https://mail.1kb.no
export STRICT_LATEST_VERSION=1
export MAX_CACHE_AGE=3600
export NTFY_BASE_URL=https://ntfy.sh
export NTFY_TOPIC=my-explicit-topic
```

By default, the Mailcow check reports only through its exit status and stdout. Enable ntfy notifications with `--notify`:

```bash
bash mailcow-health-status.sh --notify
```

Use an explicit env file with:

```bash
bash mailcow-health-status.sh --notify --env-file /etc/default/mailcow-health-status
```

`--check` and `--status-only` are accepted as explicit no-notify modes.

## DigitalOcean Snapshot Check

`digitalocean-snapshots.py` expects `config.json` in the current working directory:

```json
{
  "api_token": "your-digitalocean-api-token",
  "droplet_id": "123456789",
  "ntfy_topic": "my-snapshot-topic"
}
```

Run it from the directory containing `config.json`:

```bash
python3 digitalocean-snapshots.py
```

The script stores previous snapshot IDs in `snapshot_state.txt` in the current working directory. It sends notifications only when snapshots are added or removed.

To publish through a self-hosted ntfy endpoint:

```bash
NTFY_BASE_URL=http://127.0.0.1:8085 python3 digitalocean-snapshots.py
```

## Scheduling

Cron example for the website check:

```cron
*/5 * * * * cd /root/status && NTFY_BASE_URL=http://127.0.0.1:8085 ./website-mail-1kb-status.sh
```

Cron example for Mailcow notifications:

```cron
*/10 * * * * /root/status/mailcow-health-status.sh --notify --env-file /etc/default/mailcow-health-status
```

The included service units are long-running restart loops. They currently point to:

```text
/root/status/hp-power-status.sh
/root/status/mailcow-health-status.sh
```

Typical Mailcow service setup:

```bash
install -d /root/status
cp mailcow-health-status.sh /root/status/
cp mailcow-health-status.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now mailcow-health-status.service
```

Create `/etc/default/mailcow-health-status` before starting the service:

```bash
ADMIN_API_KEY=your-mailcow-admin-api-key
MAILCOW_URL=https://mail.1kb.no
STRICT_LATEST_VERSION=1
MAX_CACHE_AGE=3600
NTFY_BASE_URL=http://127.0.0.1:8085
```

Typical HP power service setup:

```bash
install -d /root/status
cp hp-power-status.sh /root/status/
cp hp-power-status.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hp-power-status.service
```

## Alert Throttling

Scripts that notify on repeated failures use cache files to avoid noisy repeats:

- New hardware scripts: repeat a failure at most once per `MAX_CACHE_AGE`, defaulting to one hour.
- `hp-power-status.sh`: compatibility wrapper around `ipmi-platform-status.sh --power-only`.
- `hp-raid-status.sh`: compatibility wrapper around `hp-smart-array-status.sh`.
- `website-escnorge-status.sh`: suppresses repeated website failure alerts for one hour.
- `website-mail-1kb-status.sh`: suppresses repeated website failure alerts for one hour.
- `mailcow-health-status.sh`: suppresses repeated Mailcow response/version alerts for `MAX_CACHE_AGE`, defaulting to one hour.

When a problem clears, the relevant cache file is removed. Some scripts also send a recovery notification.

## Notes For Operators

- Review each script before deploying it; several defaults are intentionally specific to the hosts and services they were written for.
- Prefer runtime configuration through environment variables or env files. Do not patch source files after checkout just to change ntfy endpoints or topics.
- Keep scheduling, host-specific topics, thresholds, and systemd unit policy in the deployment repository. This repo owns reusable script logic.
- If you publish to public `ntfy.sh`, avoid simple shared topics. Use generated per-host topics, explicit unique topics, authenticated publishing, or a self-hosted endpoint.

## Testing

Run shell syntax checks:

```bash
bash -n *.sh tests/run-hardware-checks.sh
```

Run the self-contained hardware parser tests:

```bash
tests/run-hardware-checks.sh
```

## License

See [LICENSE](LICENSE).
