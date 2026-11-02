#!/usr/bin/env bash
# Certificates (Appendix B of the guide) and CoreConfig TLS settings.

configure_cert_metadata() {
  local f=$TAK_DIR/certs/cert-metadata.sh
  [[ -f $f ]] || die "Missing $f"
  set_shell_var "$f" COUNTRY             "$CERT_COUNTRY"
  set_shell_var "$f" STATE               "$CERT_STATE"
  set_shell_var "$f" CITY                "$CERT_CITY"
  set_shell_var "$f" ORGANIZATION        "$CERT_ORG"
  set_shell_var "$f" ORGANIZATIONAL_UNIT "$CERT_OU"
  set_shell_var "$f" CAPASS              "$CERT_PASS"
  ok "Wrote certificate settings to cert-metadata.sh"
}

generate_certs() {
  local files=$TAK_DIR/certs/files u

  if [[ $FORCE_CERTS == 1 && -d $files ]]; then
    local backup
    backup="$files.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$files" "$backup"
    warn "Moved existing certificates to $backup"
  fi

  if [[ -f $files/ca.pem ]]; then
    ok "Root CA already exists — keeping it"
  else
    tak_exec "cd /opt/tak/certs && ./makeRootCa.sh --ca-name '$CA_NAME'"
    ok "Created root CA '$CA_NAME'"
  fi

  if [[ -f $files/$SERVER_CERT_NAME.jks ]]; then
    ok "Server certificate already exists"
  else
    tak_exec "cd /opt/tak/certs && ./makeCert.sh server '$SERVER_CERT_NAME'"
    ok "Created server certificate '$SERVER_CERT_NAME'"
  fi

  for u in admin $USERS; do
    if [[ -f $files/$u.p12 ]]; then
      ok "Client certificate for $u already exists"
    else
      tak_exec "cd /opt/tak/certs && ./makeCert.sh client '$u'"
      ok "Created client certificate for $u"
    fi
  done
}

# Point CoreConfig at the right keystore and passwords. Edits both CoreConfig.xml and the
# example it's generated from, whichever exist, so first start picks the settings up too.
configure_coreconfig() {
  local cc pass_esc
  pass_esc=$(printf '%s' "$CERT_PASS" | sed -e 's/[#&]/\\&/g')
  for cc in "$TAK_DIR/CoreConfig.xml" "$TAK_DIR/CoreConfig.example.xml"; do
    [[ -f $cc ]] || continue
    sed -i -E \
      -e "s#keystorePass=\"[^\"]*\"#keystorePass=\"${pass_esc}\"#g" \
      -e "s#truststorePass=\"[^\"]*\"#truststorePass=\"${pass_esc}\"#g" \
      -e "s#keystoreFile=\"certs/files/takserver\.jks\"#keystoreFile=\"certs/files/${SERVER_CERT_NAME}.jks\"#g" \
      "$cc"
  done
  ok "CoreConfig TLS settings updated"
}

wait_for_tak() {
  local deadline=$((SECONDS + START_TIMEOUT))
  log "Waiting for TAK Server to listen on 8443 (up to ${START_TIMEOUT}s — first start is slow)"
  until (exec 3<>/dev/tcp/127.0.0.1/8443) 2>/dev/null; do
    if (( SECONDS > deadline )); then
      die "TAK Server did not come up. Check logs in $TAK_DIR/logs/ (takserver-messaging.log, takserver-api.log)."
    fi
    sleep 5
  done
  ok "TAK Server is listening"
}

# UserManager talks to the running server, which can lag behind the port opening.
user_manager() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if tak_exec_root "cd /opt/tak && java -jar utils/UserManager.jar $1"; then return 0; fi
    log "UserManager not ready yet (attempt $attempt) — retrying in 10s"
    sleep 10
  done
  return 1
}

register_users() {
  user_manager "certmod -A certs/files/admin.pem" || die "Could not register admin certificate"
  ok "admin certificate has admin rights"

  if [[ -z $USER_GROUPS ]]; then return 0; fi
  local u g group_args=''
  for g in $USER_GROUPS; do group_args+=" -g '$g'"; done
  for u in $USERS; do
    user_manager "certmod$group_args certs/files/$u.pem" || die "Could not add $u to groups"
    ok "$u added to groups: $USER_GROUPS"
  done
}
