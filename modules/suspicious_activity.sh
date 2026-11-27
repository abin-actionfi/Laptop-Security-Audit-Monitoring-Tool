#!/bin/bash

 check_world_writable_files() {
    section "WORLD-WRITABLE FILES"

    local results
    results=$(find "${WORLD_WRITABLE_DIRS[@]}" -type f -perm -0002 -print 2>/dev/null)

    if [ -z "$results" ]; then
        local dirs="${WORLD_WRITABLE_DIRS[*]}"
        log_ok "No world-writable files found in ${dirs// /, }"
        return
    fi

    while read -r file; do
        log_warn "World-writable file: $file"
    done <<< "$results"

    recommend "Remove public write access: chmod o-w <file>"
}

 check_hidden_executables() {
    section "HIDDEN EXECUTABLE FILES"

    local results name
    local prune_args=()

    for name in "${HIDDEN_EXEC_PRUNE[@]}"; do
        if [ "${#prune_args[@]}" -gt 0 ]; then
            prune_args+=(-o)
        fi
        prune_args+=(-path "*/$name")
    done

    results=$(find "${HIDDEN_EXEC_DIRS[@]}" \
        \( "${prune_args[@]}" \) -prune \
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
    local proc pid exe pattern matched

    for proc in /proc/[0-9]*; do
        pid=${proc##*/}
        exe=$(readlink "$proc/exe" 2>/dev/null)

        matched=0
        for pattern in "${SUSPICIOUS_PROCESS_PATHS[@]}"; do
            if [[ "$exe" == $pattern ]]; then
                matched=1
                break
            fi
        done

        if [ "$matched" -eq 1 ]; then
            log_warn "Process $pid runs from an unusual location: $exe"
            found=1
        elif [[ "$exe" == *"(deleted)"* ]]; then
            log_warn "Process $pid runs a deleted executable: $exe"
            found=1
        fi
        done

    if [ "$found" -eq 0 ]; then
        log_ok "No suspicious processes found"
    else
        recommend "Investigate processes: ls -l /proc/<PID>/exe and ps -p <PID> -f"
    fi
}

check_system_cron() {
    section "CRON JOBS"

    local entries pattern cron_file
    local cron_files=()

    for pattern in "${CRON_FILES[@]}"; do
        for cron_file in $pattern; do
            if [ -f "$cron_file" ]; then
                cron_files+=("$cron_file")
            fi
        done
    done

    if [ "${#cron_files[@]}" -gt 0 ]; then
        entries=$(grep -hv '^\s*#' "${cron_files[@]}" 2>/dev/null | grep -v '^\s*$')
    fi

    if [ -z "$entries" ]; then
        log_ok "No active cron entries found"
        return
    fi

    local count
    count=$(echo "$entries" | wc -l)
    log_ok "$count active cron entries found (review in report)"

    local bad path
    local cron_args=()

    for path in "${SUSPICIOUS_CRON_PATHS[@]}"; do
        cron_args+=(-e "$path")
    done

    bad=$(echo "$entries" | grep -F "${cron_args[@]}")

    if [ -n "$bad" ]; then
        while read -r line; do
            log_crit "Cron job runs from a temp folder: $line"
        done <<< "$bad"
        recommend "Inspect the cron job and remove it if unknown: crontab -e"
    fi
}
