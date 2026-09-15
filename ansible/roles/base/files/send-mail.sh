#!/usr/bin/env bash
# Send stdin to notify@abbenhuis.net.
# Envelope-from is <hostname>@abbenhuis.net (the MTA accepts @abbenhuis.net
# senders, e.g. maximus@abbenhuis.net). A From: header carrying the hostname as
# the display name is prepended so mail clients (Outlook) show a friendly name
# instead of the raw address.
HOST="$(hostname -s)"
FROM_ADDR="$HOST@abbenhuis.net"

{
  printf 'From: %s <%s>\n\n' "$HOST" "$FROM_ADDR"
  cat
} | msmtp -f "$FROM_ADDR" notify@abbenhuis.net
