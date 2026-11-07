#!/bin/bash

# The Apple installer planner raises PlanningError when the APFS capacity
# ceiling and the partition map disagree. omacom/omarchy#17820 hit that on
# an M1 after a shrink updated the ceiling and left the map behind.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

python3 "$ROOT/test/shell.d/fixtures/apple-resize-metrics/test_resize_metrics.py"
pass "apple installer planner re-queries inconsistent macOS resize metrics"
