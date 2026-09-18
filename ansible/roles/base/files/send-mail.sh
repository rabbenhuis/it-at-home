#!/usr/bin/env bash
# Send stdin to notify@abbenhuis.net.
# Envelope-from is <hostname>@abbenhuis.net (the MTA accepts @abbenhuis.net
# senders, e.g. maximus@abbenhuis.net). A From: header carrying the hostname as
# the display name is prepended so mail clients (Outlook) show a friendly name
# instead of the raw address. The first line of stdin becomes the Subject and
# stays as the first body line, so callers need no changes.
HOST="$(hostname -s)"
FROM_ADDR="$HOST@abbenhuis.net"

{
  IFS= read -r subject
  printf 'From: %s <%s>\nSubject: %s\n\n' "$HOST" "$FROM_ADDR" "$subject"
  printf '%s\n' "$subject"
  cat
} | msmtp -f "$FROM_ADDR" notify@abbenhuis.net
