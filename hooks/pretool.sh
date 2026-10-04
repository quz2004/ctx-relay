#!/usr/bin/env bash
# Emergency path: at >= CTX_RELAY_EMERGENCY (default 90%) interrupt once to request the handoff.
set -u
[[ -n "${CTX_RELAY_RUN_DIR:-}" ]] || exit 0
. "$(dirname "$0")/../lib/ctx-lib.sh"
D="$CTX_RELAY_RUN_DIR"
in=$(cat)
[[ "$(cat "$D/state" 2>/dev/null || echo idle)" == idle && "${CTX_RELAY_AUTOCLEAR:-1}" == 1 ]] || exit 0
pct=$(ctx_usage_pct "$D" "$(jq -r '.transcript_path // empty' <<<"$in")")
(( ${CTX_RELAY_ROTATIONS:-0} > 0 )) && [[ ! -s "$D/baseline" ]] && exit 0
(( pct >= ${CTX_RELAY_EMERGENCY:-90} )) || exit 0
IFS='|' read -r name base depth extra <<<"$(ctx_plan_handoff "$CTX_RELAY_HANDOFF_DIR")"
printf '%s\n' "$name|$base|$depth|$extra" > "$D/request"
echo 0 > "$D/attempts"; echo requested > "$D/state"
jq -cn --arg r "$(ctx_block_reason "$name" "$base" "$depth" "$extra")" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
