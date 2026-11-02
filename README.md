# tak-builder

Builds a TAK Server from scratch with one command: OS prep, TAK install (native package or Docker),
certificates, admin and user setup, client data packages and firewall. Based on the TAK Server 5.7
Configuration Guide.

## Quick start

1. Download installers from tak.gov and drop them in `installers/` (keep as many versions as you like):
   - `takserver_<ver>_all.deb` for Ubuntu 22.04 / Raspberry Pi OS 64-bit
   - `takserver-<ver>.noarch.rpm` for Rocky / RHEL 8–9
   - `takserver-docker-<ver>.zip` for Docker on any of the above
2. Copy this folder to the fresh server:
   `scp -r tak-builder user@SERVER:~`
3. On the server:
   `cd ~/tak-builder && sudo ./takbuild.sh`

The script detects the OS and hardware, lists only the installers that fit that machine (newest first),
asks for anything not in the config, shows a summary, then builds the server.

When it's done, `output/<host>-<timestamp>/` holds:
- `packages/<user>.zip`: import into ATAK / WinTAK / iTAK to connect
- `admin/admin.p12`: import into your browser for https://SERVER:8443
- `takbuild.log`: full log of the run

## Saved configs

`config/default.conf` documents every setting. For repeat builds, copy an example and edit it:

```
cp config/examples/cloud-vps.conf config/client-x.conf
sudo ./takbuild.sh -c config/client-x.conf        # prompts, prefilled from the config
sudo ./takbuild.sh -c config/client-x.conf -y     # no prompts at all
```

| Example                | For                                                                  |
|------------------------|----------------------------------------------------------------------|
| `raspberry-pi.conf`    | Pi 4/5 field kit: runs `takserver-noplugins`, longer startup timeout |
| `cloud-vps.conf`       | VPS with a public IP, custom cert password, user group               |
| `docker-lab.conf`      | Throwaway lab server from the Docker bundle                          |

## Options

```
-c, --config FILE     settings file layered over config/default.conf
-i, --installer FILE  skip the version menu
-y, --yes             unattended
    --force-certs     back up existing certs and create a new CA
```

## Re-running

Safe to re-run on the same machine. An installed package, running containers and existing certificates
are detected and kept, so re-running with more names in `USERS` just adds those users and their packages.

## Hardware handling

- Raspberry Pi or less than 8 GB RAM: uses the `takserver-noplugins` service (messaging + API only).
- Warns below the guide's minimums (4 cores, 8 GB RAM, 40 GB disk).
- Two-server installs, the hardened Docker bundle and Federation Hub are not handled yet.
