#!/usr/bin/env bash
# Build per-user connection data packages (import in ATAK / WinTAK / iTAK) and collect admin files.

write_server_pref() {
  local user=$1
  cat <<EOF
<?xml version='1.0' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">${CONNECTION_NAME}</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">${SERVER_ADDRESS}:8089:ssl</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/truststore-root.p12</entry>
    <entry key="caPassword" class="class java.lang.String">${CERT_PASS}</entry>
    <entry key="certificateLocation" class="class java.lang.String">cert/${user}.p12</entry>
    <entry key="clientPassword" class="class java.lang.String">${CERT_PASS}</entry>
  </preference>
</preferences>
EOF
}

write_manifest() {
  local user=$1
  cat <<EOF
<MissionPackageManifest version="2">
  <Configuration>
    <Parameter name="uid" value="$(cat /proc/sys/kernel/random/uuid)"/>
    <Parameter name="name" value="${CONNECTION_NAME} - ${user}"/>
    <Parameter name="onReceiveDelete" value="true"/>
  </Configuration>
  <Contents>
    <Content ignore="false" zipEntry="certs/server.pref"/>
    <Content ignore="false" zipEntry="certs/truststore-root.p12"/>
    <Content ignore="false" zipEntry="certs/${user}.p12"/>
  </Contents>
</MissionPackageManifest>
EOF
}

build_packages() {
  local files=$TAK_DIR/certs/files u work
  mkdir -p "$OUTPUT_DIR/packages" "$OUTPUT_DIR/admin"

  for u in $USERS; do
    work=$(mktemp -d)
    mkdir -p "$work/certs" "$work/MANIFEST"
    write_server_pref "$u" > "$work/certs/server.pref"
    write_manifest "$u"    > "$work/MANIFEST/manifest.xml"
    cp "$files/truststore-root.p12" "$files/$u.p12" "$work/certs/"
    rm -f "$OUTPUT_DIR/packages/$u.zip"
    (cd "$work" && zip -qr "$OUTPUT_DIR/packages/$u.zip" MANIFEST certs)
    rm -rf "$work"
    ok "Data package: packages/$u.zip"
  done

  cp "$files/admin.p12" "$files/truststore-root.p12" "$OUTPUT_DIR/admin/"
  ok "Admin browser cert: admin/admin.p12"
}
