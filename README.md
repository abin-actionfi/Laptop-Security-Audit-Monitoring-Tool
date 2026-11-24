# Laptop Security Audit & Monitoring Tool

A lightweight Bash tool that audits the security and health of an Ubuntu laptop, flags suspicious activity, and saves a report with findings and recommendations. It runs unattended on a schedule.

> **Authorised use only.** The tool lists running processes and scans `/home`. Run it only on systems you own or have written permission to audit. Collect only security and health data.

---

## What it does

Every run performs read-only checks. Each check gives a verdict:

| Verdict | Meaning |
|---|---|
| `[OK]` | Check passed |
| `[WARN]` | Worth reviewing |
| `[CRIT]` | Needs attention |

Every `WARN` and `CRIT` is also written to an alert log. At the end, a summary shows the counts, a **Critical Findings** list, and numbered **Recommendations**.

### Checks

| Area | Check | Verdicts |
|---|---|---|
| System info | OS, CPU, memory, disk, installed package count | Info only |
| Resources | CPU, RAM and root-disk usage against an 80% threshold | OK / WARN |
| Firewall | `ufw` missing or inactive | OK / WARN / CRIT |
| SSH | `PermitRootLogin yes` is CRIT, password login enabled is WARN. Reads `sshd_config` and `sshd_config.d/*.conf`. If no SSH server is installed, the check passes. | OK / WARN / CRIT |
| Updates | Pending updates via `apt-check`. Security updates are CRIT, other updates WARN. | OK / WARN / CRIT |
| Open ports | Ports listening on all interfaces (`0.0.0.0` or `[::]`) | WARN per port |
| Services | Running services that are often unneeded: avahi-daemon, cups-browsed, bluetooth, gnome-remote-desktop, snapd | WARN per service |
| Permissions | World-writable files in `/etc`, `/usr`, `/var` | WARN per file |
| Hidden files | Hidden executables in `/tmp`, `/var/tmp`, `/dev/shm`, `/root`, `/home` | WARN per file |
| Processes | Processes running from `/tmp`, `/var/tmp`, `/dev/shm`, `~/Downloads`, or whose executable was deleted | WARN per process |
| Cron | Counts active system cron entries (OK). Entries that run from temp folders are CRIT. | OK / CRIT |
| File integrity | SHA-256 hashes of `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/hosts`, `/etc/crontab` compared with a saved baseline | OK / CRIT |

The tool is **non-destructive**. Checks only read. The one deletion is its own old reports (see "What the tool writes").

### How one run works

1. `audit.sh` loads the helper functions and modules, then stops unless it runs as root.
2. If started with `--rebaseline`, it resets the integrity baseline and exits (no audit).
3. It deletes its own reports older than 30 days.
4. It runs every check. Output goes to the screen and into a new report file at the same time.
5. It prints the summary, critical findings and recommendations.

---

## Requirements

- Ubuntu or Debian (uses `dpkg`, `apt-check` and `/etc/os-release`). Tested on Ubuntu 24.04.
- systemd and logrotate (both standard on Ubuntu)
- `git`, to download the tool
- `sudo` access for whoever installs it

---

## Project layout

```
laptop-security-audit/
├── audit.sh                    main script, run as root
├── install.sh                  installs to /opt and schedules the audit
├── lib/
│   └── common.sh               verdict helpers, counters, alerts, summary
├── modules/
│   ├── system_info.sh          system, resources, firewall, SSH, updates, ports, services
│   ├── suspicious_activity.sh  permissions, hidden files, processes, cron
│   └── integrity.sh            hash baseline, comparison, rebaseline
├── baseline/                   saved hashes (git-ignored)
├── logs/                       alert log (git-ignored)
├── reports/                    generated reports (git-ignored)
└── .gitignore
```

---

## Installation and scheduling

```bash
git clone https://github.com/abin-actionfi/Laptop-Security-Audit-Monitoring-Tool.git
cd Laptop-Security-Audit-Monitoring-Tool
sudo ./install.sh            # default time 15:00
sudo ./install.sh 16:30      # or choose a time (HH:MM)
```

`install.sh`:

1. Copies the tool to `/opt/laptop-audit`.
2. Makes everything root-owned. Code folders are `755`. `baseline/`, `logs/` and `reports/` are `700` (root only).
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

**Updating a laptop:** pull the new code and run `sudo ./install.sh` again. It replaces the code and never touches `baseline/`, `logs/` or `reports/`. If you changed the schedule, also run `sudo systemctl restart laptop-audit.timer` so the new time is picked up.

**Two copies:** the project folder and `/opt/laptop-audit` are separate. Each has its own reports, alert log and baseline. The scheduled audit uses `/opt`.

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
| `reports/audit_<date>.txt` | Full output of one run | Reports older than 30 days are deleted at the start of each run |
| `logs/alerts.log` | One line per WARN or CRIT (and per rebaseline): `DD-MM-YYYY HH:MM:SS [LEVEL] message` | logrotate: weekly, 8 compressed copies |
| `logs/errors.log` | Errors from scheduled runs (systemd). Manual runs print errors to the terminal instead. | logrotate, same rule |
| `baseline/integrity.sha256` | Reference hashes of the monitored files. Created on the first run. | Never deleted |

---

## Live monitoring (separate from this repository)

Live CPU, RAM and disk alerting uses off-the-shelf tools, not these scripts:

- **node_exporter** measures the laptop.
- **Prometheus** collects and stores the numbers.
- **Grafana** shows the *Node Exporter Full* dashboard and holds alert rules for CPU, RAM and root disk above 80% for 5 minutes.

Status: working on a single test laptop, with alerts visible inside Grafana only. Alert delivery (email, Slack or Telegram), a second laptop and the server move are not done yet. The audit tool and the live monitoring are not connected yet.

**Security note:** node_exporter (port 9100), Prometheus (9090) and Grafana (3000) listen on all interfaces over plain HTTP, and node_exporter and Prometheus have no login. This is acceptable for a test, and must be firewalled and encrypted before any rollout. The audit tool's own open-port check will WARN about these ports.

---

## Design decisions

| Decision | Reason |
|---|---|
| Runs as root, no `sudo` inside the scripts | Scheduled jobs cannot type a password, and some checks need root |
| Installed to `/opt`, root-owned | A root job running a script that users can edit would be privilege escalation |
| systemd timer, not cron | Needed a fixed time and a catch-up after a missed run. Cron cannot catch up, and anacron has no fixed time. |
| Own `sha256sum` baseline, not AIDE | Simple to read and explain. AIDE is more powerful but heavier to configure. |
| `<<<` here-string instead of piping into `while read` | A pipe runs in a subshell and the verdict counters would be lost |
| Plain Bash and standard Linux tools | Easy to read and audit |

---

## Known limitations

- Process and file checks use fixed rules. Some WARNs are noise (for example Firefox opens random ports, and updated programs show as "deleted").
- The process check looks at **where** a program runs from, not what it does. It will not catch malware in `/usr/bin`, scripts run through an interpreter, or short-lived processes.
- The integrity baseline trusts the machine's state on the first run and covers only 5 files.
- Anyone with root can edit the tool, the baseline and the logs, or run `--rebaseline`. The `[INFO]` log line is the only trace. Real protection needs standard (non-sudo) staff accounts and a central copy of results.
- No SUID/SGID check.
- The SSH check is simplified: it keeps the last matching setting, while OpenSSH uses the first.
- `apt-check` only reads what `apt update` has already downloaded, so update counts can be stale.
- The alert log repeats the same finding every run.
- Only `ufw` is checked for the firewall.
- Ubuntu and Debian only.
- This is not a replacement for antivirus or EDR.
- Behaviour on suspend or lid close has not been tested on a real laptop, and a catch-up run at boot may happen before the network is up.

---

## Planned

- Open-source scanners (rkhunter and ClamAV) as an optional `--scan` mode, report only
- Software allowlist, to detect installs that were not approved for the laptop's role
- Config file for thresholds and lists
- Machine-readable output so audit results can go to Prometheus
- Heartbeat or last-seen alert for laptops that stop reporting
- TLS and authentication for the monitoring stack
- Sample reports and a `shellcheck` pass
