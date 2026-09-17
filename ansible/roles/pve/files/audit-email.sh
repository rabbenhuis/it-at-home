#!/usr/bin/env bash
# Email critical auditd events (identity / sshd_config / cron key changes) since
# the last run. Silent when nothing new (empty output = no mail), matching the
# other security-scan cron jobs.
set -u

STAMP_DIR=/var/lib/audit-email
RUN_LOG="$STAMP_DIR/last-run"
FMT="%m/%d/%Y %H:%M:%S"

mkdir -p "$STAMP_DIR"

now() { date "+$FMT"; }

if [[ -f "$RUN_LOG" ]]; then
  SINCE="$(cat "$RUN_LOG")"
else
  SINCE="$(date -d '1 hour ago' "+$FMT")"
fi

OUT=""
for key in identity sshd_config cron; do
  OUT+="$(ausearch --start "$SINCE" --key "$key" --format text 2>/dev/null)"
done

printf '%s\n' "$(now)" > "$RUN_LOG"

if [[ -n "$OUT" ]]; then
  {
    echo "Auditd critical events - $(hostname)"
    echo "Since: $SINCE"
    echo
    echo "$OUT"
  } | /usr/local/bin/send-mail
fi