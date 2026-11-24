#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/modules/system_info.sh"
source "$PROJECT_DIR/modules/suspicious_activity.sh"
source "$PROJECT_DIR/modules/integrity.sh"

require_root

require_root

if [ "$1" = "--rebaseline" ]; then
    rebaseline_integrity
    exit 0
fi

REPORT_FILE="$PROJECT_DIR/reports/audit_$(date +%d-%m-%Y_%H-%M-%S).txt"

echo "LAPTOP SECURITY AUDIT TOOL"

mkdir -p "$PROJECT_DIR/reports"

find "$PROJECT_DIR/reports" -name 'audit_*.txt' -mtime +30 -delete

{
check_system
check_resources
check_firewall
check_ssh
check_updates
check_ports
check_services
check_world_writable_files
check_hidden_executables
check_suspicious_processes
check_system_cron
check_integrity

print_summary

echo ""
echo "Audit Completed!"
} | tee "$REPORT_FILE"

