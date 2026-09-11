#!/usr/bin/env bash
set -euo pipefail

# Build a versioned LXC template:
#   1. terraform apply (creates the build container from upstream or a clone)
#   2. ansible-playbook (provisions + hardens it)
#   3. stop container, convert to template via the Proxmox API
#   4. terraform state rm (the template is now the artifact, not the build resource)
#
# Prereqs (env): TF_VAR_pm_api_token_id, TF_VAR_pm_api_token_secret
# Usage: ./build-template.sh <role> <version> <vmid> <node>

ROLE="${1:?usage: build-template.sh <role> <version> <vmid> <node>}"
VERSION="${2:?}"
VMID="${3:?}"
NODE="${4:-bm-pve-prd-01}"

: "${TF_VAR_pm_api_token_id:?set TF_VAR_pm_api_token_id}"
: "${TF_VAR_pm_api_token_secret:?set TF_VAR_pm_api_token_secret}"

API_URL="https://bm-pve-prd-01.abbenhuis.internal:8006/api2/json"
AUTH="PVEAPIToken=${TF_VAR_pm_api_token_id}=${TF_VAR_pm_api_token_secret}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

log "Applying terraform (role=$ROLE version=$VERSION vmid=$VMID)"
cd "$ROOT"
terraform apply -auto-approve \
  -var "template_role=$ROLE" \
  -var "template_version=$VERSION" \
  -var "template_vmid=$VMID"

IP=$(terraform output -raw "${ROLE}_ip" | cut -d/ -f1)

if [[ "$ROLE" == "native" ]]; then
  ANSIBLE_USER=root
  PLAY="playbooks/harden.yml"
else
  ANSIBLE_USER=ansible
  PLAY="playbooks/${ROLE}.yml"
fi

log "Provisioning with ansible (role=$ROLE host=$IP user=$ANSIBLE_USER)"
cd "$ROOT/ansible"

log "Waiting for SSH to become ready on $IP..."
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
READY=0
for i in $(seq 1 120); do
  if timeout 3 bash -c ">/dev/tcp/$IP/22" 2>/dev/null && \
     timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=4 \
       -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$IP" true >/dev/null 2>&1; then
    READY=1
    log "SSH ready after ~$((i * 5))s"
    break
  fi
  sleep 5
done
if [[ "$READY" -ne 1 ]]; then
  echo "ERROR: SSH to $IP did not become ready within ~10 minutes" >&2
  exit 1
fi

~/.local/bin/ansible-playbook -i "${IP}," -u "$ANSIBLE_USER" -b "$PLAY"

log "Stopping container $VMID"
curl -ksS -X POST -H "Authorization: $AUTH" "$API_URL/nodes/$NODE/lxc/$VMID/status/stop"

log "Converting container $VMID to template"
curl -ksS -X POST -H "Authorization: $AUTH" "$API_URL/nodes/$NODE/lxc/$VMID/template"

TEMPLATE_NAME="tmpl-debian13-${ROLE}-v${VERSION}"
log "Renaming template to $TEMPLATE_NAME"
curl -ksS -X PUT -H "Authorization: $AUTH" \
  "$API_URL/nodes/$NODE/lxc/$VMID/config" \
  --data-urlencode "hostname=$TEMPLATE_NAME"

log "Forgetting build resource in terraform state"
cd "$ROOT"
STATE_ADDR="module.template_${ROLE}[0].proxmox_virtual_environment_container.build"
if terraform state rm "$STATE_ADDR" >/dev/null 2>&1; then
  log "Removed $STATE_ADDR from state"
else
  log "WARN: could not state rm $STATE_ADDR (leaving state as-is)"
fi

log "Done: $TEMPLATE_NAME (vmid $VMID)"