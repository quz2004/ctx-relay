# ctx-relay

Automatic context rollover for Claude Code: write a handoff at the pause, restart with a fresh
context, and continue where you left off.

> Status: working prototype (fake-claude tests pass; real-claude end-to-end pending). See the latest `HANDOFF-*.md`.

## Rationale

Long Claude Code sessions degrade in two ways: quality and cost.

**Quality.** As context fills, the model gets slower to follow instructions, forgets early
decisions, and re-explores things it already knew. Native auto-compact fires late, rewrites history
lossily, and you do not control what survives.

**Cost.** Every request re-sends the whole conversation. Each user prompt and each tool call adds
a turn, and each turn pays for everything before it. If turn *i* adds roughly one unit of context,
the tokens processed over *n* turns are

    1 + 2 + 3 + ... + n = n(n+1)/2

which is quadratic in the number of turns. Prompt caching cuts the price of the re-read portion to
about 1/10, but that is a constant factor, not a change in growth. When the context is large, the
re-read bill still dominates the session.

Rolling over to a fresh context at a natural pause turns one long quadratic curve into several
short ones. Splitting *n* turns into *k* sessions of *n/k* turns costs about `k * (n/k)^2 / 2 =
n^2 / 2k`, roughly a *k*-fold saving on re-read tokens, minus the small cost of one handoff write
and one handoff read per rollover. A rollover at 50% of the window is far cheaper than carrying
the session to 90% and then compacting.

So ctx-relay aims for:

1. **A real handoff, not a lossy summary.** The agent itself writes the handoff in the live
   session, with full context, in a format you can read and edit.
2. **Rollover only at a pause.** It triggers from the Stop hook, when the agent is waiting for you,
   never mid-run. An emergency path exists near 90%.
3. **Subscription friendly.** Works with the Claude OAuth login. No API key, no proxy, no
   `claude -p`.
4. **Safe exits.** Ctrl-D, `/exit` and crashes exit normally and never relaunch.

## Design in one paragraph

A small launcher supervises `claude` in a loop instead of `exec`-ing it. Hooks and a statusline
wrapper (injected with `--settings`, so your global settings stay untouched) track context usage.
At the first Stop above the threshold (default 50%), the Stop hook asks the agent to write a
handoff; at the next Stop, it drops a flag and ends the process. The launcher sees the flag and
starts a fresh `claude` that reads the handoff and continues. Details are in the handoff files.

## Handoff convention

Handoffs are named `HANDOFF-YYYY-MM-DD-HHMM.md` and are never overwritten. The newest file is the
current one.

Handoffs are **deltas**. A session starts by reading the newest handoff and the handoffs it builds
on. When it writes a new one it does not repeat what an earlier handoff already says. It only:

- states the status of earlier items (`done`, `not done`, `changed`, `dropped`), by reference,
  for example "item 3 in HANDOFF-2026-10-03-2049.md: done";
- adds new goals, state, decisions, failed attempts, next step and how to verify.

Every handoff starts with a header:

    Base: HANDOFF-2026-10-03-2049.md      (or "none" for a baseline)
    Chain depth: 2

**Depth limit: 5.** A handoff's depth is its base's depth plus one. A baseline has depth 1. A
session must never write a handoff of depth 6. Instead it writes a new baseline: it reads the whole
chain and restates everything still relevant in one self-contained file, with `Base: none` and
`Chain depth: 1`. Older files can then be archived. This keeps a new session from having to read
more than 5 files, and keeps references from rotting.

## Usage

    bin/ctx-relay [claude flags...]        # drop-in for `claude`
    test/run-tests.sh                      # no real claude, no tmux; safe anywhere

Handoffs are written to the launch directory (`CTX_RELAY_HANDOFF_DIR`); gitignore `HANDOFF-*.md`
if you do not want them committed. `claude-pro` integration: `docs/claude-pro-integration.md`.
On relaunch, resume flags (`-c`, `-r`, `--session-id`) and the initial prompt are deliberately
dropped: the handoff replaces the old session, and resuming would reload the large context we are
escaping. (Detecting a trailing prompt is best-effort.)

Units: `CTX_RELAY_THRESHOLD` (default 50) is percent of the context window; `CTX_RELAY_MIN_GROWTH`
(default 15) is percentage points of growth over the fresh session's baseline.

## License

MIT
