#!/usr/bin/env bash
# Native (.deb / .rpm) install, following section 4.2 of the TAK Server 5.7 guide.

raise_file_limits() {
  if grep -qE '^\*\s+hard\s+nofile\s+32768' /etc/security/limits.conf; then
    ok "File limits already raised"
    return 0
  fi
  printf '* soft nofile 32768\n* hard nofile 32768\n' >> /etc/security/limits.conf
  ok "Raised open-file limit to 32768"
}

prereqs_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y lsb-release curl ca-certificates gnupg zip unzip openssl
  install -d /etc/apt/keyrings
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /etc/apt/keyrings/postgresql.asc
  echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/postgresql.list
  apt-get update -y
}

prereqs_rhel() {
  dnf -y install dnf-plugins-core
  if [[ $OS_ID == rhel ]]; then
    dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm"
  else
    dnf -y install epel-release
  fi
  if ! rpm -q pgdg-redhat-repo >/dev/null 2>&1; then
    dnf -y install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${OS_MAJOR}-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"
  fi
  dnf -qy module disable postgresql
  dnf -y update

  # PostGIS dependencies live in CRB (EL9) / PowerTools (EL8).
  if [[ $OS_ID == rhel ]]; then
    subscription-manager config --rhsm.manage_repos=1 || true
    if ! subscription-manager repos --enable "codeready-builder-for-rhel-${OS_MAJOR}-${ARCH}-rpms"; then
      warn "Could not enable CodeReady Builder via subscription-manager; trying the AWS RHUI repo name"
      dnf config-manager --set-enabled "codeready-builder-for-rhel-${OS_MAJOR}-rhui-rpms" \
        || die "Enable CodeReady Builder manually (is this system registered?), then re-run."
    fi
  elif [[ $OS_MAJOR == 8 ]]; then
    dnf config-manager --set-enabled powertools
  else
    dnf config-manager --set-enabled crb
  fi

  dnf -y install java-17-openjdk-devel checkpolicy zip unzip openssl
}

package_installed() {
  if [[ $PKG_TYPE == deb ]]; then
    dpkg -s takserver >/dev/null 2>&1
  else
    rpm -q takserver >/dev/null 2>&1
  fi
}

install_takserver_package() {
  if package_installed; then
    warn "takserver is already installed — skipping package install (certs/config steps still run)."
    return 0
  fi
  if [[ $PKG_TYPE == deb ]]; then
    apt-get install -y "$INSTALLER"
  else
    dnf -y install "$INSTALLER"
  fi
  ok "TAK Server package installed"
}

ensure_java17() {
  if java -version 2>&1 | grep -q 'version "17\.'; then
    ok "Java 17 is the default"
    return 0
  fi
  local java17 alt
  java17=$(ls -d /usr/lib/jvm/java-17-openjdk*/bin/java 2>/dev/null | head -1 || true)
  [[ -n $java17 ]] || die "Java 17 not found under /usr/lib/jvm"
  alt=$(command -v alternatives || command -v update-alternatives)
  "$alt" --set java "$java17"
  ok "Switched default Java to $java17"
}

apply_selinux_policy() {
  if [[ $PKG_TYPE != rpm ]] || ! command -v selinuxenabled >/dev/null || ! selinuxenabled; then return 0; fi
  if semodule -l | grep -q takserver; then
    ok "SELinux takserver policy already loaded"
    return 0
  fi
  (cd "$TAK_DIR" && ./apply-selinux.sh)
  semodule -l | grep -q takserver || die "SELinux takserver policy did not load"
  ok "SELinux takserver policy applied"
}

install_native() {
  TAK_DIR=/opt/tak
  raise_file_limits
  "prereqs_$OS_FAMILY"
  install_takserver_package
  ensure_java17
  apply_selinux_policy
  systemctl daemon-reload

  if ! systemctl cat "$TAK_SERVICE" >/dev/null 2>&1; then
    warn "Service $TAK_SERVICE not found; using takserver"
    TAK_SERVICE=takserver
  fi
}

restart_native() {
  systemctl enable "$TAK_SERVICE"
  systemctl restart "$TAK_SERVICE"
}
