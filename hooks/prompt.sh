#!/usr/bin/env bash
# UserPromptSubmit: typing "relay now" asks for a handoff in this very turn; the Stop hook then rotates.
set -u
[[ -n "${CTX_RELAY_RUN_DIR:-}" ]] || exit 0
. "$(dirname "$0")/../lib/ctx-lib.sh"
D="$CTX_RELAY_RUN_DIR"
p=$(jq -r '.prompt // empty' | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*[.!]*$//')
[[ "$p" == "relay now" || "$p" == "relay" ]] || exit 0
[[ "$(cat "$D/state" 2>/dev/null || echo idle)" == idle ]] || exit 0
jq -cn --arg r "The user asked for a manual context rollover. $(ctx_request_handoff "$D")" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$r}}'
