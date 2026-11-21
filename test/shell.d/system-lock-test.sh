#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in omarchy-shell hyprctl pkill omarchy-toggle-desktop-keyboard; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done

# A screensaver that does not exit within its second.
cat >"$mock_bin/timeout" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 124
SH

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/omarchy-system-lock"
mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")

[[ ${shutdown[0]} == "pkill -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock stops the native screensaver" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock waits for the native screensaver to clean up" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -KILL -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock force-stops a stuck native screensaver" "calls: ${shutdown[*]}"
rg -A1 '^pkill -KILL ' "$call_log" | rg -q 'invisible = false' ||
  fail "system lock shows the cursor a killed screensaver left hidden" "$(<"$call_log")"
stop_line=$(rg -n 'omarchy-toggle-desktop-keyboard stop' "$call_log" | head -n 1 | cut -d: -f1)
lock_line=$(rg -n '^omarchy-shell lock lock$' "$call_log" | head -n 1 | cut -d: -f1)
[[ -n $stop_line && -n $lock_line && $stop_line -lt $lock_line ]] ||
  fail "system lock hides the desktop keyboard before the lock" "$(<"$call_log")"
pass "system lock gives the screensaver a second to restore the cursor before killing it, then restores it itself"
pass "system lock hides the desktop keyboard before locking"

# A trusted owner must be compositor-secure before the proactive lock caller
# can proceed. Test the caller's failure propagation; sleep-lock-test exercises
# the real readiness/secure state checks separately.
mkdir -p "$tmpdir/root/bin"
cat >"$tmpdir/root/bin/omarchy-lock-host" <<'SH'
#!/bin/bash
echo host
SH
cat >"$tmpdir/root/bin/omarchy-system-sleep-lock" <<'SH'
#!/bin/bash
printf 'secure-check\n' >>"$CALL_LOG"
exit "$SECURE_RESULT"
SH
chmod +x "$tmpdir/root/bin/"*
: >"$call_log"
if PATH="$mock_bin:$PATH" CALL_LOG="$call_log" SECURE_RESULT=1 HYPRLAND_INSTANCE_SIGNATURE=fixture OMARCHY_PATH="$tmpdir/root" "$ROOT/bin/omarchy-system-lock"; then
  fail "unready trusted lock must fail the proactive caller"
fi
[[ $(<"$call_log") == $'omarchy-toggle-desktop-keyboard stop\nsecure-check' ]] || fail "failed secure acquisition must stop proactive lock completion" "$(<"$call_log")"
PATH="$mock_bin:$PATH" CALL_LOG="$call_log" SECURE_RESULT=0 HYPRLAND_INSTANCE_SIGNATURE=fixture OMARCHY_PATH="$tmpdir/root" "$ROOT/bin/omarchy-system-lock"
rg -q '^hyprctl ' "$call_log" || fail "secure trusted lock can complete normal display handling"
pass "trusted lock acquisition failure propagates before proactive lock completion"
