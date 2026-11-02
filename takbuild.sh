#!/usr/bin/env bash
# takbuild.sh — build a TAK Server from scratch on this machine.
#
#   sudo ./takbuild.sh                          # interactive: pick installer, answer prompts
#   sudo ./takbuild.sh -c config/my.conf        # use a saved config (still prompts for blanks)
#   sudo ./takbuild.sh -c config/my.conf -y     # fully unattended
#
# Re-running is safe: existing packages, containers and certs are detected and kept.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for lib in "$SCRIPT_DIR"/lib/*.sh; do source "$lib"; done

usage() {
  cat <<EOF
Usage: sudo $0 [options]

  -c, --config FILE     Settings file (layered on top of config/default.conf)
  -i, --installer FILE  Installer to use (skips the version menu)
  -y, --yes             No prompts — use config values / newest installer
      --force-certs     Back up existing certs and generate a new CA + certs
  -h, --help            Show this help
EOF
}

parse_args() {
  CONFIG_FILE='' CLI_INSTALLER='' ASSUME_YES=0 FORCE_CERTS=0
  while (( $# )); do
    case $1 in
      -c|--config)    CONFIG_FILE=${2:?--config needs a file}; shift ;;
      -i|--installer) CLI_INSTALLER=${2:?--installer needs a file}; shift ;;
      -y|--yes)       ASSUME_YES=1 ;;
      --force-certs)  FORCE_CERTS=1 ;;
      -h|--help)      usage; exit 0 ;;
      *)              usage; die "Unknown option: $1" ;;
    esac
    shift
  done
}

load_config() {
  source "$SCRIPT_DIR/config/default.conf"
  if [[ -n $CONFIG_FILE ]]; then
    [[ -f $CONFIG_FILE ]] || die "Config not found: $CONFIG_FILE"
    source "$CONFIG_FILE"
  fi
  if [[ -n $CLI_INSTALLER ]]; then INSTALLER=$CLI_INSTALLER; fi
  OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/output/$(hostname -s)-$(date +%Y%m%d-%H%M%S)}
}

setup_logging() {
  mkdir -p "$OUTPUT_DIR"
  LOG_FILE=$OUTPUT_DIR/takbuild.log
  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'die "Failed at line $LINENO: $BASH_COMMAND  (full log: $LOG_FILE)"' ERR
  log "Logging to $LOG_FILE"
}

prompt_settings() {
  SERVER_ADDRESS=${SERVER_ADDRESS:-$(primary_ip)}
  ask SERVER_ADDRESS  "Address clients connect to (public IP/DNS for cloud)"
  ask CONNECTION_NAME "Connection name shown in ATAK"
  ask USERS           "Client usernames (space separated)"
  ask USER_GROUPS     "Groups for those users (blank = none)"
  ask CERT_PASS       "Certificate password"
  ask CA_NAME         "Root CA name"
  ask CERT_STATE      "Cert state/province"
  ask CERT_CITY       "Cert city"
  ask CERT_ORG        "Cert organization"
  ask CERT_OU         "Cert organizational unit"

  local name u
  for name in SERVER_ADDRESS CONNECTION_NAME CERT_PASS CA_NAME CERT_COUNTRY CERT_STATE CERT_CITY CERT_ORG CERT_OU; do
    validate_text "$name" "${!name}"
  done
  validate_username "$SERVER_CERT_NAME"
  [[ -n $USERS ]] || die "USERS must list at least one client"
  for u in $USERS $USER_GROUPS; do validate_username "$u"; done
  if (( ${#CERT_PASS} < 6 )); then die "CERT_PASS must be at least 6 characters"; fi
  if [[ $CERT_PASS == atakatak ]]; then warn "Using TAK's default cert password 'atakatak' — fine for a lab, change it for real use."; fi
}

show_plan() {
  cat <<EOF

  ${C_BOLD}About to build:${C_RESET}
    Installer:     $(basename "$INSTALLER")  ($INSTALL_MODE)
    OS / hardware: $OS_NAME, $CPU_CORES cores, ${RAM_GB} GB RAM
    Service:       $([[ $INSTALL_MODE == docker ]] && echo "docker containers" || echo "$TAK_SERVICE")
    Clients use:   $SERVER_ADDRESS:8089 (TLS)
    Users:         $USERS$([[ -n $USER_GROUPS ]] && echo "  → groups: $USER_GROUPS")
    Firewall:      $([[ $CONFIGURE_FIREWALL == 1 ]] && echo "open $TAK_PORTS" || echo "unchanged")
    Output:        $OUTPUT_DIR

EOF
}

finish() {
  if [[ -n ${SUDO_USER:-} ]]; then chown -R "$SUDO_USER" "$OUTPUT_DIR"; fi
  cat <<EOF

${C_GREEN}${C_BOLD}TAK Server is up.${C_RESET}

  Admin UI:   https://$SERVER_ADDRESS:8443   (import admin/admin.p12 into your browser, password: $CERT_PASS)
  Clients:    import packages/<user>.zip in ATAK / WinTAK / iTAK
  Files:      $OUTPUT_DIR
  Logs:       $TAK_DIR/logs/

  Copy the files to your Mac with:
    scp -r ${SUDO_USER:-root}@$SERVER_ADDRESS:$OUTPUT_DIR .
EOF
  if [[ $CONFIGURE_FIREWALL == 1 ]]; then
    echo "  Cloud server? Also open $TAK_PORTS/tcp in the provider's security group."
  fi
}

main() {
  parse_args "$@"
  require_root "$@"
  load_config
  setup_logging

  step "Checking this machine"
  detect_system
  check_system

  step "Choosing installer"
  select_installer

  step "Settings"
  prompt_settings
  show_plan
  confirm "Proceed?" || die "Aborted"

  step "Installing TAK Server"
  if [[ $INSTALL_MODE == docker ]]; then install_docker; else install_native; fi

  step "Certificates"
  configure_cert_metadata
  generate_certs
  configure_coreconfig

  step "Starting TAK Server"
  if [[ $INSTALL_MODE == docker ]]; then restart_docker; else restart_native; fi
  wait_for_tak

  step "Users"
  register_users

  step "Client data packages"
  build_packages

  step "Firewall"
  open_firewall

  finish
}

main "$@"
