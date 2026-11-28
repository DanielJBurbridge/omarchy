#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
OMARCHY_TEST_ROOT="$ROOT" python3 "$ROOT/test/helpers/gaming-setup-routing.py"
OMARCHY_TEST_ROOT="$ROOT" python3 "$ROOT/test/helpers/gaming-sunshine.py"
OMARCHY_TEST_ROOT="$ROOT" dbus-run-session -- python3 "$ROOT/test/helpers/gaming-session.py"
if grep -q 'ally-power' "$ROOT/bin/omarchy-session-start"; then
  fail "session-start still references ally-power"
fi
pass "session-start has no ally-power references"
