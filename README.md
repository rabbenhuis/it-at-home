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
- `bws` CLI (Bitwarden Secrets Manager) — optional; only if you don't export
  the token vars yourself
- `sshpass` — only for bootstrapping a fresh PVE host (`--bootstrap`)
- A Proxmox API token with privilege separation **disabled** so it inherits the
  user's rights
- SSH key pair on the control host: `~/.ssh/id_ed25519[.pub]`

## Credentials

The provider is configured with a shared token id plus a per-node secret (each
node has its own `terraform@pve` token):

```hcl
variable "pm_api_token_id"          { type = string; sensitive = true }
variable "pm_api_token_secret_pve1" { type = string; sensitive = true }
variable "pm_api_token_secret_pve2" { type = string; sensitive = true }
```

Export them in your shell before running anything:

```bash
export TF_VAR_pm_api_token_id='terraform@pve!infra'
export TF_VAR_pm_api_token_secret_pve1='<pve1 secret>'
export TF_VAR_pm_api_token_secret_pve2='<pve2 secret>'
```

Alternatively, store them in Bitwarden Secrets Manager under these exact keys
and export `BWS_ACCESS_TOKEN` + `BWS_PROJECT_ID`; `build-template.sh` and
`deploy-hosts.sh` fetch them automatically when the `TF_VAR_*` vars are unset
(via `scripts/_load-creds.sh`).

```text
TF_VAR_pm_api_token_id            = terraform@pve!infra
TF_VAR_pm_api_token_secret_pve1   = <pve1 secret>
TF_VAR_pm_api_token_secret_pve2   = <pve2 secret>
```

## Repo layout

```
main.tf                        # provider + module instances (native/podman/docker/vm)
modules/cluster-data/          # shared node map, VLAN registry, SSH keys (build + deploy)
modules/lxc-template/          # reusable container -> template module
modules/vm-template/           # reusable VM (cloud image + cloud-init) -> template
modules/deploy/                # clone a template -> deployed host (lxc or vm, per node)
deploy/                        # deployment map, own statefile
  main.tf                      # one module per node (deploy_pve1 / deploy_pve2)
  deployments.tf               # deployment map - one entry per host (edit this)
  roles.tf                     # role -> ansible playbook mapping
  firewall.tf                  # role -> PVE firewall rules mapping
ansible/
  ansible.cfg
  inventory/hosts.yml
  playbooks/
    harden.yml                 # base hardening only
    podman.yml                 # base + podman
    docker.yml                 # base + docker
    vm.yml                     # base + vm
    pve.yml                    # PVE host hardening + access control
    adguard.yml                # deploy AdGuard Home (post-deploy)
    unbound.yml                # deploy unbound resolver (post-deploy)
  roles/
    base/                      # shared hardening (LXC and VM)
    podman/
    docker/
    vm/                        # qemu-guest-agent + acct (VM only)
    pve/                       # PVE host hardening + pveum access control
    adguard/                   # AdGuard Home install + config (deployed hosts)
    unbound/                   # unbound recursive resolver (deployed hosts)
scripts/build-template.sh      # full pipeline: apply -> provision -> convert
scripts/deploy-hosts.sh        # deploy hosts from deployments.tf
scripts/_load-creds.sh         # bws -> TF_VAR_* credential loader
scripts/pve-hosts.sh           # harden/provision the PVE hosts
scripts/bootstrap-pve.sh       # bootstrap a fresh PVE host (pveum + bws)
scripts/_deploy-helpers.py     # JSON helpers used by deploy-hosts.sh
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

## Deployments from templates (deployment map)

The `deploy/` config clones hosts from the built templates. It is a **separate
Terraform configuration with its own statefile** so deployed hosts are
long-lived resources, isolated from the build-and-discard template pipeline.
Both configs share `modules/cluster-data/` (node map, VLAN registry, SSH keys).

### Deployment map (`deploy/deployments.tf`)

One entry per host. The map (not a CSV) is the source of truth so fields stay
native HCL types, comments are allowed, and `terraform validate` catches errors:

| Field | Meaning |
|-------|---------|
| `type` | `"lxc"` or `"vm"` |
| `target` | node: `"pve1"` (amd64) or `"pve2"` (arm64) |
| `vlan_id` | VLAN ID; gateway/nameserver/search-domain resolve from the VLAN registry |
| `template_vmid` | template to clone: 9000 native / 9010 podman / 9020 docker / 9200 vm |
| `vmid` | unique VMID (keep clear of the 9000-9200 template range, e.g. 100-899) |
| `ip` | static IPv4 in CIDR, on the VLAN's subnet |
| `cores` | CPU cores (omit = inherit template) |
| `memory` | RAM in MB (omit = inherit template) |
| `disk_size` | rootfs/disk in GB, **LXC only** (omit = inherit; VM disk is always inherited) |
| `on_boot` | start at host boot (default `true`) |
| `startup` | startup/shutdown order and delays: `{ order, up_delay?, down_delay? }` (omit = unset) |
| `unprivileged` | LXC only (default `true`) |
| `nesting`/`fuse`/`keyctl` | LXC features (omit = inherit template) |
| `role` | service role to apply post-deploy, mapped to an ansible playbook in `deploy/roles.tf` (e.g. `adguard`, `unbound`, `haos`); omit = skip |
| `description` | free-form note shown in the Proxmox container/VM notes field (omit = `Managed by Terraform (deployed from template vmid N)`) |

A complete entry looks like:

```hcl
adguard-sec01 = {
  type          = "lxc"
  target        = "pve1"
  vlan_id       = 90
  template_vmid = 9000
  vmid          = 205
  cores         = 1
  memory        = 256
  disk_size     = 8
  ip            = "192.168.90.42/24"
  on_boot       = true
  startup       = { order = 20, up_delay = 15, down_delay = 60 }
  role          = "adguard"
  description   = "Secondary AdGuard Home DNS blocker"
}
```

### Role → playbook mapping (`deploy/roles.tf`)

The `role` field is a service/application name; `deploy/roles.tf` maps it to an
Ansible playbook that is applied post-deploy:

```hcl
locals {
  roles = {
    adguard = "adguard.yml"
    unbound = "unbound.yml"
    haos    = "haos.yml"
    harden  = "harden.yml"
  }
}
```

A host without a `role` (or with a role not in the map) is created but not
provisioned. Add a new service by creating its playbook under `ansible/playbooks/`
(which can include an Ansible role under `ansible/roles/`) and registering it here.

### Role → firewall rules (`deploy/firewall.tf`)

A host gets a PVE firewall rule set only when its `role` is registered in the
`firewall_rules` map. The rule set is the **complete** inbound rule list for the
guest (the `.fw` file is replaced wholesale) and defaults to **deny-by-default**
(each role ends with a `DROP` tail). Management base rules (SSH `22` + ICMP from
the workstation VLANs 120/132, `192.168.120.0/24` + `192.168.132.0/24`) are
prepended automatically. Hosts whose role isn't registered keep PVE's default
ACCEPT (no rules file).

```hcl
firewall_rules = {
  adguard = [                  # env-wide DNS: 53 open to all VLANs
    { type = "in", action = "ACCEPT", proto = "udp", dport = "53", comment = "DNS" },
    { type = "in", action = "ACCEPT", proto = "tcp", dport = "53", comment = "DNS over TCP" },
    { type = "in", action = "ACCEPT", proto = "tcp", dport = "3000", source = "192.168.120.0/24,192.168.132.0/24", comment = "Admin UI (mgmt)" },
    { type = "in", action = "DROP", comment = "Deny other inbound" },
  ]
}
```

Rule fields: `type` (`in`/`out`/`forward`), `action` (`ACCEPT`/`DROP`/`REJECT`),
`proto`, `dport`/`sport`, `source`/`dest` (IP/network, comma-separated list
allowed, or an alias/`+ipset` name), `iface`, `log`, `comment`.

### DNS views (per-VLAN internal record visibility)

AdGuard Home has no DNS views, so internal record visibility is implemented in
unbound. Each `unbound` host runs one unbound instance per view on a dedicated
port; AdGuard routes each VLAN to the right view via **per-client upstreams**
(`clients.persistent`), keeping global blocklist filtering in AdGuard.

| View | Port | VLANs | Internal records |
|------|------|-------|------------------|
| `internal-full` | 5353 | 37, 70, 75, 80, 90, 95, 100, 115 | full set |
| `internal-limited` | 5354 | 120, 122, 132 | NAS, printer, scanner, HA + mgmt (pve1, unifi, zigbee2mqtt, mqtt-explorer) |
| `iot-platform` | 5355 | 150 | full set + IoT |
| `iot-limited` | 5356 | 152 | none |
| `gaming-limited` | 5357 | 160 | none |

- Internal records live in the **unbound** role (`unbound_records_full`,
  `unbound_records_limited`, `unbound_views`) — **not** in AdGuard rewrites
  (global rewrites would bypass the views).
- VLAN→view routing is defined in the **adguard** role (`adguard_view_clients`,
  matching the unbound view ports).
- Add a record: add it to the right unbound record set, then re-run both
  playbooks.

### VLAN registry (`modules/cluster-data/outputs.tf`)

The `vlans` output is the single source of truth for every VLAN. Each entry
provides `gateway`, `nameserver` (a list) and `dns_zone` (used as the host's
search domain); deployed hosts only reference the numeric `vlan_id`:

```hcl
vlans = {
  70 = { name = "mgmt", subnet = "192.168.70.0/24",
         gateway = "192.168.70.1", nameserver = ["192.168.70.1"],
         dns_zone = "abbenhuis.internal" }
}
```

### Module inputs (`modules/deploy`)

Each deployment map entry maps 1:1 onto this module's inputs (values marked
"registry" come from `modules/cluster-data` via the host's `vlan_id`/`target`,
not from the map):

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `name` | string | – | host name (map key) |
| `type` | string | – | `"lxc"` or `"vm"` |
| `vmid` | number | – | container/VM VMID |
| `template_vmid` | number | – | template to clone: 9000 native / 9010 podman / 9020 docker / 9200 vm |
| `hostname` | string | – | short hostname (from map key) |
| `ip` | string | – | static IPv4 in CIDR (from map) |
| `vlan_id` | number | – | VLAN ID (from map; gateway/nameserver/search-domain resolved from the VLAN registry) |
| `node_name` | string | – | PVE node (registry: `nodes[pve1/pve2].node_name`) |
| `architecture` | string | `amd64` | CPU architecture, LXC (registry) |
| `nameserver` | list(string) | – | DNS servers (registry: `vlans[id].nameserver`) |
| `searchdomain` | string | – | DNS search domain (registry: `vlans[id].dns_zone`) |
| `gateway` | string | – | IPv4 gateway (registry: `vlans[id].gateway`) |
| `disk_datastore` | string | `local-lvm` | rootfs/disk datastore, LXC (registry) |
| `bridge` | string | `vmbr0` | network bridge (registry) |
| `ssh_keys` | list(string) | `[]` | keys injected via cloud-init, VM only (registry) |
| `on_boot` | bool | `true` | start at host boot (map, default `true`) |
| `startup` | object | `null` | `{ order, up_delay?, down_delay? }`; omit = unset (map) |
| `unprivileged` | bool | `true` | unprivileged container, LXC only (map) |
| `nesting`/`fuse`/`keyctl` | bool | `null` | LXC features; `null` = inherit template (map) |
| `cores` | number | `0` | CPU cores; `0` = inherit template (map) |
| `memory` | number | `0` | RAM in MB; `0` = inherit template (map) |
| `swap` | number | `0` | swap in MB, LXC (map) |
| `disk_size` | number | `0` | rootfs/disk in GB, **LXC only**; `0` = inherit template (map; VM disk always inherited) |
| `firewall` | bool | `true` | enable the PVE firewall on the NIC |
| `description` | string | `Managed by Terraform (deployed)` | shown in the PVE notes field (map) |

The `deploy/` config also exposes a `hosts` output mapping every host in
`deployments.tf` to its `type`, `target`, `vlan_id`, `vmid`, `ip` and resolved
`playbook`; `scripts/deploy-hosts.sh` uses it to decide which hosts to
provision and over which SSH user.

### Deploying

```bash
./scripts/deploy-hosts.sh                 # deploy all hosts
./scripts/deploy-hosts.sh pve1            # deploy only pve1 (amd64) hosts
./scripts/deploy-hosts.sh pve2            # deploy only pve2 (arm64) hosts
./scripts/deploy-hosts.sh --hosts web1,db1  # deploy only the named hosts
./scripts/deploy-hosts.sh destroy [scope]   # tear down (same scope options)
```

Scoped deploys use `terraform apply -target` so hosts outside the scope are
**never touched** (the map stays the full desired state). Ansible provisioning
runs only for hosts in scope that set a `role` (resolved to a playbook via
`deploy/roles.tf`). SSH always connects as the `ansible` user (baked into both
LXC and VM templates by the base role, with passwordless sudo). Requires the
same `TF_VAR_pm_api_token_*` env vars as the template pipeline.

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

### Module inputs (`modules/vm-template`)

`name`, `template_version`, `vmid`, `node_name`, `hostname`, `cloud_image_file_id`,
`nameserver`, `searchdomain`, `ip`, `gateway`, `ssh_keys`, `cores`, `memory`,
`disk_size`, `disk_datastore`, `bridge`, `vlan_id`, `firewall`, `ostype`. The
VM is created from `cloud_image_file_id` (static `nas:import/...` reference per
node) with cloud-init, `agent` enabled, and `stop_on_destroy` set.

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
| `pve.yml` | pve | ansible (PVE hosts) |

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

## Proxmox host management (pve1/pve2)

The Proxmox hosts themselves are managed from this repo: the `pve` role hardens
them and manages PVE access control (`pveum`), and a bootstrap script stands up
a fresh install.

### Access model (PVE users/roles/ACLs)

Managed by the `pve` role / bootstrap via `pveum` (not Terraform), converging
on every run:

| PVE user | Realm | Role / path | Purpose |
|----------|-------|-------------|---------|
| `terraform@pve` | pve | `Terraform-Infra` on `/` | Terraform build/deploy (API token `infra`, one per node) |
| `sysadm1n@pam` | pam | `Administrator` on `/` | human maintenance / GUI login (OS user) |
| `ansible@pam` | pam | `PVEAuditor` on `/` | read-only; Ansible connects over SSH as the OS `ansible` user |

The `Terraform-Infra` role mirrors the manually-created `TerraformRole` on
pve1 (22 privileges; see `ansible/roles/pve/defaults/main.yml`). PAM realm
users authenticate against the OS users the role creates (`ansible`,
`sysadm1n`), so they exist only after the first run.

### Bootstrapping a fresh install

A fresh PVE install has only `root@pam`. One command stands it up:

```bash
export PVE_ROOT_PASSWORD='<root password from the installer>'
export BWS_ACCESS_TOKEN='<machine access token>'
export BWS_PROJECT_ID='<secrets project id>'
./scripts/bootstrap-pve.sh pve1
```

This:
1. SSHs as root and, via `pveum`, ensures the `terraform@pve` user and creates
   the API token `infra` (`--privsep 0`) — the chicken-egg step only this
   script can do.
2. Stores `TF_VAR_pm_api_token_id` (created once) and
   `TF_VAR_pm_api_token_secret_pve1` in Bitwarden Secrets Manager.
3. Auto-runs `./scripts/pve-hosts.sh pve1 --bootstrap`, which creates the
   `Terraform-Infra` role, the ACLs, the OS users and applies hardening.

Run it once per node (pve2 later, same command). To store an **already-existing**
token in bws without touching the host (e.g. pve1):

```bash
./scripts/bootstrap-pve.sh pve1 --register-only   # prompts for the token secret
```

### Ongoing hardening

```bash
./scripts/pve-hosts.sh            # all PVE hosts, SSH as ansible
./scripts/pve-hosts.sh pve1       # only pve1
./scripts/pve-hosts.sh pve1 --check   # dry-run, never applies (review first!)
```

Connection modes:
- **default**: SSH as the `ansible` user (`~/.ssh/id_ed25519`, passwordless sudo).
  Only possible once the pve role has run (it creates that user).
- **`--bootstrap`**: SSH as root with `PVE_ROOT_PASSWORD` (sshpass); only for a
  fresh install where root password auth still works.
- **`--user sysadm1n`**: first run on an already-configured host that has no
  `ansible` user yet (e.g. pve1). Uses `~/.ssh/id_rsa`; `sysadm1n`'s sudo needs
  a password, so either export `PVE_SUDO_PASSWORD` or you'll be prompted
  (`--ask-become-pass`). This run creates the `ansible` user and hardens the
  host; afterwards plain runs as `ansible` work:

```bash
./scripts/pve-hosts.sh pve1 --check --user sysadm1n    # review the diff first
./scripts/pve-hosts.sh pve1 --user sysadm1n            # converge (creates ansible)
./scripts/pve-hosts.sh pve1                            # from now on, as ansible
```

`--check` runs `ansible-playbook --check --diff`: nothing is applied, and on a
manually-configured host it will show the managed files the role would adopt
(sshd drop-in, fail2ban, sysctl, …) as changes — expected, not an error.

### pve role summary

- **OS users**: `ansible` (id_ed25519) and `sysadm1n` (id_rsa) with passwordless
  sudo — these back the `@pam` PVE accounts. PVE `pam` realm users authenticate
  against the OS accounts, so to log into the PVE web GUI as `sysadm1n@pam`
  the OS `sysadm1n` user needs a password: export `PVE_SYSADM1N_PASSWORD` (or
  store it in bws under that key) before running `pve-hosts.sh` and the role
  sets it (deterministic hash, never committed). `ansible` intentionally stays
  passwordless (SSH-key automation only).

- **OS users**: `ansible` (id_ed25519) and `sysadm1n` (id_rsa) with passwordless
  sudo — these back the `@pam` PVE accounts.
- **PVE access control** via `pveum` (idempotent, additive): role/user/ACL
  convergence as in the table above.
- **Hardening** (PVE-safe subset of the base role): apt full-upgrade,
  unattended-upgrades, sysctl, sshd drop-in (`PermitRootLogin no`, keys only,
  `AllowUsers ansible sysadm1n`), fail2ban (sshd **+ proxmox** jails for the
  web UI), **auditd** (kernel auditing works on the full host, running the
  host's `hardening.rules`; hourly email alert on critical identity/ssh/cron/
  systemd/pam/audit events), journald limits,
  `/etc/cron.allow`, login.defs/umask, core dumps off,
  pam_pwquality (`minlen=12 minclass=3`), timezone, **chrony** (PVE's NTP),
  lynis + debsums + rkhunter + debsecan with cron email, purges `at`/`zip`/`unzip`.
- **Deliberately NOT done** (would break the hypervisor): machine-id / SSH
  host-key reset, `firstboot.service`, aide, postfix purge, locking root.

## Access model (guests)

| User | Key | Purpose |
|------|-----|---------|
| `root` | richard key only, login disabled | fallback only |
| `ansible` | `id_ed25519` | automated deployments (Ansible) |
| `sysadm1n` | your personal public key | maintenance from other devices |

(The Proxmox host access model — PVE realm users/roles/ACLs — is described
[above](#access-model-pve-usersrolesacls).)

## Manual template conversion (without the script)

```bash
export SECRET="${TF_VAR_pm_api_token_secret_pve1}"
export AUTH="PVEAPIToken=${TF_VAR_pm_api_token_id}=${SECRET}"
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