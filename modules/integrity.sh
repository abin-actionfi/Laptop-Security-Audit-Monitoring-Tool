#!/bin/bash

INTEGRITY_FILES=(/etc/passwd /etc/shadow /etc/sudoers /etc/hosts /etc/crontab)

check_integrity() {
    section "FILE INTEGRITY"

    local baseline="$PROJECT_DIR/baseline/integrity.sha256"
    mkdir -p "$PROJECT_DIR/baseline"

    if [ ! -f "$baseline" ]; then
        sha256sum "${INTEGRITY_FILES[@]}" > "$baseline"
        log_ok "Baseline created for ${#INTEGRITY_FILES[@]} files (first run)"
        return
    fi

    local changed
    changed=$(sha256sum -c "$baseline" 2>/dev/null | grep ': FAILED')

    if [ -z "$changed" ]; then
        log_ok "All monitored files match the baseline"
        return
    fi

    while read -r line; do
        log_crit "File changed since baseline: ${line%%:*}"
    done <<< "$changed"

    recommend "Verify the change was intended. If it was, delete baseline/integrity.sha256 to re-create it."
}

rebaseline_integrity() {
	local baseline="$PROJECT_DIR/baseline/integrity.sha256"
	mkdir -p "$PROJECT_DIR/baseline"

	sha256sum "${INTEGRITY_FILES[@]}" > "$baseline"
	send_alert "INFO" "Integrity baseline reset by ${SUDO_USER:-root}"
	echo "Baseline updated for ${#INTEGRITY_FILES[@]} files"
}
