#!/usr/bin/env bash
# Codex adapter. Registered in .codex/hooks.json for Stop and UserPromptSubmit.
# Translates Codex's payloads to the state machine in stop.sh and its answers back. Inert for any
# session not started through ctx-relay-codex.
set -u
[[ -n "${CTX_RELAY_RUN_DIR:-}" ]] || { echo '{}'; exit 0; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib/ctx-lib.sh"
D="$CTX_RELAY_RUN_DIR"
in=$(cat)
transcript=$(jq -r '.transcript_path // .transcriptPath // empty' <<<"$in")
active=$(jq -r '.stop_hook_active // .stopHookActive // false' <<<"$in")
state=$(cat "$D/state" 2>/dev/null || echo idle)

case "${1:-}" in
  Stop)
    out=$(jq -cn --arg t "$transcript" --argjson act "$active" \
      '{stop_hook_active:$act, transcript_path:$t, background_tasks:[]}' | "$HERE/stop.sh")
    reason=$(jq -r 'select(.decision == "block") | .reason' <<<"$out" 2>/dev/null)
    if [[ -n "$reason" ]]; then
      jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
    else
      echo '{}'
    fi
    ;;
  UserPromptSubmit)
    # Manual: user prompt is "relay now" or "relay"
    prompt=$(jq -r '.prompt // .user_prompt // empty' <<<"$in" | tr 'A-Z' 'a-z' | sed 's/[[:space:]]*[.!]*$//')
    if [[ "$prompt" == "relay now" || "$prompt" == "relay" ]]; then
      touch "$D/rotate.now"
      jq -cn --arg m "Manual rotation queued for next pause." '{systemMessage:$m}'
      exit 0
    fi
    echo '{}'
    ;;
  *) echo '{}' ;;
esac
