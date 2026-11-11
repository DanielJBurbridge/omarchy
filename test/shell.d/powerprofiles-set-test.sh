#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/state"

cat >"$tmp_dir/bin/powerprofilesctl" <<'EOF'
#!/bin/bash

if [[ $1 == "list" ]]; then
  printf '  power-saver:\n* balanced:\n  performance:\n'
elif [[ $1 == "set" ]]; then
  [[ ${POWERPROFILES_SET_FAIL:-0} == "0" ]] || exit 1
  printf '%s\n' "$2" >>"$POWERPROFILES_LOG"
fi
EOF
chmod +x "$tmp_dir/bin/powerprofilesctl"

cat >"$tmp_dir/bin/busctl" <<'EOF'
#!/bin/bash

if [[ ${ON_BATTERY:-0} == "1" ]]; then
  echo "b true"
else
  echo "b false"
fi
EOF
chmod +x "$tmp_dir/bin/busctl"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export POWERPROFILES_LOG="$tmp_dir/calls"
export OMARCHY_POWERPROFILES_STATE_DIR="$tmp_dir/state"

"$ROOT/bin/omarchy-powerprofiles-set" ac balanced
[[ $(<"$tmp_dir/state/ac") == "balanced" ]] || fail "power profile stores AC preference"
[[ $(tail -n 1 "$tmp_dir/calls") == "balanced" ]] || fail "power profile applies selected AC preference"
pass "power profile stores and applies AC preference"

"$ROOT/bin/omarchy-powerprofiles-set" ac
[[ $(tail -n 1 "$tmp_dir/calls") == "balanced" ]] || fail "power profile restores AC preference"
pass "power profile restores AC preference"

if POWERPROFILES_SET_FAIL=1 "$ROOT/bin/omarchy-powerprofiles-set" ac performance; then
  fail "power profile reports a failed selection"
fi
[[ $(<"$tmp_dir/state/ac") == "balanced" ]] || fail "power profile preserves preference after failed selection"
pass "power profile persists only successful selections"

"$ROOT/bin/omarchy-powerprofiles-set" battery performance
[[ $(<"$tmp_dir/state/battery") == "performance" ]] || fail "power profile stores battery preference"
pass "power profile stores battery preference separately"

"$ROOT/bin/omarchy-powerprofiles-set" ac
[[ $(tail -n 1 "$tmp_dir/calls") == "balanced" ]] || fail "battery preference does not replace AC preference"
pass "power profile keeps AC and battery preferences separate"

ON_BATTERY=1 "$ROOT/bin/omarchy-powerprofiles-set"
[[ $(tail -n 1 "$tmp_dir/calls") == "performance" ]] || fail "autodetect restores battery preference"
pass "power profile autodetect restores battery preference"

rm "$tmp_dir/state/ac"
ON_BATTERY=0 "$ROOT/bin/omarchy-powerprofiles-set"
[[ $(tail -n 1 "$tmp_dir/calls") == "performance" ]] || fail "power profile uses performance as AC default"
pass "power profile retains performance as AC default"

"$ROOT/bin/omarchy-powerprofiles-set" ac power-saver
"$ROOT/bin/omarchy-powerprofiles-init"
[[ $(tail -n 1 "$tmp_dir/calls") == "power-saver" ]] || fail "init restores the autodetected preference"
pass "power profile init restores the autodetected preference"

# Exercise the real compatibility router with handheld ownership selected.
mkdir -p "$tmp_dir/handheld/omarchy/ally-power"
touch "$tmp_dir/handheld/omarchy/ally-power/enabled"
export XDG_STATE_HOME="$tmp_dir/handheld"
cat >"$tmp_dir/bin/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$tmp_dir/bin/omarchy-power-ally" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$POWERPROFILES_LOG"
EOF
chmod +x "$tmp_dir/bin/omarchy-hw-rog-ally" "$tmp_dir/bin/omarchy-power-ally"
ON_BATTERY=0 "$ROOT/bin/omarchy-powerprofiles-set" battery power-saver
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "set --source battery profile quiet" ]] || fail "handheld router preserves battery target while plugged in"
pass "handheld router preserves battery target while plugged in"
ON_BATTERY=1 "$ROOT/bin/omarchy-powerprofiles-set" ac performance
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "set --source ac profile performance" ]] || fail "handheld router preserves AC target while unplugged"
pass "handheld router preserves AC target while unplugged"
before=$(<"$POWERPROFILES_LOG")
if "$ROOT/bin/omarchy-powerprofiles-set" invalid balanced; then fail "handheld router rejects an invalid action"; fi
[[ $(<"$POWERPROFILES_LOG") == "$before" ]] || fail "invalid action reached handheld backend"
pass "invalid handheld action never reaches backend"
"$ROOT/bin/omarchy-powerprofiles-set" battery
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "restore --source battery" ]] || fail "handheld router restores the requested source"
pass "handheld router restores the requested source"
