# ctx-relay shared helpers. Sourced by hooks; needs bash + jq.

CTX_RELAY_MAX_DEPTH=5

# Setting KEY (THRESHOLD, MIN_GROWTH, EMERGENCY, AUTOCLEAR): run config > env CTX_RELAY_KEY > default.
# The run config is written by `ctx-relay config` (the /relay slash command) and survives rotations.
ctx_cfg() {  # KEY DEFAULT
  local v ev="CTX_RELAY_$1"
  [[ -n "${CTX_RELAY_RUN_DIR:-}" ]] && v=$(sed -n "s/^$1=//p" "$CTX_RELAY_RUN_DIR/config" 2>/dev/null | tail -n 1)
  echo "${v:-${!ev:-$2}}"
}

# Context usage (integer percent). Prefer the statusline snapshot, else the transcript.
ctx_usage_pct() {
  local dir="$1" transcript="${2:-}" pct size used
  if [[ "${CTX_RELAY_BACKEND:-claude}" == agy ]]; then   # agy: no statusline snapshot; read its transcript
    [[ -f "$transcript" ]] || { echo 0; return; }
    # Each model step records input_tokens (uncached) + cache_read_tokens; their sum is the prompt size.
    used=$(tail -n 400 "$transcript" | jq -R 'fromjson? | select(.input_tokens != null) | .input_tokens + (.cache_read_tokens // 0)' 2>/dev/null | tail -n 1)
    echo $(( ${used:-0} * 100 / ${CTX_RELAY_WINDOW:-1000000} )); return
  fi
  if [[ -s "$dir/ctx.json" ]]; then
    pct=$(jq -r '.used_percentage // empty' "$dir/ctx.json" 2>/dev/null)
    [[ -n "$pct" ]] && { printf '%.0f' "$pct"; return; }
  fi
  [[ -f "$transcript" ]] || { echo 0; return; }
  size=$(jq -r '.context_window_size // empty' "$dir/ctx.json" 2>/dev/null)
  size=${size:-${CTX_RELAY_WINDOW:-200000}}
  used=$(tail -n 200 "$transcript" | jq -rs '
    [ .[] | select(.type=="assistant") | .message.usage // empty ] | last
    | ((.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0))' 2>/dev/null)
  echo $(( ${used:-0} * 100 / size ))
}

ctx_latest_handoff() {  # newest HANDOFF-YYYY-MM-DD-HHMM.md in $1 (name order == time order)
  ls -1 "$1" 2>/dev/null | grep -E '^HANDOFF-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}\.md$' | sort | tail -n 1
}

ctx_depth_of() {  # chain depth declared in the header of file $1
  sed -n '1,12p' "$1" 2>/dev/null | sed -n 's/^[Cc]hain depth:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1
}

ctx_new_name() {  # unique timestamped name in dir $1; bump minute if taken
  local dir="$1" i=0 n
  while :; do
    n="HANDOFF-$(date -v+${i}M +%Y-%m-%d-%H%M 2>/dev/null || date -d "+${i} min" +%Y-%m-%d-%H%M).md"
    [[ -e "$dir/$n" ]] || { echo "$n"; return; }
    i=$((i+1))
  done
}

# Prints "<name>|<base or none>|<depth>" for the next handoff.
ctx_plan_handoff() {
  local dir="$1" base depth
  base=$(ctx_latest_handoff "$dir")
  if [[ -z "$base" ]]; then
    echo "$(ctx_new_name "$dir")|none|1"; return
  fi
  depth=$(ctx_depth_of "$dir/$base"); depth=${depth:-1}
  if (( depth + 1 > CTX_RELAY_MAX_DEPTH )); then
    echo "$(ctx_new_name "$dir")|none|1|baseline-of:$base"
  else
    echo "$(ctx_new_name "$dir")|$base|$((depth+1))"
  fi
}

ctx_handoff_ok() {  # file $1 exists, non-empty, header depth == $2
  [[ -s "$1" ]] && [[ "$(ctx_depth_of "$1")" == "$2" ]]
}

ctx_block_reason() {  # name base depth [extra]
  local name="$1" base="$2" depth="$3" extra="${4:-}" how
  if [[ "$base" == none && -n "$extra" ]]; then
    how="The chain is at its depth limit. Write a CONSOLIDATED BASELINE: read the whole chain (starting from ${extra#baseline-of:}) and restate everything still relevant, self-contained. Header must be exactly: 'Base: none' and 'Chain depth: 1'."
  elif [[ "$base" == none ]]; then
    how="This is a baseline. Header must be exactly: 'Base: none' and 'Chain depth: 1'."
  else
    how="Write a DELTA against $base. Header must be exactly: 'Base: $base' and 'Chain depth: $depth'. Do not repeat what earlier handoffs say; reference earlier items by file and mark them done / not done / changed / dropped. Then add new goal, state, files touched, decisions, failed attempts, the exact next step and how to verify."
  fi
  printf 'Context is nearly full, so this session will be restarted fresh. Before stopping, write the handoff to %s/%s (exact name, project directory). %s Put the two header lines first. Write only the file, then stop and wait; do not continue the task.' \
    "${CTX_RELAY_HANDOFF_DIR}" "$name" "$how"
}

# Put the run into "requested" and print the instruction text for the agent.
ctx_request_handoff() {  # run_dir
  local D="$1" name base depth extra
  IFS='|' read -r name base depth extra <<<"$(ctx_plan_handoff "$CTX_RELAY_HANDOFF_DIR")"
  printf '%s\n' "$name|$base|$depth|$extra" > "$D/request"
  echo 0 > "$D/attempts"; echo requested > "$D/state"
  ctx_block_reason "$name" "$base" "$depth" "$extra"
}

# Register (install) or remove (uninstall) ctx-relay in a workspace's .agents/hooks.json, keeping other entries.
# Workspace, not global: agy 1.2.x loads only one named hook from ~/.agents/hooks.json, so a second entry there never runs.
# The hooks are inert unless the session was started through ctx-relay-agy (they check CTX_RELAY_RUN_DIR).
ctx_agy_hooks_json() {  # install|uninstall ROOT [DIR]
  local mode="$1" root="$2" f="${CTX_RELAY_AGY_HOOKS_JSON:-${3:-$PWD}/.agents/hooks.json}" cur tmp
  cur='{}'; [[ -s "$f" ]] && cur=$(cat "$f")
  jq -e 'type == "object"' <<<"$cur" >/dev/null 2>&1 || { echo "ctx-relay: $f is not a JSON object; not touching it" >&2; return 1; }
  if [[ "$mode" == install ]]; then
    tmp=$(jq --arg h "$root/hooks/agy-hook.sh" '. + {"ctx-relay": {
        PreInvocation: [{type: "command", command: ($h + " PreInvocation"), timeout: 15}],
        Stop:          [{type: "command", command: ($h + " Stop"),          timeout: 15}]}}' <<<"$cur") || return 1
  else
    tmp=$(jq 'del(.["ctx-relay"])' <<<"$cur") || return 1
  fi
  mkdir -p "$(dirname "$f")"
  [[ -s "$f" && ! -e "$f.bak-ctx-relay" ]] && cp "$f" "$f.bak-ctx-relay"
  printf '%s\n' "$tmp" > "$f"
  echo "ctx-relay: ${mode}ed agy hooks -> $f"
}
# Make sure the launch workspace has the hooks (a no-op when present). CTX_RELAY_AUTOINSTALL=0 opts out.
ctx_agy_ensure_hooks() {  # ROOT
  local f="${CTX_RELAY_AGY_HOOKS_JSON:-$PWD/.agents/hooks.json}"
  [[ "${CTX_RELAY_AUTOINSTALL:-1}" == 0 ]] && return 0
  jq -e --arg h "$1/hooks/agy-hook.sh Stop" '."ctx-relay".Stop[0].command == $h' "$f" >/dev/null 2>&1 && return 0
  ctx_agy_hooks_json install "$1" >&2
}
