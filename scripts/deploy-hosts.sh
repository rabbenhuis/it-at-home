#!/usr/bin/env bash
set -euo pipefail

# Deploy hosts from the deployment map (deploy/deployments.tf):
#   terraform apply clones each selected host from its template, then ansible
#   provisions the hosts that specify a playbook.
#
# Scope (optional, combine freely):
#   ./deploy-hosts.sh                    # all hosts
#   ./deploy-hosts.sh pve1               # only pve1 (amd64) hosts
#   ./deploy-hosts.sh pve2               # only pve2 (arm64) hosts
#   ./deploy-hosts.sh --hosts web1,db1   # only the named hosts (node auto-detected)
#   ./deploy-hosts.sh destroy [scope]    # tear down (same scope options)
#
# Scoped deploys use `-target` so hosts outside the scope are left untouched.
#
# Prereqs (env): TF_VAR_pm_api_token_id + per-node TF_VAR_pm_api_token_secret_pve1/2
# (or BWS_ACCESS_TOKEN + BWS_PROJECT_ID; see scripts/_load-creds.sh)
#
# TEMP pve2: pve2 is not installed yet, so deploy/main.tf has the pve2
# variable/provider/module commented out and this script only loads pve1 creds.
# When pve2 comes online, uncomment those blocks and restore the --all load.

MODE=apply
TARGET=""
HOSTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    destroy)   MODE=destroy; shift ;;
    pve1|pve2) TARGET="$1"; shift ;;
    --hosts)   HOSTS="$2"; shift 2 ;;
    --hosts=*) HOSTS="${1#--hosts=}"; shift ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      echo "Usage: $0 [destroy] [pve1|pve2] [--hosts a,b]" >&2
      exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT/deploy"
HELPER="$ROOT/scripts/_deploy-helpers.py"

# Credentials: exported TF_VAR_* or fetched from Bitwarden Secrets Manager
# (bws). TEMP pve2: only pve1 creds are loaded because pve2 is not installed
# yet (see deploy/main.tf). When pve2 comes online, restore:
#   load_pm_creds --all
#   : "${TF_VAR_pm_api_token_secret_pve2:?}"
source "$ROOT/scripts/_load-creds.sh"
load_pm_creds pve1
: "${TF_VAR_pm_api_token_id:?}"
: "${TF_VAR_pm_api_token_secret_pve1:?}"

# Postfix relay SMTP credentials (infra-core role). From exported env vars or
# Bitwarden Secrets Manager (bws); never committed. Passed to ansible as -e
# vars for the infra-core playbook.
POSTFIX_SMTP_USER="${POSTFIX_SMTP_USER:-}"
POSTFIX_SMTP_PASSWORD="${POSTFIX_SMTP_PASSWORD:-}"
if [[ -z "$POSTFIX_SMTP_USER" && -n "${BWS_ACCESS_TOKEN:-}" && -n "${BWS_PROJECT_ID:-}" ]]; then
  POSTFIX_SMTP_USER="$(bws_value POSTFIX_SMTP_USER 2>/dev/null || true)"
fi
if [[ -z "$POSTFIX_SMTP_PASSWORD" && -n "${BWS_ACCESS_TOKEN:-}" && -n "${BWS_PROJECT_ID:-}" ]]; then
  POSTFIX_SMTP_PASSWORD="$(bws_value POSTFIX_SMTP_PASSWORD 2>/dev/null || true)"
fi

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

cd "$DEPLOY_DIR"

if [[ ! -d .terraform ]]; then
  log "Initializing terraform (first run)"
  terraform init -input=false
fi

# Resolve the module address for a host, e.g. module.deploy_pve1["web1"].
# Tries terraform state list first (cheap, no API; covers already-applied
# hosts), then a terraform plan (covers hosts not yet in state).
resolve_host() {
  local host="$1" addr=""
  addr=$(terraform state list 2>/dev/null | grep -oE 'module\.deploy_pve[12]\["'"$host"'"\]' | head -1 || true)
  if [[ -z "$addr" ]]; then
    addr=$(terraform plan -no-color -json 2>/dev/null | python3 "$HELPER" resolve "$host" || true)
  fi
  if [[ -z "$addr" ]]; then
    echo "ERROR: could not determine which node host '$host' is on (is it in deploy/deployments.tf?)" >&2
    exit 1
  fi
  echo "$addr"
}

# Build the -target argument list for the requested scope.
TARGET_ARGS=()
if [[ -n "$HOSTS" ]]; then
  IFS=',' read -ra host_arr <<< "$HOSTS"
  for h in "${host_arr[@]}"; do
    if [[ -n "$TARGET" ]]; then
      TARGET_ARGS+=("-target" "module.deploy_${TARGET}[\"${h}\"]")
    else
      TARGET_ARGS+=("-target" "$(resolve_host "$h")")
    fi
  done
elif [[ -n "$TARGET" ]]; then
  TARGET_ARGS+=("-target" "module.deploy_${TARGET}")
fi

if [[ "$MODE" == "destroy" ]]; then
  log "Destroying (${TARGET_ARGS[*]:-all hosts})"
  terraform destroy -auto-approve "${TARGET_ARGS[@]}"
  exit 0
fi

log "Applying (${TARGET_ARGS[*]:-all hosts})"
terraform apply -auto-approve "${TARGET_ARGS[@]}"

# Ansible provisioning for the hosts in this run's scope that specify a playbook.
# SSH user is always `ansible`: baked into the templates (LXC and VM) by the
# base role, with passwordless sudo. Computed from the config (terraform console)
# rather than `terraform output`, because `-target` applies never persist
# outputs in the state file.
provision_plan() {
  local expr='jsonencode({ for name, h in local.deployments : name => { type = h.type, target = h.target, ip = h.ip, playbook = try(local.roles[try(h.role, "")], "") } })'
  terraform console -no-color <<< "$expr" | python3 "$HELPER" provision "$TARGET" "$HOSTS"
}

while IFS='|' read -r name type ip playbook; do
  [[ -z "$name" ]] && continue
  user=ansible

  # The infra-core playbook (postfix relay) needs the SMTP credentials from bws.
  POSTFIX_EXTRA_ARGS=()
  if [[ "$playbook" == "infra-core.yml" ]]; then
    if [[ -n "$POSTFIX_SMTP_USER" && -n "$POSTFIX_SMTP_PASSWORD" ]]; then
      POSTFIX_EXTRA_ARGS+=(-e "postfix_smtp_user=$POSTFIX_SMTP_USER" -e "postfix_smtp_password=$POSTFIX_SMTP_PASSWORD")
    else
      echo "WARN: POSTFIX_SMTP_USER/PASSWORD not set (env or bws); postfix relay will render empty credentials" >&2
    fi
  fi

  log "Provisioning $name ($type, $ip) with $playbook as $user"
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  # First boot runs firstboot.service (machine-id, SSH host keys, aideinit,
  # rkhunter) before ssh starts, so SSH can take several minutes to appear.
  READY=0
  for i in $(seq 1 180); do
    if timeout 3 bash -c ">/dev/tcp/$ip/22" 2>/dev/null && \
       timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=4 \
         -o StrictHostKeyChecking=accept-new "$user@$ip" \
         '! pgrep -x apt-get >/dev/null 2>&1 && ! pgrep -x dpkg >/dev/null 2>&1 && ! pgrep -x apt >/dev/null 2>&1' >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 5
  done
  if [[ "$READY" -ne 1 ]]; then
    echo "WARN: SSH to $ip did not become ready within ~15 min, skipping $name" >&2
    continue
  fi
  (cd "$ROOT/ansible" && ~/.local/bin/ansible-playbook -i "${ip}," -u "$user" -b "${POSTFIX_EXTRA_ARGS[@]}" "playbooks/$playbook")
done < <(provision_plan)

log "Done. Deployed hosts (see deploy/deployments.tf):"
terraform output -json hosts 2>/dev/null | python3 -c '
import json, sys
try:
    hosts = json.load(sys.stdin)
except Exception:
    hosts = {}
print(f"{len(hosts)} host(s) in the deployment map")
'