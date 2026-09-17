# Per-workload backup tiers. A host's `backup` field in deployments.tf selects
# a tier here; one cluster-wide PVE backup job is created per tier that has at
# least one host, covering the VMIDs assigned to it on both nodes.
#
# Retention follows PVE's prune-backups semantics: options are evaluated from
# newest backup backwards, each tier only considering backups older than the
# previous one (keep-daily -> keep-weekly -> keep-monthly). Tiers layer so a
# daily schedule with keep-daily/keep-weekly/keep-monthly yields ~2 weeks of
# dailies, then ~8 weeks of weeklies, then ~12 months of monthlies.
locals {
  backup_tiers = {
    tier-0 = {
      schedule = "*-*-* 02:00"
      prune_backups = {
        keep-daily   = "14"
        keep-weekly  = "8"
        keep-monthly = "12"
      }
    }
    tier-1 = {
      schedule = "*-*-* 02:30"
      prune_backups = {
        keep-daily   = "7"
        keep-weekly  = "4"
        keep-monthly = "6"
      }
    }
    tier-2 = {
      schedule = "*-*-* 03:00"
      prune_backups = {
        keep-daily  = "7"
        keep-weekly = "4"
      }
    }
    tier-3 = {
      schedule = "Sun *-*-* 03:30"
      prune_backups = {
        keep-weekly = "4"
      }
    }
  }

  # VMIDs per tier, derived from the deployment map. Templates (9000-9200) are
  # not in the map and are never backed up (reproducible via build-template.sh).
  backup_tier_vmids = {
    for tier, _ in local.backup_tiers :
    tier => [for name, h in local.deployments : tostring(h.vmid) if try(h.backup, "") == tier]
  }
}

# Backup jobs are cluster-wide (PVE stores them in /etc/pve/jobs.cfg), so the
# pve1 provider alias is used regardless of which node a host lives on. No
# `node` is set: vzdump runs per guest on its own node.
resource "proxmox_backup_job" "tier" {
  provider = proxmox.pve1

  for_each = {
    for tier, vmids in local.backup_tier_vmids :
    tier => vmids if length(vmids) > 0
  }

  id            = each.key
  schedule      = local.backup_tiers[each.key].schedule
  storage       = "nas"
  vmid          = each.value
  mode          = "snapshot"
  compress      = "zstd"
  enabled       = true
  prune_backups = local.backup_tiers[each.key].prune_backups
  # Email on failure only. Honoured because mailto is set (notification mode
  # "auto"); delivered by the PVE host's MTA/sendmail.
  mailnotification = "failure"
  mailto           = ["notify@abbenhuis.net"]
}