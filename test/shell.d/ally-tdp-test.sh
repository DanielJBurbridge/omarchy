#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command dbus-daemon

OMARCHY_TEST_ROOT="$ROOT" python3 -B "$ROOT/test/helpers/ally-tdp.py"
