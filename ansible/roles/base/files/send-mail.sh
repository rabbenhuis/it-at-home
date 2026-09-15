#!/usr/bin/env bash
# Send stdin to notify@abbenhuis.net with a From of <hostname>@abbenhuis.net,
# matching the MTA's accepted sender domain (e.g. maximus@abbenhuis.net).
exec msmtp -f "$(hostname -s)@abbenhuis.net" notify@abbenhuis.net
