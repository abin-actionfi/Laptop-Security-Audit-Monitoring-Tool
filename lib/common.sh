#!/bin/bash

OK_COUNT=0
WARN_COUNT=0
CRIT_COUNT=0
RECOMMENDATIONS=()

ALERT_LOG="$PROJECT_DIR/logs/alerts.log"

log_ok() {
	echo "[OK]    $1"
	OK_COUNT=$((OK_COUNT+1))
}

log_warn() {
	echo "[WARN]  $1"
	WARN_COUNT=$((WARN_COUNT+1))
	send_alert "WARN" "$1"
}

log_crit() {
	echo "[CRIT]  $1"
	CRIT_COUNT=$((CRIT_COUNT+1))
	send_alert "CRIT" "$1"
}

section() {
    echo ""
    echo "===== $1 ====="
}

recommend() {
    RECOMMENDATIONS+=("$1")
}

print_summary() {
    section "AUDIT SUMMARY"
    echo "OK:        $OK_COUNT"
    echo "WARNINGS:  $WARN_COUNT"
    echo "CRITICAL:  $CRIT_COUNT"

    if [ "${#RECOMMENDATIONS[@]}" -gt 0 ]; then
        section "RECOMMENDATIONS"
        local i=1
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo "$i. $rec"
            i=$((i + 1))
        done
    fi
}

send_alert() {
    local level="$1"
    local message="$2"

    mkdir -p "$(dirname "$ALERT_LOG")"
    echo "$(date '+%d-%m-%Y %H:%M:%S') [$level] $message" >> "$ALERT_LOG"
    logger -t  laptop-audit "[$level] $message"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Run this tool as root: sudo ./audit.sh" >&2
        exit 1
    fi
}


