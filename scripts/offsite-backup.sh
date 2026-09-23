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

# HiDrive is reached via an rclone WebDAV remote (the Debian restic build has no
# webdav backend, so restic uses its rclone: backend; rclone also serves the
# OneDrive destination later). Build both var blobs as JSON to stay safe against
# special chars in credentials.
RCLONE_JSON="$(HIDRIVE_U="$HIDRIVE_USER" HIDRIVE_P="$HIDRIVE_PASSWORD" \
  python3 -c 'import json, os; print(json.dumps([{"name": "hidrive", "url": "https://webdav.hidrive.strato.com", "user": os.environ["HIDRIVE_U"], "password": os.environ["HIDRIVE_P"]}]))')"

DEST_JSON="$(HIDRIVE_REPO="rclone:hidrive:/users/${HIDRIVE_USER}/backups/unifi01" RESTIC_PW="$RESTIC_PASSWORD_HIDRIVE" \
  python3 -c 'import json, os; print(json.dumps([{"name": "hidrive", "repo": os.environ["HIDRIVE_REPO"], "password": os.environ["RESTIC_PW"]}]))')"

cd "$ROOT/ansible"
ARGS=(-i "${HOST}," -u ansible -b \
  -e "{\"backup_rclone_remotes\": ${RCLONE_JSON}, \"backup_restic_destinations\": ${DEST_JSON}}")
if [[ "$CHECK" -eq 1 ]]; then
  ARGS+=(--check --diff)
fi
~/.local/bin/ansible-playbook "${ARGS[@]}" playbooks/backup.yml