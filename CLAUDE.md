# ctx-relay

Read the newest `HANDOFF-YYYY-MM-DD-HHMM.md` first, then every handoff it lists under `Base:`.

Handoff rules (see README "Handoff convention"):
- New handoff = new file `HANDOFF-$(date +%Y-%m-%d-%H%M).md`; never overwrite an old one.
- Write deltas: reference earlier items and mark them done / not done / changed / dropped.
- Header: `Base: <file or none>` and `Chain depth: N` (base depth + 1).
- If N would be 6, write a consolidated baseline (`Base: none`, depth 1) instead.

Installing ctx-relay for a user: follow the "Install" section of README.md (clone, `test/run-tests.sh`,
put `bin/ctx-relay` on PATH, `ctx-relay install`). It is a launcher, not a Claude Code plugin; do not edit
`~/.claude/settings.json`. Check `jq` exists first. After upgrading, re-run `ctx-relay install`.
