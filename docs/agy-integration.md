# ctx-relay with Antigravity CLI (`agy`)

`bin/ctx-relay-agy` is `ctx-relay` with `CTX_RELAY_BACKEND=agy`. Rotation, handoff files, `next`, `now` and the loop guard behave as for Claude.
Tested against agy 1.2.16 (end to end in tmux, plus `test/run-tests-agy.sh` with a fake agy).

## Install

Hooks live in the **workspace** `.agents/hooks.json`, not the global one: agy 1.2.x loaded only one named hook from `~/.agents/hooks.json`
(a second entry there never ran), while the same entry in a workspace file loaded and fired. `ctx-relay-agy` adds the entry to the launch
directory automatically (`CTX_RELAY_AUTOINSTALL=0` opts out). Manually: `ctx-relay-agy install [dir]` / `uninstall [dir]`
(other entries are kept; the original is backed up once as `hooks.json.bak-ctx-relay`). The hooks do nothing unless the session was
started through `ctx-relay-agy` (they check `CTX_RELAY_RUN_DIR`).

`agy-plus`: `cp dist/agy-plus ~/bin/agy-plus`. It launches through `ctx-relay-agy` (`CTX_RELAY_AGY_BIN` overrides the path),
`agy-plus next` starts fresh from the newest handoff, `CTX_RELAY_DISABLE=1` bypasses ctx-relay. Both the plain and the Devin branches are covered.

## How it differs from the Claude backend

- **No PreToolUse hook.** agy treats an empty `{}` answer from PreToolUse as a deny, so the emergency (>= 90%) path runs from PreInvocation instead.
- **Usage** is computed from the transcript (`input_tokens + cache_read_tokens` of the latest model step) because no payload carries a percentage.
  The default window is 1,000,000 (Gemini 3.8 Flash), so the 50% threshold is 500k tokens. Set `CTX_RELAY_WINDOW` (e.g. 200000) to rotate earlier.
- **agy exits 0 on SIGTERM**, so the wrapper trusts the fresh `rotate.flag` plus a valid handoff instead of exit code 143.
- Relaunch uses `agy -i "<prompt>"`; `-c`, `--continue`, `--conversation` and an earlier `-i` are dropped.
- **No `/relay` slash command.** Use `ctx-relay-agy config ...` or `ctx-relay-agy now` from another terminal, or type `relay now` in the session.
- **No notify-only display path**: `CTX_RELAY_AUTOCLEAR=0` just disables automatic rotation; manual `relay now` still works.
- Subcommands (`mcp`, `models`, ...), `-p/--print`, `-h`, `-v` run agy unchanged (print mode hangs on the workspace-trust dialog in an untrusted dir).
- Default state dir is `~/.agents/ctx-relay`, separate from Claude's `~/.claude/ctx-relay`.
- A new directory shows agy's workspace-trust prompt on first launch (default is "Yes, I trust this folder").
