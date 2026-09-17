#!/usr/bin/env bash
set -euo pipefail

# Harden / provision Proxmox VE hosts (pve1/pve2) with the pve role:
#   ./pve-hosts.sh                    # all PVE hosts (SSH as the ansible user)
#   ./pve-hosts.sh pve1               # only pve1
#   ./pve-hosts.sh pve1 --check       # dry-run only, never applies anything
#   ./pve-hosts.sh --bootstrap        # first run after a fresh install (SSH as root)
#   ./pve-hosts.sh pve1 --bootstrap   # bootstrap only pve1
#
# --bootstrap connects as root using PVE_ROOT_PASSWORD (via sshpass); use it
# once after a fresh Proxmox install to create the ansible/sysadm1n OS users,
# set up the PVE users/roles/ACLs and apply hardening. Later runs connect as
# the ansible user (created by the first run).
#
# --check runs `ansible-playbook --check --diff`: nothing is applied. Task
# errors abort with a non-zero exit; tasks that merely report changes (expected
# on a manually-configured host) exit 0 and leave the host untouched.
#
# Prereqs: sshpass (only for --bootstrap), PVE_ROOT_PASSWORD (only for --bootstrap).

MODE=normal
TARGET=""
CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    pve1|pve2) TARGET="$1"; shift ;;
    --bootstrap) MODE=bootstrap; shift ;;
    --check) CHECK=1; shift ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      echo "Usage: $0 [pve1|pve2] [--bootstrap] [--check]" >&2
      exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT/ansible"

node_ip() {
  case "$1" in
    pve1) echo "192.168.70.64" ;;
    pve2) echo "bm-pve-prd-02.abbenhuis.internal" ;;
  esac
}

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

HOSTS=()
if [[ -n "$TARGET" ]]; then
  HOSTS=("$TARGET")
else
  HOSTS=(pve1 pve2)
fi

SSH_USER=ansible
EXTRA_ARGS=()
if [[ "$MODE" == "bootstrap" ]]; then
  command -v sshpass >/dev/null || { echo "ERROR: sshpass is required for --bootstrap" >&2; exit 1; }
  : "${PVE_ROOT_PASSWORD:?set PVE_ROOT_PASSWORD for --bootstrap (root SSH on a fresh install)}"
  SSH_USER=root
  EXTRA_ARGS=(
    -e "ansible_password=${PVE_ROOT_PASSWORD}"
    -e "ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o PreferredAuthentications=password"
  )
fi

# Optional OS password for the sysadm1n account, which enables the PVE web GUI
# login as sysadm1n@pam (pam realm users authenticate against the OS account).
# Taken from PVE_SYSADM1N_PASSWORD (env) or a bws secret of the same key. A
# deterministic SHA-512 salt is derived from the password so the hash is stable
# across runs (idempotent) while never being committed to the repo.
source "$ROOT/scripts/_load-creds.sh"
SYSADM1N_PASSWORD="${PVE_SYSADM1N_PASSWORD:-}"
if [[ -z "$SYSADM1N_PASSWORD" && -n "${BWS_ACCESS_TOKEN:-}" && -n "${BWS_PROJECT_ID:-}" ]]; then
  SYSADM1N_PASSWORD="$(bws_value PVE_SYSADM1N_PASSWORD 2>/dev/null || true)"
fi
if [[ -n "$SYSADM1N_PASSWORD" ]]; then
  if ! command -v openssl >/dev/null; then
    echo "WARN: openssl not found; cannot set the sysadm1n password" >&2
  else
    SALT="$(printf '%s' "$SYSADM1N_PASSWORD" | sha256sum | head -c 16)"
    HASH="$(openssl passwd -6 -salt "$SALT" "$SYSADM1N_PASSWORD")"
    EXTRA_ARGS+=(-e "pve_sysadm1n_password_hash=$HASH")
  fi
fi

cd "$ANSIBLE_DIR"

for h in "${HOSTS[@]}"; do
  ip="$(node_ip "$h")"
  log "Provisioning $h ($ip) as $SSH_USER"
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  if [[ "$CHECK" -eq 1 ]]; then
    ~/.local/bin/ansible-playbook -i "$ip," -u "$SSH_USER" --check --diff "${EXTRA_ARGS[@]}" playbooks/pve.yml
  else
    ~/.local/bin/ansible-playbook -i "$ip," -u "$SSH_USER" "${EXTRA_ARGS[@]}" playbooks/pve.yml
  fi
done

log "Done."