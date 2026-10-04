#!/usr/bin/env bash
# agy adapter. Registered in agy's hooks.json (`ctx-relay-agy install`) for PreInvocation and Stop.
# Translates agy's payloads to the state machine in stop.sh and its answers back. Inert (prints {}) for any
# session not started through ctx-relay-agy. agy treats an empty PreToolUse answer as a deny, so there is
# deliberately no PreToolUse hook: the emergency path runs from PreInvocation instead.
set -u
[[ -n "${CTX_RELAY_RUN_DIR:-}" ]] || { echo '{}'; exit 0; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib/ctx-lib.sh"
D="$CTX_RELAY_RUN_DIR"
in=$(cat)
transcript=$(jq -r '.transcriptPath // empty' <<<"$in")
state=$(cat "$D/state" 2>/dev/null || echo idle)

case "${1:-}" in
  Stop)
    [[ -z "$(jq -r '.error // empty' <<<"$in")" ]] || { echo '{}'; exit 0; }
    bg='[]'; [[ "$(jq -r 'if .fullyIdle == false then "false" else "true" end' <<<"$in")" == true ]] || bg='[{"id":"background"}]'
    out=$(jq -cn --arg t "$transcript" --argjson bg "$bg" \
      '{stop_hook_active:false, transcript_path:$t, background_tasks:$bg}' | "$HERE/stop.sh")
    reason=$(jq -r 'select(.decision == "block") | .reason' <<<"$out" 2>/dev/null)
    if [[ -n "$reason" ]]; then jq -cn --arg r "$reason" '{decision:"continue", reason:$r}'; else echo '{}'; fi
    ;;
  PreInvocation)
    [[ "$state" == idle ]] || { echo '{}'; exit 0; }
    # Manual: the newest user message is "relay now" (or "relay"); ask for the handoff in this very turn.
    last=$(tail -n 400 "$transcript" 2>/dev/null | jq -R 'fromjson? | select(.type == "USER_INPUT") | .content' | tail -n 1 \
      | jq -r 'capture("<USER_REQUEST>\\s*(?<p>.*?)\\s*</USER_REQUEST>"; "s").p // empty' 2>/dev/null \
      | tr 'A-Z' 'a-z' | sed 's/[[:space:]]*[.!]*$//')
    if [[ "$last" == "relay now" || "$last" == "relay" ]]; then
      jq -cn --arg r "The user asked for a manual context rollover. $(ctx_request_handoff "$D")" \
        '{injectSteps:[{ephemeralMessage:$r}]}'
      exit 0
    fi
    # Emergency: usage at or above CTX_RELAY_EMERGENCY (default 90%) mid-run.
    if [[ "$(ctx_cfg AUTOCLEAR 1)" == 1 ]] && ! { (( ${CTX_RELAY_ROTATIONS:-0} > 0 )) && [[ ! -s "$D/baseline" ]]; }; then
      pct=$(ctx_usage_pct "$D" "$transcript")
      if (( pct >= $(ctx_cfg EMERGENCY 90) )); then
        jq -cn --arg r "$(ctx_request_handoff "$D")" '{injectSteps:[{userMessage:$r}]}'
        exit 0
      fi
    fi
    echo '{}'
    ;;
  *) echo '{}' ;;
esac
