#!/usr/bin/env bash
# Standalone test suite for ctx-relay with codex backend. Drives fake-codex and real hooks/codex-hook.sh.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); pass=0; fail=0
export CTX_RELAY_CODEX="$ROOT/test/fake-codex" CTX_RELAY_KILL_DELAY=0.2 CTX_RELAY_THRESHOLD=50
export CTX_RELAY_BACKEND=codex
export CTX_RELAY_WINDOW=258400
export PATH="$PATH"
unset CTX_RELAY_RUN_DIR 2>/dev/null || true

ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
run() {
  local name=$1; shift
  W="$T/$name"; mkdir -p "$W/home"; LOG="$W/fake.log"; : > "$LOG"
  ( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" "$@" \
      "$ROOT/bin/ctx-relay-codex" -s danger-full-access >"$W/out" 2>"$W/err" ); RC=$?
}
launches() { cat "$LOG.count" 2>/dev/null || echo 0; }

echo "rotation (baseline)"
run rot FAKE_PCT=60
[[ $(launches) == 2 ]] && ok "relaunched once (codex exits 2 on SIGTERM; flag is the signal)" || bad "launches=$(launches)"
h=$(ls "$W"/HANDOFF-*.md 2>/dev/null | head -1)
[[ -n "$h" ]] && grep -q 'Chain depth: 1' "$h" && ok "baseline written: $(basename "$h")" || bad "no handoff"
grep -q "launch 2: .*Read $W/HANDOFF-" "$LOG" && ok "fresh session started with <read handoff>" || bad "prompt: $(grep 'launch 2' "$LOG")"
grep -q -- '-s danger-full-access' <(grep 'launch 2' "$LOG") && ok "other flags kept" || bad "flags lost"
[[ $RC == 0 ]] && ok "wrapper exit 0 after user quits" || bad "rc=$RC"

echo "below threshold / quit / stale flag"
run low FAKE_PCT=10 FAKE_WAIT=0
[[ $(launches) == 1 && ! -e "$W"/HANDOFF-* ]] 2>/dev/null && ok "10%: no block, no relaunch" || bad "launches=$(launches)"
run quit FAKE_SCENARIO=quit
[[ $(launches) == 1 && $RC == 0 ]] && ok "quit: single launch, rc 0" || bad "launches=$(launches) rc=$RC"
run stale FAKE_SCENARIO=stale
[[ $(launches) == 1 ]] && ok "stale flag ignored" || bad "launches=$(launches)"

echo "agent never writes handoff"
run nohand FAKE_PCT=60 FAKE_BAD=1 FAKE_WAIT=0
[[ $(launches) == 1 && $RC == 0 ]] && ok "gives up after retries, no kill, no loop" || bad "launches=$(launches)"
[[ $(grep -c '"decision":"block"' "$LOG") == 3 ]] && ok "blocked exactly 3 times, then released" || bad "blocks=$(grep -c decision "$LOG")"

echo "no rotation loop after relaunch"
run loop FAKE_PCT=60 FAKE_RELAUNCH_PCTS="60 65 90"
grep -q 'relaunch-stop@60: {}' "$LOG" && grep -q 'relaunch-stop@65: {}' "$LOG" && ok "high baseline recorded; +5 growth ignored" || bad "stops: $(grep relaunch-stop "$LOG")"
grep -q 'relaunch-stop@90: {"decision":"block"' "$LOG" && ok "real growth (+30) over baseline requests a new handoff" || bad "growth not fired"

echo "no duplicate handoff (agent already wrote one this turn)"
run self FAKE_SCENARIO=selfwrite FAKE_PCT=60
[[ $(launches) == 2 ]] && ok "fresh self-written handoff is adopted: rotates, no second handoff" || bad "launches=$(launches)"
[[ $(grep -c 'stop1: {"decision":"block"' "$LOG") == 0 ]] && ok "no second handoff requested" || bad "stop1 requested"
run staleh FAKE_SCENARIO=stalehand FAKE_PCT=60
[[ $(grep -c 'stop1: {"decision":"block"' "$LOG") == 1 ]] && ok "old handoff (before this session) is not adopted" || bad "not requested"

echo "manual rotation (typing 'relay now')"
run manual FAKE_SCENARIO=manual
[[ $(launches) == 2 ]] && ok "'relay now' at 10% rotates" || bad "launches=$(launches)"
run man_noauto FAKE_SCENARIO=manual CTX_RELAY_AUTOCLEAR=0
[[ $(launches) == 2 ]] && ok "works with AUTOCLEAR=0 (manual-only)" || bad "launches=$(launches)"
run nowf FAKE_SCENARIO=nowfile
[[ $(launches) == 2 ]] && ok "'ctx-relay now' trigger file rotates at next Stop" || bad "launches=$(launches)"
run noauto FAKE_PCT=60 CTX_RELAY_AUTOCLEAR=0 FAKE_WAIT=0
[[ $(launches) == 1 ]] && ok "AUTOCLEAR=0: no automatic rotation" || bad "launches=$(launches)"

echo "pass-through (not supervised)"
mkdir -p "$T/pass/home"
( cd "$T/pass" && env CTX_RELAY_HOME="$T/pass/home" "$ROOT/bin/ctx-relay-codex" --version >/dev/null 2>&1 )
[[ ! -d "$T/pass/home/runs" ]] && ok "--version runs codex unchanged" || bad "created run"
( cd "$T/pass" && env CTX_RELAY_HOME="$T/pass/home" "$ROOT/bin/ctx-relay-codex" -h >/dev/null 2>&1 )
[[ ! -d "$T/pass/home/runs" ]] && ok "-h runs codex unchanged" || bad "created run"

echo "default state dir"
mkdir -p "$T/def/home"
( cd "$T/def" && env CTX_RELAY_HOME="$T/def/home" HOME="$T/def/home" "$ROOT/bin/ctx-relay-codex" -h >/dev/null 2>&1 )
grep -q 'codex/ctx-relay' <(grep 'BASE_DIR=' "$ROOT/bin/ctx-relay") && ok "runs live under ~/.codex/ctx-relay" || bad "dir"

echo "ctx-relay-codex next"
mkdir -p "$T/nx/home"; W="$T/nx"; LOG="$W/fake.log"; : > "$LOG"
printf 'Base: none\nChain depth: 1\n' > "$W/HANDOFF-2026-01-01-0100.md"
( cd "$W" && env CTX_RELAY_HOME="$W/home" CTX_RELAY_HANDOFF_DIR="$W" FAKE_LOG="$LOG" FAKE_PCT=60 FAKE_WAIT=0 "$ROOT/bin/ctx-relay-codex" next -s danger-full-access >/dev/null 2>&1 )
grep -q "launch 1: .*-s danger-full-access .*Read $W/HANDOFF-2026-01-01-0100.md" "$LOG" && ok "next: reads newest handoff, keeps flags" || bad "next: $(grep 'launch 1' "$LOG")"

echo "install / uninstall"
mkdir -p "$T/inst/.codex"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}\n' > "$T/inst/.codex/hooks.json"
( cd "$T/inst" && env CTX_RELAY_CODEX_HOOKS_JSON="$T/inst/.codex/hooks.json" "$ROOT/bin/ctx-relay-codex" install >/dev/null 2>&1 )
grep -q 'codex-hook.sh Stop' "$T/inst/.codex/hooks.json" && grep -q 'other.sh' "$T/inst/.codex/hooks.json" && ok "install is idempotent and keeps other hooks" || bad "install failed"
[[ -e "$T/inst/.codex/hooks.json.bak-ctx-relay" ]] && ok "original backed up" || bad "no backup"
( cd "$T/inst" && env CTX_RELAY_CODEX_HOOKS_JSON="$T/inst/.codex/hooks.json" "$ROOT/bin/ctx-relay-codex" uninstall >/dev/null 2>&1 )
! grep -q 'codex-hook.sh' "$T/inst/.codex/hooks.json" && grep -q 'other.sh' "$T/inst/.codex/hooks.json" && ok "uninstall removes only ctx-relay" || bad "uninstall"

echo
echo "passed=$pass failed=$fail"
rm -rf "$T"
exit $((fail>0))
