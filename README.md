# it-at-home

Proxmox template builds using Terraform (`bpg/proxmox`) + Ansible. The pipeline
creates an LXC container or a QEMU VM, hardens/provisions it with Ansible, then
converts it into a versioned Proxmox template via the API.

## Templates produced

| Template | Base | Contents |
|----------|------|----------|
| `tmpl-debian13-native-vX` | upstream Debian 13 tar | base hardening only |
| `tmpl-debian13-podman-vX` | clone of `native-vX` | base + podman |
| `tmpl-debian13-docker-vX` | clone of `native-vX` | base + docker (nesting enabled) |
| `tmpl-debian13-vm-vX` | Debian 13 cloud image (QEMU) | base + qemu-guest-agent + acct |

`X` is the version suffix (currently `1`). Older versions stay on PVE as
immutable artifacts while newer ones are built.

## Requirements

- Terraform >= 1.5
- Ansible (installed via pipx): `pipx install ansible`
- A Proxmox API token with privilege separation **disabled** so it inherits the
  user's rights
- SSH key pair on the control host: `~/.ssh/id_ed25519[.pub]`

## Credentials

The provider is configured with two variables (never committed):

```hcl
variable "pm_api_token_id" { type = string; sensitive = true }
variable "pm_api_token_secret" { type = string; sensitive = true }
```

Export them in your shell before running anything:

```bash
export TF_VAR_pm_api_token_id='terraform@pve!infra'
export TF_VAR_pm_api_token_secret='<secret>'
```

## Repo layout

```
main.tf                        # provider + module instances (native/podman/docker/vm)
modules/lxc-template/          # reusable container -> template module
modules/vm-template/           # reusable VM (cloud image + cloud-init) -> template
ansible/
  ansible.cfg
  inventory/hosts.yml
  playbooks/
    harden.yml                 # base hardening only
    podman.yml                 # base + podman
    docker.yml                 # base + docker
    vm.yml                     # base + vm
  roles/
    base/                      # shared hardening (LXC and VM)
    podman/
    docker/
    vm/                        # qemu-guest-agent + acct (VM only)
scripts/build-template.sh      # full pipeline: apply -> provision -> convert
```

## One-shot pipeline

`scripts/build-template.sh` does everything in one command:

```bash
./scripts/build-template.sh <role> <version> <vmid> [target]
```

`target` is `pve1` (default, amd64) or `pve2` (arm64); it selects the endpoint,
node, architecture, storage and image files from the `nodes` map in `main.tf`.

It will:
1. `terraform apply` the selected module (`native`, `podman`, `docker`, or `vm`)
2. Run the matching Ansible playbook against the new instance
3. Stop the instance and convert it to a template via the Proxmox API
   (`POST /nodes/<node>/lxc/<vmid>/template`; the VM uses `/qemu/`)
4. `terraform state rm` the build resource (the template is the artifact)

Example:

```bash
./scripts/build-template.sh native 1 9000
./scripts/build-template.sh podman 1 9010
./scripts/build-template.sh docker 1 9020
./scripts/build-template.sh vm 1 9200
./scripts/build-template.sh native 1 9000 pve2
./scripts/build-template.sh vm 1 9200 pve2
```

`native` connects over SSH as `root`; `podman`/`docker` connect as the `ansible`
user baked into the native template.

## Terraform

### Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `template_role` | `native` | Which template to build |
| `template_version` | `1` | Version suffix in the template name |
| `template_vmid` | `9000` | VMID for this build |
| `native_template_vmid` | `9000` | Clone source for podman/docker builds |

### Module inputs (`modules/lxc-template`)

`name`, `template_version`, `vmid`, `node_name`, `role`, `hostname`,
`nameserver`, `searchdomain`, `ip`, `gateway`, `ssh_keys`, `unprivileged`,
`nesting`, `fuse`, `keyctl`, `cores`, `memory`, `swap`, `disk_size`,
`disk_datastore`, `bridge`, `vlan_id`, `firewall`, `ostype`, plus exactly one
of:

- `base_template_file` (e.g. `nas:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`)
  to create from an upstream template
- `base_clone_id` to clone from a previously built template

### Manual apply (instead of the script)

```bash
terraform apply -var template_role=native -var template_version=1 -var template_vmid=9000
```

### Building a new version

Point podman/docker at the new native template and give every build a fresh VMID:

```bash
./scripts/build-template.sh native 2 9150
./scripts/build-template.sh podman 2 9160   # native_template_vmid now 9150
```

## Ansible

### Playbooks

| Playbook | Roles | SSH user |
|----------|-------|----------|
| `harden.yml` | base | root |
| `podman.yml` | base, podman | ansible |
| `docker.yml` | base, docker | ansible |
| `vm.yml` | base, vm | debian (cloud-init) |

All playbooks target `all` hosts; the build script passes the instance IP
inline:

```bash
cd ansible
~/.local/bin/ansible-playbook -i 192.168.70.90, -u root -b playbooks/harden.yml
~/.local/bin/ansible-playbook -i 192.168.70.91, -u ansible -b playbooks/podman.yml
~/.local/bin/ansible-playbook -i 192.168.70.93, -u debian -b playbooks/vm.yml
```

### base role summary

- `apt update` + `full-upgrade`; installs ca-certificates, curl, wget, gnupg,
  sudo, git, jq, less, bash-completion, needrestart, unattended-upgrades,
  apt-listchanges, fail2ban, lynis, aide, debsecan
- unattended-upgrades: automatic security updates, no auto-reboot, purge unused
- sysctl `net.*` hardening (ip_forward left untouched for docker/podman/VM)
- sshd hardening drop-in (`/etc/ssh/sshd_config.d/99-hardening.conf`):
  `PermitRootLogin no`, `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`, `AuthenticationMethods publickey`,
  `MaxAuthTries 3`, `LoginGraceTime 30`, `MaxSessions 2`,
  `AllowTcpForwarding/AllowAgentForwarding no`, `ClientAliveInterval 300`,
  `ClientAliveCountMax 2`, `LogLevel VERBOSE`, `TCPKeepAlive no`,
  `Ciphers aes128-ctr,aes192-ctr,aes256-ctr`, `HostbasedAuthentication no`,
  `IgnoreRhosts yes`, `X11Forwarding no`
- users: **`ansible`** (id_ed25519, sudo NOPASSWD, deployment) and
  **`sysadm1n`** (your personal key, sudo NOPASSWD, maintenance);
  root keeps the personal key but loses the build key and has its password locked
- fail2ban (sshd jail), build-time lynis audit, journald limits, `/etc/cron.allow`,
  purges `at`, `UMASK 027` + `PASS_MAX_DAYS 90`/`PASS_MIN_DAYS 1`, strips setuid
  from su/mount/umount/wall, timezone `Europe/Amsterdam`, timesyncd
- weekly cron: lynis + debsecan (`--suite <codename> --only-fixed`)
- aide exclusions for containers; aide DB initialized on first boot
- **firstboot unit** regenerates per clone: machine-id, SSH host keys, aide DB
- cleanup: apt autoremove/purge/clean, drop `/var/lib/apt/lists`, exclude docs/man
  from future packages, reset machine-id + host keys, clear history/tmp

## Access model

| User | Key | Purpose |
|------|-----|---------|
| `root` | richard key only, login disabled | fallback only |
| `ansible` | `id_ed25519` | automated deployments (Ansible) |
| `sysadm1n` | your personal public key | maintenance from other devices |

## Manual template conversion (without the script)

```bash
export AUTH="PVEAPIToken=${TF_VAR_pm_api_token_id}=${TF_VAR_pm_api_token_secret}"
API="https://bm-pve-prd-01.abbenhuis.internal:8006/api2/json"
curl -ksS -X POST -H "Authorization: $AUTH" "$API/nodes/bm-pve-prd-01/lxc/9000/status/stop"
curl -ksS -X POST -H "Authorization: $AUTH" "$API/nodes/bm-pve-prd-01/lxc/9000/template"
terraform state rm 'module.template_native.proxmox_virtual_environment_container.build[0]'
```

## Notes / caveats

- `Protocol 2` is intentionally omitted: OpenSSH >= 9.6 (Debian 13 ships 9.8)
  removed the option and it would prevent sshd from starting.
- auditd is not installed: it cannot fully function in an unprivileged LXC.
- acct (process accounting) is only installed/enabled in the VM template (`vm` role); it can't run in an unprivileged LXC.
- fail2ban starts but may not be able to manipulate nftables inside an
  unprivileged container; the Proxmox firewall is the primary protection.
- After the first successful build, `terraform state list` no longer shows the
  converted container; that is expected (build-and-discard pattern).