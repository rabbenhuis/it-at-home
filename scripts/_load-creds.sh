#!/usr/bin/env bash
# Shared credential loader for the Terraform scripts (sourced, not executed).
#
# Terraform needs a Proxmox API token per node:
#   TF_VAR_pm_api_token_id            (identical on every node: terraform@pve!infra)
#   TF_VAR_pm_api_token_secret_pve1
#   TF_VAR_pm_api_token_secret_pve2
#
# If the variables are not already exported, they are injected from Bitwarden
# Secrets Manager (bws) using the secret keys above. Requires BWS_ACCESS_TOKEN
# and BWS_PROJECT_ID exported in the shell.
#
# Usage (after `source _load-creds.sh`):
#   load_pm_creds pve1        # ensure the shared id + pve1 secret
#   load_pm_creds --all       # ensure the shared id + both node secrets
#
# Secrets can also be kept in the terminal as before (export TF_VAR_* directly);
# bws is only a fallback for when they are unset.

bws_value() {
  local key="$1"
  : "${BWS_ACCESS_TOKEN:?BWS_ACCESS_TOKEN not set (or export TF_VAR_pm_api_token_* directly)}"
  : "${BWS_PROJECT_ID:?BWS_PROJECT_ID not set (or export TF_VAR_pm_api_token_* directly)}"
  bws secret list "$BWS_PROJECT_ID" 2>/dev/null | python3 -c '
import json, sys
key = sys.argv[1]
try:
    for s in json.load(sys.stdin):
        if s.get("key") == key:
            print(s.get("value", ""))
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
' "$key"
}

load_pm_creds() {
  local want_all=0 nodes=() arg
  for arg in "$@"; do
    case "$arg" in
      --all) want_all=1 ;;
      pve1|pve2) nodes+=("$arg") ;;
      *) echo "load_pm_creds: unknown argument '$arg' (expected pve1|pve2|--all)" >&2; return 1 ;;
    esac
  done
  if [[ "$want_all" -eq 1 ]]; then
    nodes=(pve1 pve2)
  fi
  if [[ ${#nodes[@]} -eq 0 ]]; then
    echo "load_pm_creds: specify a node (pve1|pve2) or --all" >&2
    return 1
  fi

  if [[ -z "${TF_VAR_pm_api_token_id:-}" ]]; then
    local id
    id="$(bws_value TF_VAR_pm_api_token_id)" || {
      echo "load_pm_creds: TF_VAR_pm_api_token_id is not exported and not found in bws" >&2
      return 1
    }
    export TF_VAR_pm_api_token_id="$id"
  fi

  local n var val
  for n in "${nodes[@]}"; do
    var="TF_VAR_pm_api_token_secret_${n}"
    if [[ -z "${!var:-}" ]]; then
      val="$(bws_value "$var")" || {
        echo "load_pm_creds: ${var} is not exported and not found in bws" >&2
        return 1
      }
      export "$var=$val"
    fi
  done
}

# Offsite restic backup credentials (scripts/offsite-backup.sh). Falls back to
# bws under the same keys when not exported:
#   HIDRIVE_USER            e.g. mabbenhuis
#   HIDRIVE_PASSWORD        Strato HiDrive WebDAV password
#   RESTIC_PASSWORD_HIDRIVE restic repo encryption password for the HiDrive repo
# Optional (OneDrive destination):
#   ONEDRIVE_RCLONE_CONFIG  rclone.conf blob containing the [onedrive] remote
#   RESTIC_PASSWORD_ONEDRIVE restic repo encryption password for the OneDrive repo
load_backup_creds() {
  local key val
  for key in HIDRIVE_USER HIDRIVE_PASSWORD RESTIC_PASSWORD_HIDRIVE; do
    if [[ -z "${!key:-}" ]]; then
      val="$(bws_value "$key")" || {
        echo "load_backup_creds: $key is not exported and not found in bws" >&2
        return 1
      }
      export "$key=$val"
    fi
  done
  # OneDrive secrets are optional (only fetched when bws is configured).
  for key in ONEDRIVE_RCLONE_CONFIG RESTIC_PASSWORD_ONEDRIVE; do
    if [[ -z "${!key:-}" && -n "${BWS_ACCESS_TOKEN:-}" && -n "${BWS_PROJECT_ID:-}" ]]; then
      val="$(bws_value "$key" 2>/dev/null)" || true
      if [[ -n "$val" ]]; then
        export "$key=$val"
      fi
    fi
  done
}

# MQTT broker (mosquitto) per-service user passwords (scripts/deploy-hosts.sh).
# Falls back to bws under the same keys when not exported:
#   MOSQUITTO_PASSWORD_HASS        Home Assistant MQTT user password
#   MOSQUITTO_PASSWORD_ZIGBEE2MQTT zigbee2mqtt MQTT user password
load_mqtt_creds() {
  local key val
  for key in MOSQUITTO_PASSWORD_HASS MOSQUITTO_PASSWORD_ZIGBEE2MQTT; do
    if [[ -z "${!key:-}" ]]; then
      val="$(bws_value "$key")" || {
        echo "load_mqtt_creds: $key is not exported and not found in bws" >&2
        return 1
      }
      export "$key=$val"
    fi
  done
}