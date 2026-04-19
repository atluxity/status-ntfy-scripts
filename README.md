# status-ntfy-scripts

Small Bash monitoring scripts that check a few specific services or hardware states and send notifications to `ntfy.sh`.

This repository is intentionally simple. Each script is meant to be run periodically, usually from `systemd` or `cron`, and each one uses a cache file in `/var/cache` to avoid sending the same alert on every run.

## What is in this repo

- `hp-power-status.sh`: checks HP power supply presence, redundancy, and condition through `hpasmcli`.
- `hp-raid-status.sh`: checks HP RAID controller, cache, battery/capacitor, and failed physical drives through `hpssacli`.
- `website-mail-1kb-status.sh`: checks whether `http://mail.1kb.no` returns HTTP `200`.
- `hp-power-status.service`: example `systemd` unit for running `hp-power-status.sh` continuously with restart-on-exit behavior.

## ntfy topic design

The notification topic is built dynamically from:

- the local hostname, with dots replaced by dashes
- the system serial number from `dmidecode`

That produces topics like:

```text
my-host-serialnumber
```

In this setup, the topic name is not treated as a secret. That is deliberate.

The goal is:

- each machine gets its own topic automatically
- topics are specific enough that accidental collisions are unlikely
- I do not need to maintain a manual list of topic names
- I do not have to treat the topic as sensitive configuration

This is not meant to be a hard security boundary. It is just a practical way to get low-friction per-host notification channels without worrying about random outside spam in normal use.

If your threat model is different, you should use authenticated publishing or a self-hosted `ntfy` setup instead of relying on topic naming alone.

## How the scripts avoid alert spam

Each script writes state files under `/var/cache` when it sends a failure notification. On later runs, it checks the age of those files before sending the same alert again.

Current behavior:

- `hp-power-status.sh`: repeats failure alerts at most once per hour for the same condition.
- `hp-raid-status.sh`: repeats failure alerts at most once per day for the same condition.
- `website-mail-1kb-status.sh`: suppresses repeated website failure alerts for one hour.

When a problem clears, the scripts remove the relevant cache file and may send a recovery notification depending on the script logic.

## Requirements

These scripts assume a Linux host with:

- `bash`
- `curl`
- `hostname`
- `dmidecode`
- write access to `/var/cache`

Hardware-specific scripts also require:

- `/sbin/hpasmcli` for `hp-power-status.sh`
- `/sbin/hpssacli` for `hp-raid-status.sh`

The included `systemd` unit also assumes:

- `systemd`
- the script is installed at `/root/status/hp-power-status.sh`

## Running the scripts

Run them directly as root or another user with enough privileges for the hardware tools and `/var/cache`:

```bash
bash hp-power-status.sh
bash hp-raid-status.sh
bash website-mail-1kb-status.sh
```

## Using the systemd unit

The included unit is only an example for the power-supply check. It currently points to:

```text
/root/status/hp-power-status.sh
```

If you install the script somewhere else, update `ExecStart` before enabling the service.

Typical install flow:

```bash
cp hp-power-status.sh /root/status/
cp hp-power-status.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hp-power-status.service
```

## Notes

- The scripts are host-specific and operational rather than general-purpose.
- The repository currently contains shell scripts only; there is no test harness yet.
- `ntfy.sh/$TOPIC` is used directly without extra abstraction on purpose.

## License

See [LICENSE](LICENSE).
