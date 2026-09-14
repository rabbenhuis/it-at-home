#!/usr/bin/env bash
# Send stdin to notify@abbenhuis.net with an envelope-from derived from this host,
# so each container's mail is distinguishable (notify@<shortname>.abbenhuis.internal).
exec msmtp -f "notify@$(hostname -s).abbenhuis.internal" notify@abbenhuis.net
