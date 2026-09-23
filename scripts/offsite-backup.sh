#!/usr/bin/env bash
set -euo pipefail

# Provision the offsite restic backups (offsite-backup role) on a host.
#   ./offsite-backup.sh <host-ip> [--check]
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
if [[ "${2:-}" == "--check" ]]; then
  CHECK=1
fi
HOST="${1:?usage: offsite-backup.sh <host-ip> [--check]}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Credentials: exported or fetched from bws.
source "$ROOT/scripts/_load-creds.sh"
load_backup_creds
: "${HIDRIVE_USER:?}"
: "${HIDRIVE_PASSWORD:?}"
: "${RESTIC_PASSWORD_HIDRIVE:?}"

# Build the extra-vars object as JSON. Destinations go through restic's rclone:
# backend (the Debian restic build has no webdav backend; rclone serves both the
# HiDrive WebDAV remote and, when configured, the OneDrive remote).
VARS_JSON="$(HIDRIVE_U="$HIDRIVE_USER" HIDRIVE_P="$HIDRIVE_PASSWORD" \
  RESTIC_PW_HIDRIVE="$RESTIC_PASSWORD_HIDRIVE" \
  ONEDRIVE_CFG="${ONEDRIVE_RCLONE_CONFIG:-}" \
  RESTIC_PW_ONEDRIVE="${RESTIC_PASSWORD_ONEDRIVE:-}" \
  python3 -c '
import json, os
remotes = [{"name": "hidrive", "url": "https://webdav.hidrive.strato.com",
            "user": os.environ["HIDRIVE_U"], "password": os.environ["HIDRIVE_P"]}]
dests = [{"name": "hidrive",
          "repo": "rclone:hidrive:/users/%s/backups/unifi01" % os.environ["HIDRIVE_U"],
          "password": os.environ["RESTIC_PW_HIDRIVE"]}]
v = {"backup_rclone_remotes": remotes, "backup_restic_destinations": dests}
if os.environ["ONEDRIVE_CFG"]:
    if not os.environ["RESTIC_PW_ONEDRIVE"]:
        raise SystemExit("ONEDRIVE_RCLONE_CONFIG set but RESTIC_PASSWORD_ONEDRIVE missing")
    v["backup_rclone_extra_config"] = os.environ["ONEDRIVE_CFG"]
    dests.append({"name": "onedrive", "repo": "rclone:onedrive:/backups/unifi01",
                  "password": os.environ["RESTIC_PW_ONEDRIVE"]})
print(json.dumps(v))
')"

cd "$ROOT/ansible"
ARGS=(-i "${HOST}," -u ansible -b -e "$VARS_JSON")
if [[ "$CHECK" -eq 1 ]]; then
  ARGS+=(--check --diff)
fi
~/.local/bin/ansible-playbook "${ARGS[@]}" playbooks/backup.yml