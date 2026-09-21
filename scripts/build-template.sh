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
# Prereqs (env): TF_VAR_pm_api_token_id + per-node TF_VAR_pm_api_token_secret_<node>
# (or BWS_ACCESS_TOKEN + BWS_PROJECT_ID; see scripts/_load-creds.sh)
# Usage: ./build-template.sh <role> <version> <vmid> <node>

ROLE="${1:?usage: build-template.sh <role> <version> <vmid> [target]}"
VERSION="${2:?}"
VMID="${3:?}"
TARGET="${4:-pve1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Credentials: exported TF_VAR_* or fetched per-node from Bitwarden Secrets
# Manager (bws). Only the shared id + the selected node's secret are needed.
source "$ROOT/scripts/_load-creds.sh"
load_pm_creds "$TARGET"
: "${TF_VAR_pm_api_token_id:?}"
SECRET_VAR="TF_VAR_pm_api_token_secret_${TARGET}"
: "${!SECRET_VAR:?${SECRET_VAR} not set (export it or use bws)}"

case "$TARGET" in
  pve1) NODE="bm-pve-prd-01"; API_HOST="192.168.70.64" ;;
  pve2) NODE="bm-pve-prd-02"; API_HOST="bm-pve-prd-02.abbenhuis.internal" ;; # set to node IP once pve2 exists
  *) echo "ERROR: unknown target '$TARGET' (expected pve1 or pve2)" >&2; exit 1 ;;
esac

API_URL="https://${API_HOST}:8006/api2/json"
AUTH="PVEAPIToken=${TF_VAR_pm_api_token_id}=${!SECRET_VAR}"

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

log "Applying terraform (target=$TARGET role=$ROLE version=$VERSION vmid=$VMID node=$NODE)"
cd "$ROOT"
terraform apply -auto-approve \
  -var "target=$TARGET" \
  -var "template_role=$ROLE" \
  -var "template_version=$VERSION" \
  -var "template_vmid=$VMID"

IP=$(terraform output -raw "${ROLE}_ip" | cut -d/ -f1)

log "Provisioning with ansible (role=$ROLE host=$IP user=$ANSIBLE_USER)"
cd "$ROOT/ansible"

log "Waiting for SSH to become ready on $IP..."
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
READY=0
for i in $(seq 1 180); do
  if timeout 3 bash -c ">/dev/tcp/$IP/22" 2>/dev/null && \
     timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=4 \
       -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$IP" \
       '! pgrep -x apt-get >/dev/null 2>&1 && ! pgrep -x dpkg >/dev/null 2>&1 && ! pgrep -x apt >/dev/null 2>&1' >/dev/null 2>&1; then
    READY=1
    log "SSH ready after ~$((i * 5))s"
    break
  fi
  sleep 5
done
if [[ "$READY" -ne 1 ]]; then
  echo "ERROR: SSH to $IP did not become ready within ~15 minutes" >&2
  exit 1
fi

~/.local/bin/ansible-playbook -i "${IP}," -u "$ANSIBLE_USER" -b "$PLAY"

# Guard against a build whose ansible run was interrupted partway (e.g. a
# dropped SSH connection truncating in-flight file transfers to 0 bytes). A
# broken template silently produces broken clones, so verify the template-
# critical files are non-empty; the roles are idempotent, so if any came out
# empty, re-run the playbook to heal them before converting.

# Verify the given files are all non-empty (size > 0) on the build host.
check_template_files() {
  local missing=""
  for f in "$@"; do
    local sz
    sz="$(timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=4 "$ANSIBLE_USER@$IP" "stat -c %s $f 2>/dev/null || echo 0")"
    if [[ "$sz" == "0" ]]; then
      missing="$missing $f"
    fi
  done
  if [[ -n "$missing" ]]; then
    echo "$missing"
    return 1
  fi
  return 0
}

log "Verifying template-critical files are non-empty on $IP"
CRITICAL_FILES=("/usr/local/bin/firstboot.sh" "/etc/systemd/system/firstboot.service")
if [[ "$ROLE" == "vm" ]]; then
  CRITICAL_FILES+=("/etc/netplan/99-ipv4-only.yaml")
fi
MISSING="$(check_template_files "${CRITICAL_FILES[@]}")"
if [[ -n "$MISSING" ]]; then
  log "0-byte files detected ($MISSING), re-running ansible to heal (build was likely interrupted)"
  ~/.local/bin/ansible-playbook -i "${IP}," -u "$ANSIBLE_USER" -b "$PLAY"
  MISSING="$(check_template_files "${CRITICAL_FILES[@]}")"
fi
if [[ -n "$MISSING" ]]; then
  echo "ERROR: template build still has 0-byte files ($MISSING) after re-run - build is unreliable" >&2
  echo "Fix the SSH/ansible issue (check MaxSessions/AllowUsers/build VM resources) and rebuild" >&2
  exit 1
fi
log "Template-critical files OK"

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