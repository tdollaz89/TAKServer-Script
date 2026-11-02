#!/usr/bin/env bash
# Docker install from takserver-docker-<ver>.zip, following section 6.2 of the TAK Server 5.7 guide.

install_docker_engine() {
  if [[ $OS_FAMILY == debian ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y zip unzip openssl curl
    if ! command -v docker >/dev/null; then apt-get install -y docker.io; fi
  else
    dnf -y install dnf-plugins-core zip unzip openssl
    if ! command -v docker >/dev/null || docker --version 2>&1 | grep -qi podman; then
      # RHEL/Rocky ship podman, which conflicts with docker-ce.
      dnf -y remove podman buildah runc || true
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf -y install docker-ce docker-ce-cli containerd.io
    fi
  fi
  systemctl enable --now docker
  ok "Docker is running ($(docker --version))"
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

install_docker() {
  install_docker_engine

  local unpack_dir
  unpack_dir="$DOCKER_BASE_DIR/$(basename "$INSTALLER" .zip)"
  if [[ ! -d $unpack_dir ]]; then
    mkdir -p "$unpack_dir"
    unzip -q "$INSTALLER" -d "$unpack_dir"
  fi
  DOCKER_DIR=$(dirname "$(dirname "$(find "$unpack_dir" -maxdepth 3 -path '*/tak/version.txt' | head -1)")")
  [[ -f $DOCKER_DIR/tak/version.txt ]] || die "Could not find tak/version.txt inside $(basename "$INSTALLER")"
  TAK_DIR=$DOCKER_DIR/tak

  local ver db_name net
  ver=$(tr -d '[:space:]' < "$TAK_DIR/version.txt")
  TAK_CONTAINER=takserver-$ver
  db_name=takserver-db-$ver
  net=takserver-$ver

  # Database password goes into CoreConfig before the images are built.
  local db_pass
  db_pass=$(openssl rand -hex 16)
  if grep -q 'password=""' "$TAK_DIR/CoreConfig.example.xml"; then
    sed -i -E "s#(<connection [^>]*password=\")\"#\1${db_pass}\"#" "$TAK_DIR/CoreConfig.example.xml"
    ok "Set database password in CoreConfig.example.xml"
  fi

  cd "$DOCKER_DIR"
  log "Building images (this takes a few minutes)"
  docker build -t "takserver-db:$ver" -f docker/Dockerfile.takserver-db .
  docker build -t "takserver:$ver" -f docker/Dockerfile.takserver .

  if ! docker network inspect "$net" >/dev/null 2>&1; then docker network create "$net"; fi

  mkdir -p "$DOCKER_DB_DIR"
  if ! container_exists "$db_name"; then
    # Postgres is only reachable on the docker network — not published on the host.
    docker run -dt --restart unless-stopped \
      -v "$DOCKER_DB_DIR":/var/lib/postgresql/data:z \
      -v "$TAK_DIR":/opt/tak:z \
      --network "$net" --network-alias tak-database \
      --name "$db_name" "takserver-db:$ver"
  fi

  if ! container_exists "$TAK_CONTAINER"; then
    local port_args=() p
    for p in $DOCKER_PORTS; do port_args+=(-p "$p:$p"); done
    docker run -dt --restart unless-stopped \
      -v "$TAK_DIR":/opt/tak:z \
      "${port_args[@]}" \
      --network "$net" --name "$TAK_CONTAINER" "takserver:$ver"
  fi
  cd - >/dev/null
  ok "Containers running: $db_name, $TAK_CONTAINER"
}

restart_docker() {
  docker exec -d "$TAK_CONTAINER" bash -c "cd /opt/tak/ && ./configureInDocker.sh"
}
