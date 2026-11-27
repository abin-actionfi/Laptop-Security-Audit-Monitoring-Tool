# Laptop Security Audit & Monitoring Tool

A lightweight Bash tool that audits the security and health of an Ubuntu laptop, flags suspicious activity, and saves a report with findings and recommendations. It runs unattended on a schedule, and its results feed a Grafana dashboard.

> **Authorised use only.** The tool lists running processes and scans `/home`. Run it only on systems you own or have written permission to audit. Collect only security and health data.

---

## What it does

Every run performs read-only checks. Each check gives a verdict:

| Verdict | Meaning |
|---|---|
| `[OK]` | Check passed |
| `[WARN]` | Worth reviewing |
| `[CRIT]` | Needs attention |

Every `WARN` and `CRIT` is also written to an alert log. At the end, a summary shows the counts, a **Critical Findings** list, and numbered **Recommendations**. The counts, the critical findings and the report name are also written to a metrics file that Prometheus reads (see "Dashboards and alerts").

### Checks

| Area | Check | Verdicts |
|---|---|---|
| System info | OS, CPU, memory, disk, installed package count | Info only |
| Resources | CPU, RAM and disk usage against a threshold (default 80%) | OK / WARN |
| Firewall | `ufw` missing or inactive | OK / WARN / CRIT |
| SSH | `PermitRootLogin yes` is CRIT, password login enabled is WARN. Reads `sshd_config` and `sshd_config.d/*.conf`. If no SSH server is installed, the check passes. | OK / WARN / CRIT |
| Updates | Pending updates via `apt-check`. Security updates are CRIT, other updates WARN. | OK / WARN / CRIT |
| Open ports | Ports listening on all interfaces (`0.0.0.0`, `[::]` or `*`) | WARN per port |
| Services | Running services that are often unneeded (default list: avahi-daemon, cups-browsed, bluetooth, gnome-remote-desktop, snapd) | WARN per service |
| Permissions | World-writable files in the configured folders (default `/etc`, `/usr`, `/var`) | WARN per file |
| Hidden files | Hidden executables in the configured folders (default `/tmp`, `/var/tmp`, `/dev/shm`, `/root`, `/home`) | WARN per file |
| Processes | Processes running from `/tmp`, `/var/tmp`, `/dev/shm`, `~/Downloads`, or whose executable was deleted | WARN per process |
| Cron | Counts active system cron entries (OK). Entries that run from temp folders are CRIT. | OK / CRIT |
| File integrity | SHA-256 hashes of the monitored files (default `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/hosts`, `/etc/crontab`) compared with a saved baseline | OK / CRIT |

The tool is **non-destructive**. Checks only read. The one deletion is its own old reports (see "What the tool writes").

### How one run works

1. `audit.sh` loads the helper functions and modules, then stops unless it runs as root.
2. It loads `config/audit.conf` and stops with an error if the file is missing.
3. If started with `--rebaseline`, it resets the integrity baseline and exits (no audit).
4. It deletes its own reports older than the configured number of days.
5. It runs every check. Output goes to the screen and into a new report file at the same time.
6. It prints the summary, critical findings and recommendations.
7. It writes the metrics file for Prometheus.

---

## Requirements

- Ubuntu or Debian (uses `dpkg`, `apt-check` and `/etc/os-release`). Tested on Ubuntu 24.04.
- systemd and logrotate (both standard on Ubuntu)
- `git`, to download the tool
- `sudo` access for whoever installs it
- Optional, for the dashboard: node_exporter, Prometheus and Grafana (see "Dashboards and alerts"). Without node_exporter's folder, the audit still runs and skips the metrics file.

---

## Project layout

```
laptop-security-audit/
├── audit.sh                    main script, run as root
├── install.sh                  installs to /opt and schedules the audit
├── config/
│   └── audit.conf              settings that IT can change
├── lib/
│   └── common.sh               verdict helpers, counters, alerts, summary, metrics file
├── modules/
│   ├── system_info.sh          resources, firewall, SSH, updates, ports, services, system info
│   ├── suspicious_activity.sh  permissions, hidden files, processes, cron
│   └── integrity.sh            hash baseline, comparison, rebaseline
├── baseline/                   saved hashes (git-ignored)
├── logs/                       alert log (git-ignored)
├── reports/                    generated reports (git-ignored)
└── .gitignore
```

---

## Configuration

Judgement calls such as which folders to scan or which services count as risky live in `config/audit.conf`, not in the scripts.

| Setting | Meaning | Default |
|---|---|---|
| `USAGE_THRESHOLD` | CPU, RAM and disk warning level (%) | `80` |
| `DISK_MOUNT` | Mount point whose disk usage is checked | `/` |
| `REPORT_KEEP_DAYS` | Reports older than this are deleted | `30` |
| `INTEGRITY_FILES` | Files watched by the integrity check | passwd, shadow, sudoers, hosts, crontab |
| `RISKY_SERVICES` | Services flagged when running | avahi-daemon, cups-browsed, bluetooth, gnome-remote-desktop, snapd |
| `WORLD_WRITABLE_DIRS` | Folders scanned for world-writable files | `/etc /usr /var` |
| `HIDDEN_EXEC_DIRS` | Folders scanned for hidden executables | `/tmp /var/tmp /dev/shm /root /home` |
| `HIDDEN_EXEC_PRUNE` | Folder names skipped in that scan | `.cache .local .mozilla .config snap` |
| `SUSPICIOUS_PROCESS_PATHS` | Patterns a running program should not start from | `/tmp/*`, `/var/tmp/*`, `/dev/shm/*`, `/home/*/Downloads/*` |
| `SUSPICIOUS_CRON_PATHS` | Cron entries mentioning these folders are CRIT | `/tmp/ /var/tmp/ /dev/shm/` |
| `CRON_FILES` | Cron files read by the cron check | `/etc/crontab`, `/etc/cron.d/*`, `/var/spool/cron/crontabs/*` |
| `METRICS_FILE` | Where the metrics file for Prometheus is written | node_exporter's textfile folder |

Things to know:

- The file is loaded with `source`, so it must be valid Bash, and it is installed **root-owned** so normal users cannot edit it. A config that users could write to would let them run commands as root.
- If the file is missing, the audit stops with an error instead of falling back to defaults, so a deleted config is never silent.
- `install.sh` overwrites the installed config from the repository every time. Make changes in `config/audit.conf` in the repository and redeploy. Edits made directly on a laptop are lost.
- `INTEGRITY_FILES` is only used when the baseline is created. After changing the list, run `--rebaseline` for it to take effect.
- Patterns containing `*` are written in single quotes so Bash does not expand them while loading the file.
- Do not empty an array. Remove only the entry you want gone.
- The thresholds in Grafana's alert rules are separate. Changing `USAGE_THRESHOLD` does not change them.

---

## Installation and scheduling

```bash
git clone https://github.com/abin-actionfi/Laptop-Security-Audit-Monitoring-Tool.git
cd Laptop-Security-Audit-Monitoring-Tool
sudo ./install.sh            # default time 15:00
sudo ./install.sh 16:30      # or choose a time (HH:MM)
```

`install.sh`:

1. Copies the tool and its config to `/opt/laptop-audit`.
2. Makes everything root-owned. Code and config folders are `755`. `baseline/`, `logs/` and `reports/` are `700` (root only).
3. Creates a systemd **service** (what to run) and **timer** (when to run).
4. Installs a logrotate rule for the logs.

The schedule is **every Monday at the chosen time** (default 15:00). The timer uses `Persistent=true`, so if the laptop was off at that time the audit runs once after the next boot, not once per missed run. To change the day or frequency, edit the `OnCalendar=` line in `install.sh`.

Useful commands:

```bash
systemctl list-timers laptop-audit.timer         # next and last run
sudo systemctl start laptop-audit.service        # run the scheduled audit now
sudo ls -t /opt/laptop-audit/reports             # newest report first
sudo tail /opt/laptop-audit/logs/alerts.log      # recent alerts
```

**Updating a laptop:** pull the new code and run `sudo ./install.sh` again. It replaces the code and config and never touches `baseline/`, `logs/` or `reports/`. If you changed the schedule, also run `sudo systemctl restart laptop-audit.timer` so the new time is picked up.

**Two copies:** the project folder and `/opt/laptop-audit` are separate. Each has its own reports, alert log and baseline. The scheduled audit uses `/opt`. Both copies write the same metrics file, so a manual run from the project folder overwrites the numbers of the scheduled one. Use the project folder for testing only.

---

## Usage

Run an audit by hand:

```bash
sudo ./audit.sh                          # from the project folder (uses its own reports/ and baseline/)
sudo /opt/laptop-audit/audit.sh          # the installed copy
```

The report is printed and saved as `reports/audit_<DD-MM-YYYY_HH-MM-SS>.txt`. File names do not sort by date in `ls`, so use `ls -t` to find the newest.

Accept a legitimate change to the monitored files (for example a new user), so the integrity check stops reporting it:

```bash
sudo /opt/laptop-audit/audit.sh --rebaseline
```

This re-hashes the monitored files and overwrites the baseline. It does not run an audit. It writes an `[INFO]` line to the alert log with the name of the user who ran it. Make the legitimate change first, then rebaseline.

---

## What the tool writes

| File | Content | Cleanup |
|---|---|---|
| `reports/audit_<date>.txt` | Full output of one run | Deleted after `REPORT_KEEP_DAYS` days, at the start of each run |
| `logs/alerts.log` | One line per WARN or CRIT (and per rebaseline): `DD-MM-YYYY HH:MM:SS [LEVEL] message` | logrotate: weekly, 8 compressed copies |
| `logs/errors.log` | Errors from scheduled runs (systemd). Manual runs print errors to the terminal instead. | logrotate, same rule |
| `baseline/integrity.sha256` | Reference hashes of the monitored files. Created on the first run. | Never deleted |
| `laptop_audit.prom` (at `METRICS_FILE`) | Metrics for Prometheus, rewritten on every run | Replaced each run |

The metrics file contains:

| Metric | Meaning |
|---|---|
| `laptop_audit_ok_count`, `laptop_audit_warn_count`, `laptop_audit_crit_count` | The summary counts |
| `laptop_audit_last_run_timestamp_seconds` | When the audit last ran |
| `laptop_audit_info{report, os, version}` | The report file name, OS and tool version (text goes in labels, because Prometheus only stores numbers) |
| `laptop_audit_finding{level="CRIT", message}` | One line per critical finding |

It is written to a temporary file and renamed, so node_exporter never reads a half-written file. If node_exporter's folder does not exist, the step is skipped.

---

## Dashboards and alerts

The live monitoring uses off-the-shelf tools: **node_exporter** measures the laptop and serves the metrics file, **Prometheus** collects and stores the numbers, and **Grafana** draws dashboards and evaluates alert rules.

```
audit.sh -> laptop_audit.prom -> node_exporter -> Prometheus -> Grafana
```

The audit numbers and the live CPU, RAM and disk numbers come from the same node_exporter, so they share the same `instance` label. That is what lets one table show both.

### Dashboards

| Dashboard | Purpose |
|---|---|
| **Fleet Overview** (main board) | One screen for all laptops: tiles for laptops up, laptops with a CRIT and the oldest audit, an **Active alerts** panel that is empty when all is well, a **Laptops** table with a row per laptop (up, CPU, RAM, disk, CRIT, WARN, time since the last audit, and which report to open), and a **Critical findings** table with the text of each critical finding. Table cells turn red or orange at their thresholds, and clicking a laptop opens its detail dashboard. |
| **Laptop Overview** (per laptop) | Alert status, reachability, CPU, RAM and disk gauges, and a usage trend with the 80% line. A **Laptop** dropdown selects the machine. |
| **Node Exporter Full** | A community dashboard (ID 1860) for deep dives |

The audit columns only change when an audit runs. A CRIT that has been fixed stays on the board until the next audit.

The dashboards are built in the Grafana interface and are not stored in this repository.

### Alert rules

| Rule | Fires when |
|---|---|
| High CPU, High RAM, High disk | Above 80% for 5 minutes |
| Audit found CRIT | The last audit reported at least one critical finding |
| Audit is stale | No audit for more than 8 days (catches a disabled timer or removed tool) |

Alerts are only visible inside Grafana. Delivery to email, Slack or Telegram is not set up yet.

### Setup notes

- Ubuntu's `prometheus-node-exporter` package already enables the textfile folder (`/var/lib/prometheus/node-exporter/`).
- Prometheus 2.45 on Ubuntu 24.04 serves its pages under `/classic/` (for example `/classic/targets`).
- Grafana comes from Grafana's own apt repository. Add Prometheus as a data source at `http://localhost:9090`.

### Security note

node_exporter (port 9100), Prometheus (9090) and Grafana (3000) listen on all interfaces over plain HTTP, and node_exporter and Prometheus have no login. This is acceptable for a test and must be firewalled and encrypted before any rollout. The audit's own open-port check warns about these ports.

---

## Design decisions

| Decision | Reason |
|---|---|
| Runs as root, no `sudo` inside the scripts | Scheduled jobs cannot type a password, and some checks need root |
| Installed to `/opt`, root-owned | A root job running a script or config that users can edit would be privilege escalation |
| systemd timer, not cron | Needed a fixed time and a catch-up after a missed run. Cron cannot catch up, and anacron has no fixed time. |
| Own `sha256sum` baseline, not AIDE | Simple to read and explain. AIDE is more powerful but heavier to configure. |
| `<<<` here-string instead of piping into `while read` | A pipe runs in a subshell and the verdict counters would be lost |
| Settings in one config file | The judgement calls (folders, lists, thresholds) change from office to office |
| Audit results sent through node_exporter's textfile folder | Reuses the existing monitoring chain with no new software |
| Plain Bash and standard Linux tools | Easy to read and audit |

---

## Known limitations

- Process and file checks use fixed rules. Some WARNs are noise (for example Firefox opens random ports, and programs replaced by an update show as "deleted" until the next reboot).
- The process check looks at **where** a program runs from, not what it does. It will not catch malware in `/usr/bin`, scripts run through an interpreter, or short-lived processes.
- The integrity baseline trusts the machine's state on the first run and covers only the configured files.
- Anyone with root can edit the tool, the config, the baseline and the logs, or run `--rebaseline`. The `[INFO]` log line is the only trace. Real protection needs standard (non-sudo) staff accounts and a central copy of results.
- No SUID/SGID check.
- The SSH check is simplified: it keeps the last matching setting, while OpenSSH uses the first.
- `apt-check` only reads what `apt update` has already downloaded, so update counts can be stale.
- The alert log repeats the same finding every run.
- Only `ufw` is checked for the firewall.
- Audit data on the dashboard is as fresh as the last run (weekly by default).
- If the audit stops running, the old metrics file keeps being served. The "Audit is stale" rule is what catches that.
- Monitoring is pull-based, so Prometheus must be able to reach each laptop on port 9100.
- Ubuntu and Debian only.
- This is not a replacement for antivirus or EDR.
- Behaviour on suspend or lid close has not been tested on a real laptop, and a catch-up run at boot may happen before the network is up.

---

## Planned

### Hardening checks

Read-only checks for a new `modules/hardening.sh`, each with its own settings in `config/audit.conf`:

| Check | What it reads | Flags |
|---|---|---|
| Reboot pending | `/var/run/reboot-required` | WARN when updates are installed but not active |
| Firewall policy | `/etc/default/ufw` and `/etc/ufw/ufw.conf` | Default incoming policy not deny, logging off |
| Admin accounts | The `sudo` and `admin` groups, extra UID 0 accounts, `NOPASSWD` rules, empty passwords | CRIT for anyone not on the approved admin list |
| Disk encryption | Whether the device behind `/` has an encrypted layer | CRIT when unencrypted |
| Screen lock | GNOME idle delay plus lock delay, read as each logged-in user | WARN when the lock is off or slower than the limit. Skipped if nobody is logged in. |
| Password policy | Per-account `chage` values and `pwquality.conf` | WARN for empty passwords or a short minimum length |
| USB storage | A modprobe block rule for `usb-storage`, or `usbguard` | WARN when not blocked |

New settings: `APPROVED_ADMINS`, `SCREEN_LOCK_MAX_IDLE`, `PASSWORD_MIN_LENGTH` and `FIREWALL_ALLOWED_POLICIES`.

### Other

- Allowed-ports setting, so the monitoring ports stop warning once they are intentionally open
- Open-source scanners (rkhunter and ClamAV) as an optional `--scan` mode, report only
- Software allowlist, to detect installs that were not approved for the laptop's role
- Alert delivery (email, Slack or Telegram)
- TLS and authentication for the monitoring stack
- Dashboards exported into the repository
- Sample reports and a `shellcheck` pass
