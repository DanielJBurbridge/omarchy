#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH" TEST_OVERLAY_LOG="$test_tmp/call"
unset XDG_CURRENT_DESKTOP GAMESCOPE_WAYLAND_DISPLAY
# Only the renderer/compositor boundaries are faked. Parsing, config selection
# and exact argv/environment propagation are the actual production command.
cat >"$test_tmp/bin/mangohud" <<'STUB'
#!/bin/bash
printf '%s\n' "$MANGOHUD_CONFIG" >"$TEST_OVERLAY_LOG"
exec "$@"
STUB
cat >"$test_tmp/bin/gamescope" <<'STUB'
#!/bin/bash
printf '%s\n' "${MANGOHUD-unset}" "$MANGOHUD_CONFIG" "$@" >"$TEST_OVERLAY_LOG"
STUB
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/mangoapp"
chmod +x "$test_tmp/bin/"*

# The shell source and argument intentionally contain a literal substitution.
# shellcheck disable=SC2016
"$ROOT/bin/omarchy-launch-gaming-overlay" --fps 40 -- /bin/bash -c '[[ $1 == "a b" && $2 == "\$(touch never)" ]]' game 'a b' '$(touch never)'
[[ $(<"$TEST_OVERLAY_LOG") == *fps_limit=40* ]] || fail "desktop cap reaches the game environment"
pass "desktop overlay preserves literal arguments and runs without session environment"
if "$ROOT/bin/omarchy-launch-gaming-overlay" -- /bin/bash -c 'exit 23'; then
  fail "overlay returns the game failure"
else
  [[ $? == 23 ]] || fail "overlay preserves the exact game exit status"
fi
pass "overlay returns the game exit status"

MANGOHUD=1 "$ROOT/bin/omarchy-launch-gaming-overlay" --preset detailed --fps 60 --gamescope -- game 'a b'
mapfile -t call <"$TEST_OVERLAY_LOG"
[[ ${call[0]} == unset && ${call[1]} == *fps_limit=0* && ${call[2]} == --mangoapp && ${call[3]} == -r && ${call[4]} == 60 && ${call[5]} == -- && ${call[6]} == game && ${call[7]} == 'a b' ]] ||
  fail "Gamescope owns overlay and cap, without game-layer injection" "$(<"$TEST_OVERLAY_LOG")"
pass "Gamescope uses mangoapp and caps the compositor rather than its overlay"

for option in '--fps 61' '--preset unknown' '--fps' ''; do
  : >"$TEST_OVERLAY_LOG"
  read -ra invalid <<<"$option"
  if "$ROOT/bin/omarchy-launch-gaming-overlay" "${invalid[@]}" >"$test_tmp/output" 2>&1; then
    fail "invalid overlay invocation fails: $option"
  fi
  [[ ! -s $TEST_OVERLAY_LOG ]] || fail "invalid options never launch a renderer"
done
if XDG_CURRENT_DESKTOP=gamescope "$ROOT/bin/omarchy-launch-gaming-overlay" -- /bin/true >"$test_tmp/output" 2>&1; then
  fail "direct injection into an existing Gamescope session is rejected"
fi
pass "invalid invocations and unsupported direct Gamescope injection never launch a game"
