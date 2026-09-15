#!/usr/bin/env python3
"""Helpers for scripts/deploy-hosts.sh.

Reads JSON from stdin; usage:
  python3 _deploy-helpers.py resolve <host>   # module address for a host (plan JSON)
  python3 _deploy-helpers.py provision <target> <hosts>  # hosts to provision (hosts output JSON)
"""
import json
import re
import sys


def resolve_host(host):
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("type") == "planned_change":
            addrs = [(msg.get("change") or {}).get("resource", {}).get("addr", "")]
        else:
            addrs = [rc.get("address", "") for rc in (msg.get("resource_changes") or [])]
        for addr in addrs:
            m = re.match(r'^(module\.deploy_pve[12])\["([^"]+)"\]', addr)
            if m and m.group(2) == host:
                print(f'{m.group(1)}["{host}"]')
                return


def provision_plan(target, hosts_arg):
    try:
        hosts = json.load(sys.stdin)
    except Exception:
        hosts = {}
    want = set(x for x in hosts_arg.split(",") if x) if hosts_arg else None
    for name, h in sorted(hosts.items()):
        if target and h["target"] != target:
            continue
        if want and name not in want:
            continue
        if not h.get("playbook"):
            continue
        ip = h["ip"].split("/")[0]
        print(f"{name}|{h['type']}|{ip}|{h['playbook']}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "resolve":
        resolve_host(sys.argv[2])
    elif cmd == "provision":
        provision_plan(sys.argv[2], sys.argv[3])
    else:
        sys.exit(2)