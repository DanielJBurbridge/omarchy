#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
called=$work/called

cat > "$work/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
[[ ${LOCK_HW:-laptop} == ally ]]
EOF
cat > "$work/sudo" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$called"
exit 1
EOF
chmod +x "$work/omarchy-hw-rog-ally" "$work/sudo"

run_migration() {
  : > "$called"
  PATH="$work:$PATH" OMARCHY_PATH="$ROOT" LOCK_HW=$1 bash "$ROOT/migrations/1794466185.sh" >"$work/out" 2>&1
}

run_migration laptop
[[ ! -s $called ]] || fail "a laptop migration asks for sudo" "$(cat "$called")"
pass "a laptop migration does not ask for sudo or write the K07 marker"

run_migration ally
[[ ! -s $called ]] || fail "a dormant Ally migration asks for sudo" "$(cat "$called")"
pass "an Ally migration stays dormant and does not write the K07 marker"
