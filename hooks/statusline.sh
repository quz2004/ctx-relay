#!/usr/bin/env bash
# Snapshot context usage for the Stop hook, then delegate to the user's own statusline.
in=$(cat)
if [[ -n "${CTX_RELAY_RUN_DIR:-}" ]]; then
  printf '%s' "$in" | jq -c '{used_percentage: .context_window.used_percentage,
      context_window_size: .context_window.context_window_size, ts: now}' \
    > "$CTX_RELAY_RUN_DIR/ctx.json.tmp" 2>/dev/null &&
    mv "$CTX_RELAY_RUN_DIR/ctx.json.tmp" "$CTX_RELAY_RUN_DIR/ctx.json"
fi
if [[ -n "${CTX_RELAY_ORIG_STATUSLINE:-}" ]]; then
  printf '%s' "$in" | bash -c "$CTX_RELAY_ORIG_STATUSLINE"
fi
