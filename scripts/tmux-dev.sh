#!/usr/bin/env zsh

if ! grep -qi "microsoft" /proc/version; then
  echo "This tmux environment is only intended for WSL/Linux."
  exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"

DEV_CONTAINER="${1:-}"

if [[ -n "$DEV_CONTAINER" ]]; then
  if [[ ! -d "$PROJECT_ROOT/.devcontainer/$DEV_CONTAINER" ]]; then
    echo "Error: devcontainer '$DEV_CONTAINER' not found under .devcontainer/"
    exit 1
  fi
  SESSION_NAME="$DEV_CONTAINER"
  WINDOW_NAME="$DEV_CONTAINER"
else
  SESSION_NAME="${PROJECT_ROOT:t}"
  WINDOW_NAME="dev"
fi

OPENCODE_WIDTH_PCT=15
SHELL_HEIGHT_PCT=15

tmux kill-session -t "$SESSION_NAME" 2>/dev/null

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Session '$SESSION_NAME' already exists. Attaching..."
  tmux attach -t "$SESSION_NAME"
  exit 0
fi

PORT=$(ss -tln | awk '{print $4}' | grep -oE '[0-9]+$' | sort -n | awk 'BEGIN{p=49152} {if($1==p) p++} END{print p}')

trap 'tmux kill-session -t "$SESSION_NAME"; exit 1' ERR

tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -n "$WINDOW_NAME"
tmux set-environment -t "$SESSION_NAME" OPENCODE_PORT "$PORT"
EDITOR_PANE=$(tmux display-message -t "$SESSION_NAME:$WINDOW_NAME" -p '#{pane_id}')

AGENT_CMD=""
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  AGENT_CMD="export SSH_AUTH_SOCK='${SSH_AUTH_SOCK}'; "
fi

if [[ -n "$DEV_CONTAINER" ]]; then
  EDITOR_CMD="${AGENT_CMD}devpod up .devcontainer/$DEV_CONTAINER --ide none --devcontainer-path devcontainer.json && devpod ssh $DEV_CONTAINER --agent-forwarding --command nvim"
  RETRY="until devpod ssh $DEV_CONTAINER --agent-forwarding --command true >/dev/null 2>&1; do sleep 2; done"
  OPENCODE_CMD="${AGENT_CMD}${RETRY}; devpod ssh $DEV_CONTAINER --agent-forwarding --command \"opencode --port $PORT\""
  SHELL_CMD="${AGENT_CMD}${RETRY}; clear; devpod ssh $DEV_CONTAINER --agent-forwarding"
else
  EDITOR_CMD="nvim"
  OPENCODE_CMD="opencode --port $PORT"
  SHELL_CMD=""
fi

tmux send-keys -t "$EDITOR_PANE" "$EDITOR_CMD" C-m

OPENCODE_PANE=$(tmux split-window -h -t "$SESSION_NAME:$WINDOW_NAME" -c "$PROJECT_ROOT" -P -F '#{pane_id}')

tmux send-keys -t "$OPENCODE_PANE" "$OPENCODE_CMD" C-m

tmux select-pane -t "$SESSION_NAME:$WINDOW_NAME" -L

SHELL_PANE=$(tmux split-window -v -t "$SESSION_NAME:$WINDOW_NAME" -c "$PROJECT_ROOT" -P -F '#{pane_id}')

if [[ -n "$SHELL_CMD" ]]; then
  tmux send-keys -t "$SHELL_PANE" "$SHELL_CMD" C-m
fi

tmux select-pane -t "$EDITOR_PANE"

tmux select-layout -t "$SESSION_NAME:$WINDOW_NAME" "f3eb,250x67,0,0{159x67,0,0[159x52,0,0,0,159x14,0,53,2],90x67,160,0,1}"

trap - ERR

tmux attach -t "$SESSION_NAME"
