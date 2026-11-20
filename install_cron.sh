#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$PROJECT_DIR/lib/common.sh"
require_root

SCHEDULE="${1:-0 15 * * *}"
CRON_LINE="$SCHEDULE PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin $PROJECT_DIR/audit.sh >> $PROJECT_DIR/logs/cron.log 2>&1"

mkdir -p "$PROJECT_DIR/logs"

( crontab -l 2>/dev/null | grep -vF "$PROJECT_DIR/audit.sh"; echo "$CRON_LINE" ) | crontab -

echo "Cron job installed"
echo "$CRON_LINE"

