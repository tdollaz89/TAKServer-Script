#!/usr/bin/env bash
# Shared helpers: logging, prompts, validation, and running commands "inside" TAK
# (as the tak user for a native install, or via docker exec for a container install).

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
else
  C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi

log()  { printf '%s[*]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# ask VAR "Question" — prompt using VAR's current value as the default.
# Does nothing in --yes mode, so config values are used as-is.
ask() {
  local var=$1 question=$2 current=${!1-} reply
  if [[ $ASSUME_YES == 1 ]]; then return 0; fi
  read -r -p "  $question [$current]: " reply
  if [[ -n $reply ]]; then printf -v "$var" '%s' "$reply"; fi
}

confirm() {
  local reply
  if [[ $ASSUME_YES == 1 ]]; then return 0; fi
  read -r -p "$1 [y/N]: " reply
  [[ $reply =~ ^[Yy] ]]
}

require_root() {
  if [[ $EUID -ne 0 ]]; then die "Run as root: sudo $0 $*"; fi
}

# Values end up inside single-quoted shell assignments and XML attributes.
validate_text() {
  local name=$1 value=$2
  if [[ -z $value ]]; then die "$name must not be empty"; fi
  if [[ $value == *[\'\"\<\>\&\\]* ]]; then die "$name must not contain quotes, <, >, & or backslashes: $value"; fi
}

validate_username() {
  if [[ ! $1 =~ ^[A-Za-z0-9._-]+$ ]]; then die "Invalid username '$1' (letters, digits, . _ - only)"; fi
}

primary_ip() {
  { ip route get 1.1.1.1 2>/dev/null || true; } | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}

# Run a command where /opt/tak is TAK's home: as the tak user (native) or in the container.
tak_exec() {
  if [[ $INSTALL_MODE == docker ]]; then
    docker exec "$TAK_CONTAINER" bash -c "$1"
  else
    sudo -u tak bash -c "$1"
  fi
}

# Same, but with root privileges (needed for UserManager.jar on native installs).
tak_exec_root() {
  if [[ $INSTALL_MODE == docker ]]; then
    docker exec "$TAK_CONTAINER" bash -c "$1"
  else
    bash -c "$1"
  fi
}

# set_shell_var FILE KEY VALUE — rewrite a KEY=... line in a shell file as KEY='VALUE'.
set_shell_var() {
  local file=$1 key=$2 esc
  esc=$(printf '%s' "$3" | sed -e 's/[|&]/\\&/g')
  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}='${esc}'|" "$file"
  else
    printf "%s='%s'\n" "$key" "$3" >> "$file"
  fi
}
