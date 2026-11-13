# ctx-relay with OpenAI Codex CLI (`codex`)

`bin/ctx-relay-codex` is `ctx-relay` with `CTX_RELAY_BACKEND=codex`. Rotation, handoff files, `next`, `now`, and the loop guard behave identically to Claude and Antigravity.
Tested against Codex CLI (v0.167.2) via `test/run-tests-codex.sh` with a fake codex driver and interactive smoke tests.

## Install

Hooks live in the workspace `.codex/hooks.json`. `ctx-relay-codex` ensures the hook entry is present in the launch directory automatically (`CTX_RELAY_AUTOINSTALL=0` opts out). Manually: `ctx-relay-codex install [dir]` / `uninstall [dir]` (existing hooks are preserved, original file backed up once as `hooks.json.bak-ctx-relay`). The hooks do nothing unless the session was started through `ctx-relay-codex` (they check `CTX_RELAY_RUN_DIR`).

`codex-plus`: `cp dist/codex-plus ~/bin/codex-plus`. It launches through `ctx-relay-codex` (`CTX_RELAY_CODEX_BIN` overrides the path), `codex-plus next` starts fresh from the newest handoff, and `CTX_RELAY_DISABLE=1` bypasses ctx-relay. Both the default profile and Cognee/Devin branches are covered.

## How it differs from Claude and Antigravity

- **Hook registration**: Hooks use `.codex/hooks.json` under `hooks.Stop` and `hooks.UserPromptSubmit`.
- **CLI flags**: `ctx-relay-codex` automatically passes `--enable hooks --dangerously-bypass-hook-trust` when launching interactive sessions so workspace hooks run without manual confirmation prompts.
- **Usage tracking**: Evaluated from the session's rollout JSONL (`~/.codex/sessions/...`) by reading the last `token_count` event (`last_token_usage.input_tokens / model_context_window`). Default window is 258,400 (customizable via `CTX_RELAY_WINDOW`).
- **SIGTERM exit code**: Codex exits `2` on SIGTERM. The wrapper trusts exit code `2` as well as any fresh `rotate.flag` (< 60s) accompanied by a valid handoff file.
- **Relaunch**: Passes the handoff prompt as the trailing positional prompt to `codex`. Resume / continue flags are stripped.
- **Subcommands**: Subcommands (`exec`, `review`, `mcp`, `plugin`, etc.) and non-interactive flags (`-h`, `--help`, `-V`, `--version`) bypass the wrapper and run `codex` directly.
- **Default state directory**: `~/.codex/ctx-relay`, separate from `~/.claude/ctx-relay` and `~/.agents/ctx-relay`.
