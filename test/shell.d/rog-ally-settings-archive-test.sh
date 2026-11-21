#!/bin/bash

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"
require_command bsdtar

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
template=usr/share/omarchy/default/systemd/user/omarchy-lock-host.service
unit=usr/lib/systemd/user/omarchy-lock-host.service
verify="$ROOT/packaging/rog-ally-release/verify-settings-package"

package_fixture() {
  tar --owner=0 --group=0 --numeric-owner -C "$work/stage" -cf "$work/settings.tar" usr
}

reject_fixture() {
  local expected=$1 output
  package_fixture
  if output=$("$verify" "$work/settings.tar" 2>&1); then
    fail "$expected"
  fi
  [[ $output == *"$expected"* ]] || fail "the package check reports $expected" "$output"
}

install -Dm644 "$ROOT/default/systemd/user/omarchy-lock-host.service" "$work/stage/$template"
reject_fixture "$unit"
pass "a settings package with only the template is rejected"

install -Dm644 "$work/stage/$template" "$work/stage/$unit"
package_fixture
"$verify" "$work/settings.tar"
pass "a settings package with both identical regular units is accepted"

chmod 0600 "$work/stage/$unit"
reject_fixture "$unit"
pass "a settings package with the wrong service mode is rejected"

chmod 0644 "$work/stage/$unit"
printf '# altered copy\n' >> "$work/stage/$unit"
reject_fixture "differs from its template"
pass "a settings package with mismatched unit bytes is rejected"
