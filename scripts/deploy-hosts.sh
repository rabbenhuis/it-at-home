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
# Prereqs (env): TF_VAR_pm_api_token_id, TF_VAR_pm_api_token_secret

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

: "${TF_VAR_pm_api_token_id:?set TF_VAR_pm_api_token_id}"
: "${TF_VAR_pm_api_token_secret:?set TF_VAR_pm_api_token_secret}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT/deploy"
HELPER="$ROOT/scripts/_deploy-helpers.py"

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
# SSH users: lxc -> ansible (baked into the templates), vm -> debian (cloud-init).
provision_plan() {
  terraform output -json hosts 2>/dev/null | python3 "$HELPER" provision "$TARGET" "$HOSTS"
}

while IFS='|' read -r name type ip playbook; do
  [[ -z "$name" ]] && continue
  case "$type" in
    vm) user=debian ;;
    *)  user=ansible ;;
  esac

  log "Provisioning $name ($type, $ip) with $playbook as $user"
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  READY=0
  for i in $(seq 1 120); do
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
    echo "WARN: SSH to $ip did not become ready within ~10 min, skipping $name" >&2
    continue
  fi
  (cd "$ROOT/ansible" && ~/.local/bin/ansible-playbook -i "${ip}," -u "$user" -b "playbooks/$playbook")
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