#!/usr/bin/env bash
# Open TAK ports in the host firewall (section 7 of the guide).

open_firewall() {
  if [[ $CONFIGURE_FIREWALL != 1 ]]; then
    log "Skipping firewall (CONFIGURE_FIREWALL=0)"
    return 0
  fi
  local p

  if [[ $OS_FAMILY == debian ]]; then
    if ! command -v ufw >/dev/null; then
      apt-get install -y ufw
      if [[ $IS_PI == 1 ]]; then warn "ufw was just installed — the guide recommends rebooting the Pi afterwards."; fi
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT/tcp"   # keep SSH open before enabling
    for p in $TAK_PORTS; do ufw allow "$p/tcp"; done
    ufw --force enable
  else
    if ! systemctl is-active --quiet firewalld; then
      warn "firewalld is not running — no host firewall changes made"
      return 0
    fi
    for p in $TAK_PORTS; do firewall-cmd --permanent --add-port="$p/tcp"; done
    firewall-cmd --reload
  fi
  ok "Firewall open for TCP: $TAK_PORTS"
}
