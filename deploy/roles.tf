# Map a deployment role (the `role` field in deployments.tf) to an ansible
# playbook applied post-deploy by scripts/deploy-hosts.sh. Playbooks are
# invoked from the ansible/ dir, so values are paths relative to ansible/.
#
# Add new service roles here as you create their playbooks under ansible/playbooks/.
locals {
  roles = {
    adguard    = "adguard.yml"
    unbound    = "unbound.yml"
    avahi      = "avahi.yml"
    harden     = "harden.yml"
    unifi      = "unifi.yml"
    infra-core = "infra-core.yml"
    mqtt       = "mqtt.yml"
  }
}