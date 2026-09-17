#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a Proxmox VE host from a fresh install (or register an existing token).
#
#   ./bootstrap-pve.sh pve1                  # full bootstrap (needs root SSH)
#   ./bootstrap-pve.sh pve1 --register-only  # store an existing token in bws (no SSH)
#
# Full bootstrap:
#   1. SSH as root and, via pveum, ensure user terraform@pve exists and create
#      the API token 'infra' (--privsep 0). This is the chicken-egg step the
#      pve role cannot do: the one-time token secret must be captured here.
#   2. Store the token id + per-node secret in Bitwarden Secrets Manager (bws):
#        TF_VAR_pm_api_token_id           = terraform@pve!infra   (shared, created once)
#        TF_VAR_pm_api_token_secret_pve1/2 = <node secret>
#   3. Auto-run scripts/pve-hosts.sh --bootstrap. That runs the pve role, which
#      owns the rest of the access control (TerraForm-Infra role, ACLs, PAM
#      users) plus OS users and hardening.
#
# --register-only skips SSH/pveum (e.g. on pve1 which is already configured and
# hardened): it just stores the existing token id + secret for the node in bws.
#
# Prereqs (env): PVE_ROOT_PASSWORD (full only), BWS_ACCESS_TOKEN, BWS_PROJECT_ID,
# sshpass (full only).

MODE=full
NODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    pve1|pve2) NODE="$1"; shift ;;
    --register-only) MODE=register; shift ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      echo "Usage: $0 pve1|pve2 [--register-only]" >&2
      exit 1 ;;
  esac
done

NODE="${NODE:?usage: bootstrap-pve.sh pve1|pve2 [--register-only]}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${BWS_ACCESS_TOKEN:?set BWS_ACCESS_TOKEN}"
: "${BWS_PROJECT_ID:?set BWS_PROJECT_ID}"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

node_ip() {
  case "$1" in
    pve1) echo "192.168.70.64" ;;
    pve2) echo "bm-pve-prd-02.abbenhuis.internal" ;;
  esac
}

# --- bws helpers ----------------------------------------------------------

bws_secret_id() {
  local key="$1"
  bws secret list "$BWS_PROJECT_ID" 2>/dev/null | python3 -c '
import json, sys
key = sys.argv[1]
try:
    for s in json.load(sys.stdin):
        if s.get("key") == key:
            print(s["id"]); sys.exit(0)
except Exception:
    pass
' "$key"
}

bws_value() {
  local key="$1"
  bws secret list "$BWS_PROJECT_ID" 2>/dev/null | python3 -c '
import json, sys
key = sys.argv[1]
try:
    for s in json.load(sys.stdin):
        if s.get("key") == key:
            print(s.get("value", "")); sys.exit(0)
except Exception:
    pass
sys.exit(1)
' "$key"
}

bws_set_secret() {
  local key="$1" value="$2" id
  id="$(bws_secret_id "$key")"
  if [[ -n "$id" ]]; then
    log "Updating bws secret $key"
    bws secret edit "$id" --value "$value" >/dev/null
  else
    log "Creating bws secret $key"
    bws secret create "$key" "$value" "$BWS_PROJECT_ID" >/dev/null
  fi
}

# --- credential input ------------------------------------------------------

TOKEN_ID="${TF_VAR_pm_api_token_id:-terraform@pve!infra}"
SECRET_KEY="TF_VAR_pm_api_token_secret_${NODE}"
SECRET="${!SECRET_KEY:-}"

if [[ -z "$SECRET" ]]; then
  if [[ "$MODE" == "register" ]]; then
    if [[ ! -t 0 ]]; then
      echo "ERROR: no interactive terminal for the secret prompt; export ${SECRET_KEY} instead" >&2
      exit 1
    fi
    read -r -p "Token id (default $TOKEN_ID): " ans
    [[ -n "$ans" ]] && TOKEN_ID="$ans"
    read -r -s -p "Token secret for $NODE: " SECRET
    echo
  else
    : "${PVE_ROOT_PASSWORD:?set PVE_ROOT_PASSWORD for the full bootstrap}"
    command -v sshpass >/dev/null || { echo "ERROR: sshpass is required" >&2; exit 1; }
    # For the full bootstrap the secret is captured from pveum output below.
    SECRET=""
  fi
fi

# --- full bootstrap: ensure user + create token over root SSH ---------------

if [[ "$MODE" == "full" ]]; then
  IP="$(node_ip "$NODE")"
  log "Bootstrapping the PVE API token on $NODE ($IP) as root"
  ssh-keygen -R "$IP" >/dev/null 2>&1 || true

  TOKEN_OUT="$(sshpass -p "$PVE_ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    -o PubkeyAuthentication=no -o PreferredAuthentications=password \
    "root@$IP" bash -s <<'EOF'
set -e
pveum user list --output-format json | grep -qE '"userid"[[:space:]]*:[[:space:]]*"terraform@pve"' || pveum user add terraform@pve
if pveum user token list terraform@pve --output-format json | grep -qE '"tokenid"[[:space:]]*:[[:space:]]*"infra"'; then
  echo "TOKEN_EXISTS"
else
  pveum user token add terraform@pve infra --privsep 0 --output-format json
fi
EOF
  )"

  if grep -q '^TOKEN_EXISTS' <<<"$TOKEN_OUT"; then
    if [[ -n "$(bws_secret_id "$SECRET_KEY")" ]]; then
      log "Token already exists and its secret is already in bws; skipping token creation"
    else
      log "WARN: token 'infra' already exists but its secret is not in bws."
      echo "Recreating it now; the previous token value is revoked." >&2
      TOKEN_OUT="$(sshpass -p "$PVE_ROOT_PASSWORD" ssh \
        -o StrictHostKeyChecking=accept-new \
        -o PubkeyAuthentication=no -o PreferredAuthentications=password \
        "root@$IP" 'pveum user token remove terraform@pve infra; pveum user token add terraform@pve infra --privsep 0 --output-format json')"
    fi
  fi

  if [[ -z "$SECRET" ]]; then
    if [[ -n "$(bws_secret_id "$SECRET_KEY")" ]]; then
      # Token already existed and its secret is stored in bws; nothing to do.
      SECRET="$(bws_value "$SECRET_KEY")"
    else
      SECRET="$(python3 -c '
import json, sys
try:
    print(json.loads(sys.stdin.read())["secret"])
except Exception as e:
    sys.stderr.write("could not parse pveum token output: %s\n" % e)
    sys.exit(1)
' <<<"$TOKEN_OUT")"
    fi
  fi
fi

# --- store in bws ----------------------------------------------------------

bws_set_secret TF_VAR_pm_api_token_id "$TOKEN_ID"
bws_set_secret "$SECRET_KEY" "$SECRET"

log "Stored TF_VAR_pm_api_token_id and ${SECRET_KEY} in bws"

# --- auto-run the OS-side provisioning -------------------------------------

if [[ "$MODE" == "full" ]]; then
  log "Auto-running scripts/pve-hosts.sh $NODE --bootstrap"
  "$ROOT/scripts/pve-hosts.sh" "$NODE" --bootstrap
fi

log "Done. You can now run terraform/build/deploy scripts with BWS_ACCESS_TOKEN exported."