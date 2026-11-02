#!/usr/bin/env bash
# Find TAK Server installers in the installers/ folder and let the user pick one.
#
# Recognized files (from tak.gov):
#   takserver_<ver>-RELEASE<n>_all.deb       native install on Ubuntu / Raspberry Pi OS
#   takserver-<ver>-RELEASE-<n>.noarch.rpm   native install on Rocky / RHEL
#   takserver-docker-<ver>-RELEASE-<n>.zip   Docker install on any supported OS

installer_version() {
  basename "$1" | grep -oE '[0-9]+(\.[0-9]+)+-RELEASE-?[0-9]+' | sed -E 's/-RELEASE-?/-/' | head -1
}

installer_mode() {
  case $(basename "$1") in
    *.zip) echo docker ;;
    *)     echo native ;;
  esac
}

list_installers() {
  local f name
  shopt -s nullglob
  for f in "$INSTALLER_DIR"/takserver*; do
    name=$(basename "$f")
    case $name in
      takserver_[0-9]*_all.deb)        if [[ $PKG_TYPE != deb ]]; then continue; fi ;;
      takserver-[0-9]*.noarch.rpm)     if [[ $PKG_TYPE != rpm ]]; then continue; fi ;;
      takserver-docker-[0-9]*.zip)     ;;
      *) continue ;;  # core/database/fed-hub/hardened bundles are not handled
    esac
    if [[ $INSTALL_MODE != auto && $(installer_mode "$f") != "$INSTALL_MODE" ]]; then continue; fi
    # Middle column ranks native above docker when versions tie; dropped by cut.
    printf '%s\t%s\t%s\n' "$(installer_version "$f")" "$([[ $name == *.zip ]] && echo 2 || echo 1)" "$f"
  done | sort -t $'\t' -k1,1Vr -k2,2n | cut -f1,3
  shopt -u nullglob
}

select_installer() {
  if [[ -n $INSTALLER ]]; then
    [[ -f $INSTALLER ]] || die "Installer not found: $INSTALLER"
  else
    local lines=() line i choice
    mapfile -t lines < <(list_installers)
    if (( ${#lines[@]} == 0 )); then
      die "No usable installers in $INSTALLER_DIR for $OS_NAME (need a .$PKG_TYPE or a takserver-docker .zip)."
    fi

    if (( ${#lines[@]} == 1 )) || [[ $ASSUME_YES == 1 ]]; then
      choice=1
    else
      echo "  Installers available for this machine:"
      for i in "${!lines[@]}"; do
        line=${lines[$i]}
        printf '    %d) %-10s %-7s %s%s\n' $((i + 1)) "${line%%$'\t'*}" "$(installer_mode "${line#*$'\t'}")" \
          "$(basename "${line#*$'\t'}")" "$([[ $i == 0 ]] && echo '   (newest)')"
      done
      read -r -p "  Choose [1]: " choice
      choice=${choice:-1}
      if [[ ! $choice =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#lines[@]} )); then die "Invalid choice: $choice"; fi
    fi
    INSTALLER=${lines[$((choice - 1))]#*$'\t'}
  fi

  INSTALLER=$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")
  INSTALL_MODE=$(installer_mode "$INSTALLER")
  TAK_VERSION=$(installer_version "$INSTALLER")
  verify_installer "$INSTALLER"
  ok "Using $(basename "$INSTALLER") ($INSTALL_MODE install, version ${TAK_VERSION:-unknown})"
}

# Catch truncated copies and saved login/error pages before touching the system.
verify_installer() {
  local f=$1 size_mb valid=1
  size_mb=$(( $(stat -c %s "$f") / 1024 / 1024 ))
  case $f in
    *.deb) dpkg-deb --info "$f" >/dev/null 2>&1 || valid=0 ;;
    *.rpm) rpm -qp "$f" >/dev/null 2>&1 || valid=0 ;;
    *.zip) if command -v unzip >/dev/null; then unzip -tq "$f" >/dev/null 2>&1 || valid=0; fi ;;
  esac
  if [[ $valid == 0 ]]; then
    die "$(basename "$f") is not a valid package (${size_mb} MB, $( (file -b "$f" 2>/dev/null || echo 'unknown type') | cut -c1-60)).
    It is probably an incomplete download/copy, or a tak.gov login page saved under that name.
    Compare checksums with: sha256sum \"$f\"   (shasum -a 256 on a Mac), then re-download or re-copy."
  fi
  log "Installer checks out (${size_mb} MB, sha256 $(sha256sum "$f" | cut -c1-16)…)"
}
