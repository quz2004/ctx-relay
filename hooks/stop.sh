#!/usr/bin/env bash
# Stop hook. State machine: idle -> requested -> rotating (see HANDOFF / README).
set -u
[[ -n "${CTX_RELAY_RUN_DIR:-}" ]] || exit 0
. "$(dirname "$0")/../lib/ctx-lib.sh"

D="$CTX_RELAY_RUN_DIR"
in=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$in")
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
bg=$(jq -r '((.background_tasks // []) | length)' <<<"$in")
state=$(cat "$D/state" 2>/dev/null || echo idle)
thr=${CTX_RELAY_THRESHOLD:-50}

block() { jq -cn --arg r "$1" '{decision:"block",reason:$r}'; exit 0; }

claude_pid() {  # ancestor whose parent is the wrapper
  local p=$PPID pp
  while [[ -n "$p" && "$p" -gt 1 ]]; do
    pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [[ "$pp" == "${CTX_RELAY_WRAPPER_PID:-x}" ]] && { echo "$p"; return; }
    p=$pp
  done
}

case "$state" in
  idle)
    [[ "$active" == true || "$bg" -gt 0 ]] && exit 0
    [[ "${CTX_RELAY_AUTOCLEAR:-1}" == 1 ]] || exit 0
    pct=$(ctx_usage_pct "$D" "$transcript")
    (( pct >= thr )) || exit 0
    plan=$(ctx_plan_handoff "$CTX_RELAY_HANDOFF_DIR")
    IFS='|' read -r name base depth extra <<<"$plan"
    printf '%s\n' "$name|$base|$depth|$extra" > "$D/request"
    echo 0 > "$D/attempts"; echo requested > "$D/state"
    block "$(ctx_block_reason "$name" "$base" "$depth" "$extra")"
    ;;
  requested)
    IFS='|' read -r name base depth extra < "$D/request"
    if ctx_handoff_ok "$CTX_RELAY_HANDOFF_DIR/$name" "$depth"; then
      pid=$(claude_pid)
      if [[ -z "$pid" ]]; then echo idle > "$D/state"; exit 0; fi
      echo "$name" > "$D/handoff"; echo rotating > "$D/state"
      touch "$D/rotate.flag"
      ( sleep "${CTX_RELAY_KILL_DELAY:-1}"; kill -TERM "$pid" ) >/dev/null 2>&1 &
      disown
      exit 0
    fi
    n=$(( $(cat "$D/attempts" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/attempts"
    if (( n > 2 )); then echo idle > "$D/state"; exit 0; fi   # give up; never loop
    block "Handoff missing or malformed. $(ctx_block_reason "$name" "$base" "$depth" "$extra")"
    ;;
  *) exit 0 ;;
esac
