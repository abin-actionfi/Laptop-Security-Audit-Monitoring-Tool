#!/bin/bash

 check_world_writable_files() {
    section "WORLD-WRITABLE FILES"

    local results
    results=$(find /etc /usr /var -type f -perm -0002 -print 2>/dev/null)

    if [ -z "$results" ]; then
        log_ok "No world-writable files found in /etc, /usr, /var"
        return
    fi

    while read -r file; do
        log_warn "World-writable file: $file"
    done <<< "$results"

    recommend "Remove public write access: chmod o-w <file>"
}

 check_hidden_executables() {
    section "HIDDEN EXECUTABLE FILES"

    local results
    results=$(find /tmp /var/tmp /dev/shm /root /home \
        \( -path "*/.cache" -o -path "*/.local" -o -path "*/.mozilla" -o -path "*/.config" -o -path "*/snap" \) -prune \
        -o -type f -name ".*" -perm /111 -print 2>/dev/null)

    if [ -z "$results" ]; then
        log_ok "No hidden executable files found"
        return
    fi

    while read -r file; do
        log_warn "Hidden executable file: $file"
    done <<< "$results"

    recommend "Inspect hidden executables and remove if unknown: ls -l <file>"
}

 check_suspicious_processes() {
    section "SUSPICIOUS PROCESSES"

    local found=0
    local proc pid exe

    for proc in /proc/[0-9]*; do
        pid=${proc##*/}
        exe=$(readlink "$proc/exe" 2>/dev/null)

        case "$exe" in
            /tmp/*|/var/tmp/*|/dev/shm/*|/home/*/Downloads/*)
                log_warn "Process $pid runs from an unusual location: $exe"
                found=1
                ;;
            *"(deleted)"*)
                log_warn "Process $pid runs a deleted executable: $exe"
                found=1
                ;;
        esac
    done

    if [ "$found" -eq 0 ]; then
        log_ok "No suspicious processes found"
    else
        recommend "Investigate processes: ls -l /proc/<PID>/exe and ps -p <PID> -f"
    fi
}

check_system_cron() {
    section "CRON JOBS"

    local entries
    entries=$(grep -hv '^\s*#' /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/* 2>/dev/null \
        | grep -v '^\s*$')

    if [ -z "$entries" ]; then
        log_ok "No active cron entries found"
        return
    fi

    local count
    count=$(echo "$entries" | wc -l)
    log_ok "$count active cron entries found (review in report)"

    local bad
    bad=$(echo "$entries" | grep -E '/tmp/|/var/tmp/|/dev/shm/')

    if [ -n "$bad" ]; then
        while read -r line; do
            log_crit "Cron job runs from a temp folder: $line"
        done <<< "$bad"
        recommend "Inspect the cron job and remove it if unknown: crontab -e"
    fi
}
