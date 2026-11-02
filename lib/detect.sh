#!/usr/bin/env bash
# Detect OS, architecture and hardware, and pick sensible defaults for this box.

detect_system() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release — is this Linux?"
  OS_ID=$(. /etc/os-release && echo "${ID:-unknown}")
  OS_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-$OS_ID}")
  OS_VERSION=$(. /etc/os-release && echo "${VERSION_ID:-0}")
  OS_MAJOR=${OS_VERSION%%.*}
  ARCH=$(uname -m)
  CPU_CORES=$(nproc)
  RAM_GB=$(awk '/MemTotal/ { printf "%d", $2 / 1024 / 1024 + 0.5 }' /proc/meminfo)
  DISK_FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  IS_PI=0
  if grep -qai 'raspberry pi' /proc/device-tree/model 2>/dev/null; then IS_PI=1; fi

  case $OS_ID in
    ubuntu|debian|raspbian) OS_FAMILY=debian; PKG_TYPE=deb ;;
    rocky|rhel|almalinux)   OS_FAMILY=rhel;   PKG_TYPE=rpm ;;
    centos)                 die "CentOS 7 is end-of-life and not supported by this script. Use Rocky 8/9 or Ubuntu 22.04." ;;
    *)                      die "Unsupported OS: $OS_NAME" ;;
  esac

  log "OS:        $OS_NAME ($ARCH)$([[ $IS_PI == 1 ]] && echo ' — Raspberry Pi')"
  log "Hardware:  $CPU_CORES cores, ${RAM_GB} GB RAM, ${DISK_FREE_GB} GB free on /"
}

# Warn about anything outside the TAK Server 5.7 guide's supported list / minimums.
check_system() {
  local supported=0
  case "$OS_ID:$OS_MAJOR" in
    ubuntu:22|rocky:8|rocky:9|rhel:8|rhel:9) supported=1 ;;
    debian:*|raspbian:*) if [[ $IS_PI == 1 && $ARCH == aarch64 ]]; then supported=1; fi ;;
  esac
  if [[ $supported == 0 ]]; then
    warn "$OS_NAME is not on the TAK Server supported list (Ubuntu 22, Rocky/RHEL 8-9, 64-bit Raspberry Pi OS)."
    confirm "Continue anyway?" || die "Aborted"
  fi

  if (( CPU_CORES < 4 )); then warn "TAK recommends 4+ CPU cores (found $CPU_CORES)."; fi
  if (( RAM_GB < 8 ));    then warn "TAK recommends 8 GB RAM (found ${RAM_GB} GB)."; fi
  if (( DISK_FREE_GB < 40 )); then warn "TAK recommends 40 GB disk (found ${DISK_FREE_GB} GB free)."; fi

  # Low-resource boxes run only the messaging + API services (no plugin service).
  if [[ $TAK_SERVICE == auto ]]; then
    if [[ $IS_PI == 1 ]] || (( RAM_GB < 8 )); then
      TAK_SERVICE=takserver-noplugins
    else
      TAK_SERVICE=takserver
    fi
  fi
}
