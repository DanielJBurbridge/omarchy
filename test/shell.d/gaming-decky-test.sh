#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" PATH="$test_tmp/bin:$ROOT/bin:$PATH" TEST_DECKY_LOG="$test_tmp/calls"
mkdir -p "$test_tmp/bin" "$HOME/.steam/steam"
# Replace only the package's fixed home boundary, as platform_root_copy does for
# fixed platform roots; the lifecycle, guards and real marker files stay intact.
# shellcheck disable=SC2016
sed 's|"/home/$user"|"$HOME"|' "$ROOT/bin/omarchy-setup-gaming-decky" >"$test_tmp/setup"
cat >"$test_tmp/bin/getent" <<'STUB'
#!/bin/bash
printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$HOME"
STUB
cat >"$test_tmp/bin/pacman" <<'STUB'
#!/bin/bash
echo 'decky-loader 3.3.1-1'
STUB
cat >"$test_tmp/bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_DECKY_LOG"
case "$*" in
  *LoadState*) echo "${TEST_DECKY_LEGACY:-not-found}" ;;
  *Environment*) echo "${TEST_DECKY_ENV:-KEEP_SYSTEMD_SERVICE=1 SERVER_HOST=127.0.0.1}" ;;
  *ProtectSystem*) echo full ;;
  *KillMode*) echo control-group ;;
  is-active*) exit 1 ;;
  enable*) exit "${TEST_DECKY_ENABLE_STATUS:-0}" ;;
esac
STUB
cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/omarchy-pkg-present"
chmod +x "$test_tmp/bin/"*

if bash "$test_tmp/setup" enable >"$test_tmp/output" 2>&1; then fail "Decky needs explicit root plugin opt-in"; fi
[[ ! -f $TEST_DECKY_LOG ]] || fail "missing opt-in changes nothing"
for guard in legacy safeguards plugins; do
  : >"$TEST_DECKY_LOG"
  if [[ $guard == legacy ]]; then
    export TEST_DECKY_LEGACY=loaded
  elif [[ $guard == safeguards ]]; then
    unset TEST_DECKY_LEGACY
    export TEST_DECKY_ENV=unprotected
  else
    unset TEST_DECKY_ENV
    mkdir -p "$HOME/.local/var/opt/decky-loader/plugins/unreviewed"
  fi
  if bash "$test_tmp/setup" enable --allow-root-plugins >"$test_tmp/output" 2>&1; then fail "Decky rejects $guard"; fi
  ! grep -q '^enable' "$TEST_DECKY_LOG" || fail "$guard refusal starts no service"
  [[ ! -e $HOME/.steam/steam/.cef-enable-remote-debugging ]] || fail "$guard refusal creates no debug marker"
done
unset TEST_DECKY_ENV
rmdir "$HOME/.local/var/opt/decky-loader/plugins/unreviewed"
pass "Decky activation rejects missing consent, legacy installs, overridden safeguards and unreviewed existing plugins"

marker="$HOME/.steam/steam/.cef-enable-remote-debugging"
bash "$test_tmp/setup" enable --allow-root-plugins >"$test_tmp/output" 2>&1
[[ -f $marker ]] || fail "activation enables Steam debugging"
bash "$test_tmp/setup" disable >"$test_tmp/output" 2>&1
[[ ! -e $marker ]] || fail "disable cleans up its owned debug marker"
touch "$marker"
bash "$test_tmp/setup" enable --allow-root-plugins >"$test_tmp/output" 2>&1
bash "$test_tmp/setup" disable >"$test_tmp/output" 2>&1
[[ -f $marker ]] || fail "disable preserves a pre-existing debug marker"
rm "$marker"
bash "$test_tmp/setup" enable --allow-root-plugins >"$test_tmp/output" 2>&1
: >"$test_tmp/replacement-marker"
mv "$test_tmp/replacement-marker" "$marker"
bash "$test_tmp/setup" disable >"$test_tmp/output" 2>&1
[[ -f $marker ]] || fail "disable preserves a debug marker replaced by another owner"
[[ ! -e $HOME/.local/state/omarchy/decky/debug-marker ]] || fail "disable retires stale marker ownership"
pass "Decky rollback removes only the marker this activation created"

rm "$marker"
if TEST_DECKY_ENABLE_STATUS=23 bash "$test_tmp/setup" enable --allow-root-plugins >"$test_tmp/output" 2>&1; then
  fail "Decky propagates service start failure"
else
  [[ $? == 23 ]] || fail "Decky preserves the service failure code"
fi
[[ ! -e $marker ]] || fail "failed enable rolls back the owned marker"
pass "failed activation disables the service and rolls back its Steam change"
