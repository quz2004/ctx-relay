#!/usr/bin/env bash
# No real claude, no tmux: a fake claude drives the real hooks. Safe to run inside a live session.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); pass=0; fail=0
export CTX_RELAY_CLAUDE="$ROOT/test/fake-claude" CTX_RELAY_KILL_DELAY=0.2 CTX_RELAY_THRESHOLD=50
export PATH="$PATH"
ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
# run NAME [env...] -- sets $W (work dir), $LOG, $RC
run() {
  local name=$1; shift
  W="$T/$name"; mkdir -p "$W/home"; LOG="$W/fake.log"; : > "$LOG"
  ( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" "$@" \
      "$ROOT/bin/ctx-relay" --model sonnet >"$W/out" 2>"$W/err" ); RC=$?
}
launches() { cat "$LOG.count" 2>/dev/null || echo 0; }
echo "rotation (baseline)"
run rot FAKE_PCT=60
[[ $(launches) == 2 ]] && ok "relaunched once" || bad "launches=$(launches)"
h=$(ls "$W"/HANDOFF-*.md 2>/dev/null | head -1)
[[ -n "$h" ]] && grep -q 'Chain depth: 1' "$h" && ok "timestamped baseline written: $(basename "$h")" || bad "no handoff"
grep -q "launch 2: .*Read $W/HANDOFF-" "$LOG" && ok "fresh session told to read handoff" || bad "prompt: $(grep 'launch 2' "$LOG")"
grep -q -- '--model sonnet' <(grep 'launch 2' "$LOG") && ok "original flags kept" || bad "flags lost"
[[ $RC == 0 ]] && ok "wrapper exit 0 after user quits" || bad "rc=$RC"
echo "below threshold"
run low FAKE_PCT=10 FAKE_SCENARIO=rotate FAKE_WAIT=0
[[ $(launches) == 1 && ! -e "$W"/HANDOFF-* ]] 2>/dev/null && ok "no block, no relaunch" || bad "launches=$(launches)"
echo "Ctrl-D / /exit"
run quit FAKE_SCENARIO=quit
[[ $(launches) == 1 && $RC == 0 ]] && ok "single launch, rc 0" || bad "launches=$(launches) rc=$RC"
echo "SIGTERM'd without our flag (crash / kill)"
run die FAKE_SCENARIO=die143
[[ $(launches) == 1 && $RC == 143 ]] && ok "no relaunch, rc propagated" || bad "launches=$(launches) rc=$RC"
echo "stale flag"
run stale FAKE_SCENARIO=stale
[[ $(launches) == 1 ]] && ok "stale flag ignored" || bad "launches=$(launches)"
echo "agent never writes handoff"
run nohand FAKE_PCT=60 FAKE_BAD=1 FAKE_WAIT=0
[[ $(launches) == 1 && $RC == 0 ]] && ok "hook gives up after retries, no kill, no loop" || bad "launches=$(launches) rc=$RC"
[[ $(grep -c '"decision":"block"' "$LOG") == 3 ]] && ok "blocked exactly 3 times then released" || bad "blocks=$(grep -c decision "$LOG")"
echo "no rotation loop after relaunch (the reported bug)"
run loop FAKE_PCT=60 FAKE_RELAUNCH_PCTS="60 65"
[[ $(launches) == 2 ]] && ok "high-baseline relaunch does not rotate again" || bad "launches=$(launches)"
grep -q 'relaunch-stop@60: none' "$LOG" && grep -q 'relaunch-stop@65: none' "$LOG" && ok "first Stop records baseline; +5 growth ignored" || bad "$(grep relaunch-stop "$LOG")"
run grow FAKE_PCT=60 FAKE_RELAUNCH_PCTS="25 55"
grep -q 'relaunch-stop@55: {"decision":"block"' "$LOG" && ok "real growth (+30) over baseline does request a new handoff" || bad "$(grep relaunch-stop "$LOG")"
echo "manual rotation"
run man FAKE_PCT=10 FAKE_SCENARIO=manual
[[ $(launches) == 2 ]] && ls "$W"/HANDOFF-*.md >/dev/null 2>&1 && ok "'relay now' at 10% usage rotates" || bad "launches=$(launches)"
run manoff FAKE_PCT=10 FAKE_SCENARIO=manual CTX_RELAY_AUTOCLEAR=0
[[ $(launches) == 2 ]] && ok "works with AUTOCLEAR=0 (manual-only mode)" || bad "launches=$(launches)"
run nf FAKE_SCENARIO=nowfile
[[ $(launches) == 2 ]] && ok "'ctx-relay now' trigger file rotates at next Stop" || bad "launches=$(launches)"
run noauto FAKE_PCT=60 CTX_RELAY_AUTOCLEAR=0 FAKE_WAIT=0
[[ $(launches) == 1 ]] && ok "AUTOCLEAR=0: no automatic rotation" || bad "launches=$(launches)"
echo "config (/relay)"
mkdir -p "$T/cfg/home"; echo THRESHOLD=70 > "$T/cfg/home/config"
run cfg FAKE_PCT=60 FAKE_WAIT=0 CTX_RELAY_HOME="$T/cfg/home"
[[ $(launches) == 1 ]] && ok "saved config threshold=70 beats env 50 (60% -> no rotation)" || bad "launches=$(launches)"
R="$T/cfgrun"; mkdir -p "$R"
out=$(CTX_RELAY_RUN_DIR="$R" CTX_RELAY_HOME="$T/cfg/home" "$ROOT/bin/ctx-relay" config threshold=40 growth=10 autoclear=off --save)
grep -q '^THRESHOLD=40' "$R/config" && grep -q '^MIN_GROWTH=10' "$R/config" && grep -q '^AUTOCLEAR=0' "$R/config" && grep -q 'threshold  40%' <<<"$out" && ok "config sets values" || bad "config: $out"
grep -q '^THRESHOLD=40' "$T/cfg/home/config" && ok "--save writes defaults" || bad "save"
CTX_RELAY_RUN_DIR="$R" "$ROOT/bin/ctx-relay" config threshold=abc >/dev/null 2>&1 && bad "bad value accepted" || ok "rejects bad value"
echo "chain depth"
mkdir -p "$T/chain"; W="$T/chain"
printf 'Base: none\nChain depth: 1\n' > "$W/HANDOFF-2026-01-01-0000.md"
printf 'Base: HANDOFF-2026-01-01-0000.md\nChain depth: 2\n' > "$W/HANDOFF-2026-01-01-0100.md"
run2() { local n=$1; shift; W="$T/$n"; LOG="$W/fake.log"; : > "$LOG"; ( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" FAKE_PCT=60 "$ROOT/bin/ctx-relay" >/dev/null 2>&1 ); }
mkdir -p "$T/d2/home"; cp "$T/chain"/HANDOFF-* "$T/d2/"; run2 d2
new=$(ls "$T"/d2/HANDOFF-*.md | sort | tail -1)
grep -q 'Base: HANDOFF-2026-01-01-0100.md' "$new" && grep -q 'Chain depth: 3' "$new" && ok "delta: base=newest, depth 3" || bad "d2: $(head -2 "$new" | tr '\n' ' ')"
mkdir -p "$T/d5/home"; printf 'Base: x\nChain depth: 5\n' > "$T/d5/HANDOFF-2026-01-01-0200.md"; run2 d5
new=$(ls "$T"/d5/HANDOFF-*.md | sort | tail -1)
grep -q 'Base: none' "$new" && grep -q 'Chain depth: 1' "$new" && ok "depth 5 -> consolidated baseline (never depth 6)" || bad "d5: $(head -2 "$new" | tr '\n' ' ')"
echo "concurrent runs"
mkdir -p "$T/ca/home" "$T/cb/home"
for n in ca cb; do ( W="$T/$n"; cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$W/fake.log" FAKE_PCT=60 "$ROOT/bin/ctx-relay" >/dev/null 2>&1 ) & done; wait
[[ $(cat "$T/ca/fake.log.count") == 2 && $(cat "$T/cb/fake.log.count") == 2 ]] && ls "$T"/ca/HANDOFF-* "$T"/cb/HANDOFF-* >/dev/null 2>&1 && ok "both rotated independently" || bad "concurrent"
echo; echo "passed=$pass failed=$fail"; rm -rf "$T"; exit $((fail>0))
