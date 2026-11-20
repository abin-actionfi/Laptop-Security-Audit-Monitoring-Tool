#!/bin/bash

USAGE_THRESHOLD=80

check_firewall() {
    section "FIREWALL"

    if ! command -v ufw >/dev/null 2>&1; then
        log_warn "ufw is not installed, no firewall check possible"
        recommend "Install a firewall: apt install ufw"
    elif ufw status | grep -q "inactive"; then
        log_crit "Firewall (ufw) is inactive"
        recommend "Enable the firewall: ufw enable"
    else
        log_ok "Firewall (ufw) is active"
    fi
}

get_ssh_setting() {
    local key="$1"
    local file="$2"

    grep -hiE "^[[:space:]]*$key[[:space:]]+" "$file" /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
    | tail -n 1 | awk '{print tolower($2)}'
}

check_ssh() {
    section "SSH"

    if [ ! -f /etc/ssh/sshd_config ]; then
        log_ok "SSH server is not installed (no remote login attack surface)"
        return
    fi
    local config="/etc/ssh/sshd_config"
    local root_login
    local password_auth

    root_login=$(get_ssh_setting "PermitRootLogin" "$config")
    password_auth=$(get_ssh_setting "PasswordAuthentication" "$config")

    if [ "$root_login" = "yes" ]; then
        log_crit "SSH allows root login (PermitRootLogin yes)"
        recommend "Set 'PermitRootLogin no' in /etc/ssh/sshd_config"
    else
        log_ok "SSH root login is restricted (${root_login:-default})"
    fi

    if [ "$password_auth" = "no" ]; then
        log_ok "SSH password login is disabled"
    else
        log_warn "SSH password login is enabled (${password_auth:-default})"
        recommend "Use SSH keys and set 'PasswordAuthentication no'"
    fi

}

check_updates() {
    section "SECURITY UPDATES"

    if [ ! -x /usr/lib/update-notifier/apt-check ]; then
        log_warn "apt-check is unavailable, cannot check for updates"
        return
    fi

    local info total security
    info=$(/usr/lib/update-notifier/apt-check 2>&1)
    total=$(echo "$info" | cut -d';' -f1)
    security=$(echo "$info" | cut -d';' -f2)

    if [ "$security" -gt 0 ]; then
        log_crit "$security security updates are pending"
        recommend "Install updates: apt update && apt upgrade"
    elif [ "$total" -gt 0 ]; then
        log_warn "$total updates are pending (none are security updates)"
        recommend "Install updates: apt update && apt upgrade"
    else
        log_ok "System is up to date"
    fi
}

check_resources() {
    section "RESOURCE UTILIZATION"

    local cpu_idle cpu ram disk

    cpu_idle=$(vmstat 1 2 | tail -n 1 | awk '{print $15}')
    cpu=$((100 - cpu_idle))
    ram=$(free | awk '/Mem:/ {printf "%d", ($2-$7)/$2*100}')
    disk=$(df / | awk 'NR==2 {gsub("%",""); print $5}')

    if [ "$cpu" -ge "$USAGE_THRESHOLD" ]; then
        log_warn "CPU usage is high: ${cpu}%"
        recommend "Check what is using CPU: top"
    else
        log_ok "CPU usage is normal: ${cpu}%"
    fi

    if [ "$ram" -ge "$USAGE_THRESHOLD" ]; then
        log_warn "RAM usage is high: ${ram}%"
        recommend "Check memory hogs: ps aux --sort=-%mem | head"
    else
        log_ok "RAM usage is normal: ${ram}%"
    fi

    if [ "$disk" -ge "$USAGE_THRESHOLD" ]; then
        log_warn "Disk usage is high: ${disk}%"
        recommend "Free disk space: apt clean, remove old files"
    else
        log_ok "Disk usage is normal: ${disk}%"
    fi
}

check_ports() {
    section "OPEN PORTS"

    local public_ports
    public_ports=$(ss -tulnp | awk 'NR>1 && ($5 ~ /^0\.0\.0\.0:/ || $5 ~ /^\[::\]:/) {print $5, $7}')

    if [ -z "$public_ports" ]; then
        log_ok "No ports are listening on all network interfaces"
        return
    fi

    while read -r line; do
        log_warn "Port open on all interfaces: $line"
    done <<< "$public_ports"

    recommend "Review open ports and disable unneeded services (e.g. avahi-daemon)"
}

check_services() {
    section "RUNNING SERVICES"

    local risky_services=(avahi-daemon cups-browsed bluetooth gnome-remote-desktop snapd)
    local found=0
    local svc

    for svc in "${risky_services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            log_warn "Service running that is often not needed: $svc"
            found=1
        fi
    done

    if [ "$found" -eq 0 ]; then
        log_ok "None of the commonly unneeded services are running"
    else
        recommend "Disable unused services: systemctl disable --now <service>"
    fi
}

check_system() {
 echo "===== SYSTEM INFORMATION ====="

 echo ""
 echo "OS INFORMATION"

 . /etc/os-release && echo "$PRETTY_NAME"

 echo ""
 echo "CPU INFORMATION"

 lscpu | grep -E "^(Model name|CPU\(s\)|Architecture):"

 echo ""
 echo "MEMORY INFORMATION"

 free -h

 echo ""
 echo "DISK INFORMATION"

 df -h /

 echo ""
 echo "INSTALLED PACKAGES"

 echo "$(dpkg-query -f '.\n' -W | wc -l) packages installed"
}
