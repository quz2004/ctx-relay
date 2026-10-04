# Wiring ctx-relay into `~/bin/claude-pro`

A ready-made full copy is at `dist/claude-pro` (`cp dist/claude-pro ~/bin/claude-pro`). The repo does not modify it. Or replace everything from
`if args_include_model "${FILTERED_ARGS[@]}"; then` to the end of the file with:

```bash
# ctx-relay: restart loop for automatic context rollover (CTX_RELAY_DISABLE=1 bypasses it).
CTX_RELAY_BIN="${CTX_RELAY_BIN:-$HOME/proj/notebooks/ctx-relay/bin/ctx-relay}"
launcher=(claude)
if [[ "${CTX_RELAY_DISABLE:-}" != "1" && -x "$CTX_RELAY_BIN" ]]; then
  launcher=("$CTX_RELAY_BIN")
fi

model_args=()
if ! args_include_model "${FILTERED_ARGS[@]}"; then
  model_args=(--model "${CLAUDE_PRO_MAIN_MODEL:-sonnet}")
fi

if [[ "$USE_COGNEE_DEVIN" == true ]]; then
  "${launcher[@]}" "${model_args[@]}" "${FILTERED_ARGS[@]}"
  exit $?
else
  exec "${launcher[@]}" "${model_args[@]}" "${FILTERED_ARGS[@]}"
fi
```

Without ctx-relay present it behaves exactly as before (`exec claude ...`). Settings:
`CTX_RELAY_THRESHOLD` (default 50), `CTX_RELAY_EMERGENCY` (90), `CTX_RELAY_AUTOCLEAR=0` (disable),
`CTX_RELAY_HANDOFF_DIR` (default: launch directory).
