#!/usr/bin/env bash
# agy backend: a fake agy drives the real adapter hooks. No real agy, safe anywhere (never touches ~/.agents).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); pass=0; fail=0
export CTX_RELAY_AGY="$ROOT/test/fake-agy" CTX_RELAY_KILL_DELAY=0.2 CTX_RELAY_THRESHOLD=50 CTX_RELAY_WINDOW=100000
ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
# run NAME [env...] -- ctx-relay-agy with user flags `--model m -c --conversation abc`; sets $W $LOG $RC
run() {
  local name=$1; shift
  W="$T/$name"; mkdir -p "$W/home"; LOG="$W/fake.log"; : > "$LOG"
  ( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" "$@" \
      "$ROOT/bin/ctx-relay-agy" --model m -c --conversation abc >"$W/out" 2>"$W/err" ); RC=$?
}
launches() { cat "$LOG.count" 2>/dev/null || echo 0; }
echo "rotation (baseline)"
run rot FAKE_PCT=60
[[ $(launches) == 2 ]] && ok "relaunched once (agy exits 0 on SIGTERM; flag is the signal)" || bad "launches=$(launches) err=$(cat "$W/err")"
h=$(ls "$W"/HANDOFF-*.md 2>/dev/null | head -1)
[[ -n "$h" ]] && grep -q 'Chain depth: 1' "$h" && ok "baseline written: $(basename "$h")" || bad "no handoff"
grep -q "launch 2: .* -i Read $W/HANDOFF-" "$LOG" && ok "fresh session started with -i <read handoff>" || bad "launch 2: $(grep 'launch 2' "$LOG")"
grep 'launch 2' "$LOG" | grep -q -- '--model m' && ok "other flags kept" || bad "flags lost"
l1=$(grep 'launch 1' "$LOG"); l2=$(grep 'launch 2' "$LOG")
[[ "$l1" == *' -c '* && "$l1" == *'--conversation abc'* ]] && ok "first launch keeps the user's -c/--conversation" || bad "launch 1: $l1"
[[ "$l2" != *' -c '* && "$l2" != *'--conversation'* ]] && ok "relaunch drops -c/--conversation (would reload the big context)" || bad "launch 2: $l2"
[[ $RC == 0 ]] && ok "wrapper exit 0 after user quits" || bad "rc=$RC"
echo "below threshold / quit / stale flag"
run low FAKE_PCT=10 FAKE_WAIT=0
[[ $(launches) == 1 && ! -e "$W"/HANDOFF-* ]] 2>/dev/null && ok "10%: no continue, no relaunch" || bad "launches=$(launches)"
run quit FAKE_SCENARIO=quit
[[ $(launches) == 1 && $RC == 0 ]] && ok "quit: single launch, rc 0" || bad "launches=$(launches) rc=$RC"
run stale FAKE_SCENARIO=stale
[[ $(launches) == 1 ]] && ok "stale flag ignored" || bad "launches=$(launches)"
echo "agent never writes handoff"
run nohand FAKE_PCT=60 FAKE_BAD=1 FAKE_WAIT=0
[[ $(launches) == 1 && $RC == 0 ]] && ok "gives up after retries, no kill, no loop" || bad "launches=$(launches) rc=$RC"
[[ $(grep -c '"decision":"continue"' "$LOG") == 3 ]] && ok "forced to continue exactly 3 times, then released" || bad "continues=$(grep -c '"decision":"continue"' "$LOG")"
echo "no rotation loop after relaunch"
run loop FAKE_PCT=60 FAKE_RELAUNCH_PCTS="60 65"
[[ $(launches) == 2 ]] && grep -q 'relaunch-stop@60: {}' "$LOG" && grep -q 'relaunch-stop@65: {}' "$LOG" && ok "high baseline recorded; +5 growth ignored" || bad "$(grep -E 'relaunch|launch' "$LOG")"
run grow FAKE_PCT=60 FAKE_RELAUNCH_PCTS="25 55"
grep -q 'relaunch-stop@55: {"decision":"continue"' "$LOG" && ok "real growth (+30) over baseline requests a new handoff" || bad "$(grep relaunch-stop "$LOG")"
echo "manual rotation (typing 'relay now')"
run man FAKE_SCENARIO=manual
[[ $(launches) == 2 ]] && ls "$W"/HANDOFF-*.md >/dev/null 2>&1 && ok "'relay now' at 10% rotates" || bad "launches=$(launches)"
run manoff FAKE_SCENARIO=manual CTX_RELAY_AUTOCLEAR=0
[[ $(launches) == 2 ]] && ok "works with AUTOCLEAR=0 (manual-only)" || bad "launches=$(launches)"
run nf FAKE_SCENARIO=nowfile
[[ $(launches) == 2 ]] && ok "'ctx-relay now' trigger file rotates at next Stop" || bad "launches=$(launches)"
run noauto FAKE_PCT=60 CTX_RELAY_AUTOCLEAR=0 FAKE_WAIT=0
[[ $(launches) == 1 ]] && ok "AUTOCLEAR=0: no automatic rotation" || bad "launches=$(launches)"
echo "emergency (PreInvocation, no PreToolUse hook)"
run emg FAKE_SCENARIO=emergency FAKE_PCT=95
[[ $(launches) == 2 ]] && grep -q '"userMessage"' "$LOG" && ok "95% mid-run: handoff injected, then rotated" || bad "launches=$(launches) $(grep '^pre' "$LOG" | head -c 200)"
run emg2 FAKE_SCENARIO=emergency FAKE_PCT=85 FAKE_WAIT=0
grep -q '^pre: {}' "$LOG" && [[ $(launches) == 1 ]] && ok "85% (below 90): nothing injected" || bad "$(grep '^pre' "$LOG")"
echo "pass-through (not supervised)"
W="$T/pt"; mkdir -p "$W/home"; LOG="$W/fake.log"; : > "$LOG"
for a in "mcp list" "-p hello" "--version" "models"; do
  rm -f "$LOG.count"; ( cd "$W" && env CTX_RELAY_HOME="$W/home" FAKE_LOG="$LOG" FAKE_WAIT=0 "$ROOT/bin/ctx-relay-agy" $a >/dev/null 2>&1 )
  grep -q "launch 1: $a\$" "$LOG" && [[ $(launches) == 1 ]] && ok "'$a' runs agy unchanged" || bad "'$a': $(tail -1 "$LOG")"
done
[[ ! -d "$W/home/runs" ]] && ok "no run directory created for pass-through" || bad "run dir created"
echo "default state dir"
W="$T/hm"; mkdir -p "$W/h"; LOG="$W/fake.log"; : > "$LOG"
( cd "$W" && env -u CTX_RELAY_HOME HOME="$W/h" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" FAKE_PCT=10 FAKE_WAIT=0 "$ROOT/bin/ctx-relay-agy" >/dev/null 2>&1 )
ls -d "$W"/h/.agents/ctx-relay/runs/* >/dev/null 2>&1 && ok "runs live under ~/.agents/ctx-relay (separate from Claude's)" || bad "no runs dir"
echo "ctx-relay-agy next"
mkdir -p "$T/nx/home"; printf 'Base: none\nChain depth: 1\n' > "$T/nx/HANDOFF-2026-01-01-0000.md"
printf 'Base: HANDOFF-2026-01-01-0000.md\nChain depth: 2\n' > "$T/nx/HANDOFF-2026-01-01-0100.md"
W="$T/nx"; LOG="$W/fake.log"; : > "$LOG"
( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" FAKE_PCT=10 FAKE_WAIT=0 "$ROOT/bin/ctx-relay-agy" next --model m >/dev/null 2>&1 )
grep -q "launch 1: --model m -i Read $W/HANDOFF-2026-01-01-0100.md" "$LOG" && ok "next: reads newest handoff, keeps flags" || bad "next: $(grep 'launch 1' "$LOG")"
echo "background tasks / inert guard / usage"
BG="$T/bg"; mkdir -p "$BG"; echo idle > "$BG/state"; printf '{"type":"PLANNER_RESPONSE","input_tokens":59000,"cache_read_tokens":1000}\n' > "$BG/t.jsonl"
bgstop() { jq -cn --argjson i "$1" --arg t "$BG/t.jsonl" '{transcriptPath:$t,fullyIdle:$i,terminationReason:"NO_TOOL_CALL",error:""}' \
  | env CTX_RELAY_BACKEND=agy CTX_RELAY_RUN_DIR="$BG" CTX_RELAY_HANDOFF_DIR="$BG" CTX_RELAY_ROTATIONS=0 "$ROOT/hooks/agy-hook.sh" Stop; }
[[ "$(bgstop false)" == '{}' && "$(cat "$BG/state")" == idle ]] && ok "background tasks running (fullyIdle=false): deferred" || bad "bg rotated"
bgstop true | grep -q '"decision":"continue"' && ok "all idle: handoff requested" || bad "bg: not requested"
for ev in Stop PreInvocation; do
  [[ "$(echo '{}' | env -u CTX_RELAY_RUN_DIR "$ROOT/hooks/agy-hook.sh" $ev)" == '{}' ]] || bad "inert $ev"
done; ok "outside ctx-relay-agy sessions every event answers {} (no-op)"
u=$(env CTX_RELAY_BACKEND=agy CTX_RELAY_WINDOW=100000 bash -c ". '$ROOT/lib/ctx-lib.sh'; ctx_usage_pct '$BG' '$BG/t.jsonl'")
[[ "$u" == 60 ]] && ok "usage = (input + cache_read) / window = 60%" || bad "usage=$u"
echo "install / uninstall"
HJ="$T/hooks.json"; echo '{"cognee-memory":{"Stop":[{"type":"command","command":"x"}]}}' > "$HJ"
mkdir -p "$T/ws/.agents"; HJ="$T/ws/.agents/hooks.json"; cp "$T/hooks.json" "$HJ"
( cd "$T/ws" && "$ROOT/bin/ctx-relay-agy" install >/dev/null && "$ROOT/bin/ctx-relay-agy" install >/dev/null )
[[ "$(jq -r 'keys|join(",")' "$HJ")" == "cognee-memory,ctx-relay" && "$(jq '."ctx-relay".Stop|length' "$HJ")" == 1 ]] && ok "install is idempotent and keeps other hooks" || bad "$(cat "$HJ")"
jq -e '."ctx-relay" | has("PreToolUse") | not' "$HJ" >/dev/null && ok "no PreToolUse hook (agy denies an empty answer)" || bad "PreToolUse registered"
[[ -f "$HJ.bak-ctx-relay" ]] && ok "original backed up" || bad "no backup"
( cd "$T/ws" && "$ROOT/bin/ctx-relay-agy" uninstall >/dev/null )
[[ "$(jq -r 'keys|join(",")' "$HJ")" == "cognee-memory" ]] && ok "uninstall removes only ctx-relay" || bad "$(cat "$HJ")"
mkdir -p "$T/auto/home"; ( cd "$T/auto" && env CTX_RELAY_HOME="$T/auto/home" FAKE_LOG="$T/auto/log" FAKE_PCT=10 FAKE_WAIT=0 "$ROOT/bin/ctx-relay-agy" >/dev/null 2>&1 )
jq -e '."ctx-relay".Stop' "$T/auto/.agents/hooks.json" >/dev/null 2>&1 && ok "launch auto-installs hooks into the workspace" || bad "no workspace hooks"
mkdir -p "$T/optout/home"; ( cd "$T/optout" && env CTX_RELAY_AUTOINSTALL=0 CTX_RELAY_HOME="$T/optout/home" FAKE_LOG="$T/optout/log" FAKE_PCT=10 FAKE_WAIT=0 "$ROOT/bin/ctx-relay-agy" >/dev/null 2>&1 )
[[ ! -e "$T/optout/.agents" ]] && ok "CTX_RELAY_AUTOINSTALL=0 leaves the workspace alone" || bad "installed despite opt-out"
echo; echo "passed=$pass failed=$fail"; rm -rf "$T"; exit $((fail>0))
