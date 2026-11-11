#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Reproduce a host with wvkbd installed, even on a machine without it. The
# missing-dependency test must never discover this caller-side executable.
mkdir -p "$test_dir/host-bin"
printf '#!/bin/bash\nexit 99\n' >"$test_dir/host-bin/wvkbd-mobintl"
chmod +x "$test_dir/host-bin/wvkbd-mobintl"
PATH="$test_dir/host-bin:$PATH" python3 "$ROOT/test/helpers/desktop-keyboard-process.py" "$ROOT/bin/omarchy-toggle-desktop-keyboard"
