#!/usr/bin/env bash
set -euo pipefail

# Build a versioned template (LXC or VM):
#   1. terraform apply (creates the build instance from upstream / a clone / cloud image)
#   2. ansible-playbook (provisions + hardens it)
#   3. stop instance, convert to template via the Proxmox API
#   4. terraform state rm (the template is now the artifact, not the build resource)
#
# Roles: native (LXC, root SSH), podman/docker (LXC, ansible SSH),
#        vm (QEMU, debian SSH via cloud-init).
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

case "$ROLE" in
  native)
    ANSIBLE_USER=root
    PLAY="playbooks/harden.yml"
    API_PATH="lxc"; RENAME_PARAM="hostname"
    STATE_ADDR="module.template_native[0].proxmox_virtual_environment_container.build"
    ;;
  vm)
    ANSIBLE_USER=debian
    PLAY="playbooks/vm.yml"
    API_PATH="qemu"; RENAME_PARAM="name"
    STATE_ADDR="module.template_vm[0].proxmox_virtual_environment_vm.build"
    ;;
  *)
    ANSIBLE_USER=ansible
    PLAY="playbooks/${ROLE}.yml"
    API_PATH="lxc"; RENAME_PARAM="hostname"
    STATE_ADDR="module.template_${ROLE}[0].proxmox_virtual_environment_container.build"
    ;;
esac

log "Applying terraform (role=$ROLE version=$VERSION vmid=$VMID)"
cd "$ROOT"
terraform apply -auto-approve \
  -var "template_role=$ROLE" \
  -var "template_version=$VERSION" \
  -var "template_vmid=$VMID"

IP=$(terraform output -raw "${ROLE}_ip" | cut -d/ -f1)

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

log "Stopping $API_PATH instance $VMID"
curl -ksS -X POST -H "Authorization: $AUTH" "$API_URL/nodes/$NODE/$API_PATH/$VMID/status/stop"

log "Converting $API_PATH instance $VMID to template"
curl -ksS -X POST -H "Authorization: $AUTH" "$API_URL/nodes/$NODE/$API_PATH/$VMID/template"

TEMPLATE_NAME="tmpl-debian13-${ROLE}-v${VERSION}"
log "Renaming template to $TEMPLATE_NAME"
curl -ksS -X PUT -H "Authorization: $AUTH" \
  "$API_URL/nodes/$NODE/$API_PATH/$VMID/config" \
  --data-urlencode "$RENAME_PARAM=$TEMPLATE_NAME"

log "Forgetting build resource in terraform state"
cd "$ROOT"
if terraform state rm "$STATE_ADDR" >/dev/null 2>&1; then
  log "Removed $STATE_ADDR from state"
else
  log "WARN: could not state rm $STATE_ADDR (leaving state as-is)"
fi

log "Done: $TEMPLATE_NAME (vmid $VMID)"