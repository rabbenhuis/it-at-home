# AGENTS.md

Proxmox template build pipeline (Terraform `bpg/proxmox` + Ansible). Builds versioned templates on two nodes selected by the `target` variable (`pve1` amd64, `pve2` arm64): `tmpl-debian13-native-v1` (9000), then `-podman-v1` (9010) and `-docker-v1` (9020) cloned from the native one, plus a QEMU `-vm-v1` (9200) from the Debian 13 cloud image via cloud-init.

## Credentials (blocker)

- Provider token comes from **env vars in the user's terminal**: `TF_VAR_pm_api_token_id` / `TF_VAR_pm_api_token_secret`. Never committed. They are **not** in the agent shell — any `terraform plan/apply`, template conversion, or API curl that needs auth must be run by the user (give exact commands) or with the vars exported.
- No SSH to the PVE host (`bm-pve-prd-01`); SSH only into build containers.
- `terraform validate` works without credentials; do that, not `plan`.

## One-shot build

`./scripts/build-template.sh <role> <version> <vmid> [target]` runs: `terraform apply` (`target=pve1|pve2` selects endpoint/node/arch/storage/images) → SSH-wait (~10 min, covers clone firstboot/aideinit and VM cloud-init) → `ansible-playbook` → stop → convert to template (API `POST /lxc/<vmid>/template`, VM uses `/qemu/`) → rename (API `PUT .../config`; `hostname=` for LXC, `name=` for VM) → `terraform state rm`. Re-running after a partial failure is safe (idempotent).

Per-node settings (endpoint, node name, architecture, disk/image datastores, bridge, VLAN, IPs, image file ids) live in the `nodes` output of `modules/cluster-data/outputs.tf` (shared with the deploy config). Base images are **static references** (not downloaded by Terraform) — provision each node's `nas` once; the pve2 (arm64) filenames are placeholders to confirm via `pveam available | grep arm64`.

## Deployments (deploy/)

`deploy/` is a **separate Terraform config** (own statefile) that clones hosts from the built templates. Source of truth is the **deployment map** `deploy/deployments.tf` (HCL, one entry per host — not a CSV). `scripts/deploy-hosts.sh` runs `terraform apply` then ansible per host; a `role` field is mapped to an ansible playbook via `deploy/roles.tf` (SSH user: `ansible` for lxc, `debian` for vm).

- Per-node/per-host scope (`pve1|pve2`, `--hosts a,b`) must be done with **`-target`** (script already does this). Do **not** implement scoping by filtering `for_each`/`count` on the map — that destroys hosts left out of the scope.
- Gateway/nameserver/search-domain come from the `vlans` registry in `modules/cluster-data` (keyed by VLAN ID); hosts only set `vlan_id`.
- `deploy/deployments.tf` is validated by `terraform validate` from `deploy/` (needs `terraform init` there first). Do that, not `plan` (no creds in the agent shell).

## Ansible specifics

- Runs via pipx: **`~/.local/bin/ansible-playbook`** (system `ansible` is not installed). Run from the `ansible/` dir so `ansible.cfg` applies.
- Playbooks target `hosts: all`; invoke with inline inventory `-i <IP>,`. SSH user: `native` → `root`, `podman`/`docker` → `ansible` (that user + key are baked into the native template; also `sysadm1n` for human maintenance), `vm` → `debian` (cloud-init user from the cloud image, key injected via `user_account`). Root login is disabled; `AllowUsers ansible sysadm1n`.
- Syntax check only: `~/.local/bin/ansible-playbook --syntax-check playbooks/harden.yml` (from `ansible/`).

## Hard-won gotchas (do not "fix" these back)

- **Never `systemctl restart ssh`** in a build container — socket-activated sshd makes it fail/hang/deadlock. The role only runs `sshd -t` (regenerating host keys first if missing).
- **Never `rm -rf /tmp/*`** in an Ansible task — it deletes the running module payload. Use `find /tmp /var/tmp -mindepth 1 \( -path '/tmp/user' -o -name 'ansible_*' \) -prune -o -exec rm -rf {} +`.
- **Do not set SSH keys when cloning** (`user_account`): PVE's clone API rejects `ssh-public-keys` (HTTP 400). The module only injects keys for create-from-upstream; clones inherit `ansible`/`sysadm1n`. Keep it that way.
- **apt-listbugs was removed** — it fails closed on grave bugs and broke unattended podman installs. Don't re-add.
- `Protocol 2` is invalid on OpenSSH 10 (Debian 13) — omitted. `auditd` and `acct` are absent from the LXC base because kernel auditing/accounting can't run in an unprivileged LXC; `acct` **is** installed by the `vm` role (works in a full VM).
- Module input is `template_version`, not `version` (`version` is a reserved module meta-argument).
- SSH host-key / machine-id / aide-db / firstboot.done are stripped in cleanup so templates ship clean; a `firstboot.service` regenerates them per clone. `firstboot.sh` must **not** call `systemctl restart ssh` (caused a boot deadlock).
- The VM template uses a static cloud image file id in the `nodes` output of `modules/cluster-data` (`modules/vm-template`); `initialization.user_account.username = "debian"`. The LXC ostemplate is likewise a static `nas:vztmpl/...` reference per node. Both images are provisioned manually per node (the `proxmox_download_file` resources were dropped because target-switching would destroy/redownload them).

## Layout

- `modules/lxc-template/` — reusable container resource; `base_template_file` vs `base_clone_id` select create-vs-clone. `modules/vm-template/` — QEMU VM from a cloud image (cloud-init). `modules/deploy/` — one module per node (`deploy_pve1`/`deploy_pve2`) cloning templates into managed hosts (lxc or vm via `type`).
- `ansible/roles/base/` — shared hardening (packages, sshd drop-in, users, sysctl, cron email jobs). `ansible/roles/{podman,docker}/` — runtime installs. `ansible/roles/vm/` — qemu-guest-agent + acct (VM only).
- `ansible/roles/base/files/id_ed25519.pub` = the `ansible` user's key; `id_rsa.pub` = `sysadm1n`/maintenance key.
- Secrets/tfstate are gitignored; keep it that way.

## Email notifications

Cron jobs email `notify@abbenhuis.net` via `msmtp` → `mta.abbenhuis.internal:25` (no auth/TLS). lynis (monthly), debsums + rkhunter + debsecan (weekly) email **only on findings** (empty output = no mail). `/etc/crontab` MAILTO is the FQDN to avoid `504 <root>` rejections.