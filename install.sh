#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/laptop-audit"

source "$PROJECT_DIR/lib/common.sh"

require_root

RUN_TIME="${1:-15:00}"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/lib" "$INSTALL_DIR/modules"
cp -r "$PROJECT_DIR/lib" "$PROJECT_DIR/modules" "$INSTALL_DIR/"
cp "$PROJECT_DIR/audit.sh" "$INSTALL_DIR/"
mkdir -p "$INSTALL_DIR/baseline" "$INSTALL_DIR/logs" "$INSTALL_DIR/reports"

chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR" "$INSTALL_DIR/audit.sh" "$INSTALL_DIR/lib" "$INSTALL_DIR/modules"
chmod 644 "$INSTALL_DIR"/lib/*.sh "$INSTALL_DIR"/modules/*.sh
chmod 700 "$INSTALL_DIR/baseline" "$INSTALL_DIR/logs" "$INSTALL_DIR/reports"

cat > /etc/systemd/system/laptop-audit.service <<EOF
[Unit]
Description=Laptop security audit

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$INSTALL_DIR/audit.sh
StandardOutput=null
StandardError=append:$INSTALL_DIR/logs/errors.log
EOF

cat > /etc/systemd/system/laptop-audit.timer <<EOF
[Unit]
Description=Run laptop security audit weekly

[Timer]
OnCalendar=Mon *-*-* $RUN_TIME:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/logrotate.d/laptop-audit <<EOF
$INSTALL_DIR/logs/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 600 root root
}
EOF

systemctl daemon-reload
systemctl enable --now laptop-audit.timer

echo "Installed to $INSTALL_DIR"
echo "Weekly audit scheduled on Mondays at $RUN_TIME (runs after next boot if missed)"
