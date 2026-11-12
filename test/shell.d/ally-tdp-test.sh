#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command dbus-daemon

# python-dbus and python-gobject are required to exercise the session-bus shim.
if ! python3 -c 'import dbus, gi'; then
  echo "ally-tdp tests need python-dbus and python-gobject" >&2
  exit 1
fi

OMARCHY_TEST_ROOT="$ROOT" python3 -B "$ROOT/test/helpers/ally-tdp.py"
