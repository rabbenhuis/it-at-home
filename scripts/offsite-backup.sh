#!/usr/bin/env bash
set -euo pipefail

# Provision the offsite restic backups (offsite-backup role) on a host.
#   ./offsite-backup.sh <host-ip> <hostname> [--check]
#
# <hostname> selects the per-host config in playbooks/backup.yml (paths,
# retention, schedule) and names the restic repo folders (backups/<hostname>).
# Existing callers with just <host-ip> default to 'unifi01' for backward compat.
#
# Loads credentials from bws (or exported env) and runs playbooks/backup.yml,
# passing the restic destinations (repo URLs + passwords) as extra vars.
#
# Prereqs (env): BWS_ACCESS_TOKEN + BWS_PROJECT_ID, with secrets:
#   HIDRIVE_USER, HIDRIVE_PASSWORD, RESTIC_PASSWORD_HIDRIVE
# (or export those three directly).
#
# --check is a dry-run that never applies.

CHECK=0
HOST=""
HOSTNAME="unifi01"
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    *)
      if [[ -z "$HOST" ]]; then
        HOST="$a"
      elif [[ "$HOSTNAME" == "unifi01" && "$a" != "unifi01" ]]; then
        HOSTNAME="$a"
      fi
      ;;
  esac
done
: "${HOST:?usage: offsite-backup.sh <host-ip> [hostname] [--check]}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Credentials: exported or fetched from bws.
source "$ROOT/scripts/_load-creds.sh"
load_backup_creds
: "${HIDRIVE_USER:?}"
: "${HIDRIVE_PASSWORD:?}"
: "${RESTIC_PASSWORD_HIDRIVE:?}"

# Build the extra-vars object as JSON. Destinations go through restic's rclone:
# backend (the Debian restic build has no webdav backend; rclone serves both the
# HiDrive WebDAV remote and, when configured, the OneDrive remote). Repo folders
# are per host (backups/<hostname>).
VARS_JSON="$(HIDRIVE_U="$HIDRIVE_USER" HIDRIVE_P="$HIDRIVE_PASSWORD" \
  RESTIC_PW_HIDRIVE="$RESTIC_PASSWORD_HIDRIVE" \
  ONEDRIVE_CFG="${ONEDRIVE_RCLONE_CONFIG:-}" \
  RESTIC_PW_ONEDRIVE="${RESTIC_PASSWORD_ONEDRIVE:-}" \
  B_HOST="$HOSTNAME" \
  python3 -c '
import json, os
host = os.environ["B_HOST"]
remotes = [{"name": "hidrive", "url": "https://webdav.hidrive.strato.com",
            "user": os.environ["HIDRIVE_U"], "password": os.environ["HIDRIVE_P"]}]
dests = [{"name": "hidrive",
          "repo": "rclone:hidrive:/users/%s/backups/%s" % (os.environ["HIDRIVE_U"], host),
          "password": os.environ["RESTIC_PW_HIDRIVE"]}]
v = {"backup_host": host,
     "backup_rclone_remotes": remotes, "backup_restic_destinations": dests}
if os.environ["ONEDRIVE_CFG"]:
    if not os.environ["RESTIC_PW_ONEDRIVE"]:
        raise SystemExit("ONEDRIVE_RCLONE_CONFIG set but RESTIC_PASSWORD_ONEDRIVE missing")
    v["backup_rclone_extra_config"] = os.environ["ONEDRIVE_CFG"]
    dests.append({"name": "onedrive", "repo": "rclone:onedrive:/backups/%s" % host,
                  "password": os.environ["RESTIC_PW_ONEDRIVE"]})
print(json.dumps(v))
')"

cd "$ROOT/ansible"
ARGS=(-i "${HOST}," -u ansible -b -e "$VARS_JSON")
if [[ "$CHECK" -eq 1 ]]; then
  ARGS+=(--check --diff)
fi
~/.local/bin/ansible-playbook "${ARGS[@]}" playbooks/backup.yml