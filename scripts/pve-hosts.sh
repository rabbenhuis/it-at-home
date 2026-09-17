#!/usr/bin/env bash
set -euo pipefail

# Harden / provision Proxmox VE hosts (pve1/pve2) with the pve role:
#   ./pve-hosts.sh                    # all PVE hosts (SSH as the ansible user)
#   ./pve-hosts.sh pve1               # only pve1
#   ./pve-hosts.sh pve1 --check       # dry-run only, never applies anything
#   ./pve-hosts.sh --bootstrap        # first run after a fresh install (SSH as root)
#   ./pve-hosts.sh pve1 --bootstrap   # bootstrap only pve1
#   ./pve-hosts.sh pve1 --user sysadm1n   # first run on an existing host (see below)
#
# Connection modes:
#   - default: SSH as the `ansible` user (~/.ssh/id_ed25519, passwordless sudo).
#     Only possible once the pve role has run (it creates that user).
#   - --bootstrap: SSH as root using PVE_ROOT_PASSWORD (via sshpass). Only for a
#     fresh install where root password auth still works.
#   - --user sysadm1n: first run on an already-configured host that has no
#     `ansible` user yet (e.g. pve1). Connects with ~/.ssh/id_rsa; sudo on
#     sysadm1n needs a password, so either export PVE_SUDO_PASSWORD or you will
#     be prompted (--ask-become-pass). This run creates the ansible user.
#
# --check runs `ansible-playbook --check --diff`: nothing is applied. Task
# errors abort with a non-zero exit; tasks that merely report changes (expected
# on a manually-configured host) exit 0 and leave the host untouched.
#
# Prereqs: sshpass (only for --bootstrap), PVE_ROOT_PASSWORD (only for --bootstrap).

MODE=normal
TARGET=""
CHECK=0
SSH_USER=ansible

while [[ $# -gt 0 ]]; do
  case "$1" in
    pve1|pve2) TARGET="$1"; shift ;;
    --bootstrap) MODE=bootstrap; shift ;;
    --check) CHECK=1; shift ;;
    --user) SSH_USER="$2"; shift 2 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      echo "Usage: $0 [pve1|pve2] [--bootstrap] [--user NAME] [--check]" >&2
      exit 1 ;;
  esac
done

if [[ "$MODE" == "bootstrap" && "$SSH_USER" != "ansible" ]]; then
  echo "ERROR: --bootstrap always connects as root; remove --user" >&2
  exit 1
fi

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

EXTRA_ARGS=()
if [[ "$MODE" == "bootstrap" ]]; then
  command -v sshpass >/dev/null || { echo "ERROR: sshpass is required for --bootstrap" >&2; exit 1; }
  : "${PVE_ROOT_PASSWORD:?set PVE_ROOT_PASSWORD for --bootstrap (root SSH on a fresh install)}"
  SSH_USER=root
  EXTRA_ARGS=(
    -e "ansible_password=${PVE_ROOT_PASSWORD}"
    -e "ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o PreferredAuthentications=password"
  )
else
  # SSH key per user: sysadm1n uses the personal key, ansible the deploy key.
  case "$SSH_USER" in
    sysadm1n) SSH_KEY="$HOME/.ssh/id_rsa" ;;
    *)        SSH_KEY="$HOME/.ssh/id_ed25519" ;;
  esac
  EXTRA_ARGS+=(-e "ansible_ssh_private_key_file=$SSH_KEY")

  # Become (sudo) password. The `ansible` user has passwordless sudo (set up by
  # the role); other users (e.g. sysadm1n on an existing host) need a password:
  # provide PVE_SUDO_PASSWORD or prompt with --ask-become-pass.
  if [[ "$SSH_USER" != "ansible" ]]; then
    if [[ -n "${PVE_SUDO_PASSWORD:-}" ]]; then
      EXTRA_ARGS+=(-e "ansible_become_password=$PVE_SUDO_PASSWORD")
    else
      EXTRA_ARGS+=(--ask-become-pass)
    fi
  fi
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