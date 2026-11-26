#!/bin/bash
# Replacing handheld runtime or settings must deactivate both SDDM settings
# and retain the installer account for a later return to handheld packages.

set -uo pipefail

if (( EUID != 0 )); then
  exec unshare --user --map-root-user bash "$0"
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$here/base-test.sh"

script=$ROOT/packages/omarchy-gaming-session/omarchy-handheld-autologin-guard
hook=$ROOT/packages/omarchy-gaming-session/omarchy-handheld-autologin-guard.hook
pkgbuild=$ROOT/packages/omarchy-gaming-session/PKGBUILD
[[ -f $script ]] || fail "the gaming-session package is missing the autologin guard"
[[ -f $hook ]] || fail "the gaming-session package is missing the autologin guard hook"
grep -q 'Operation = Upgrade' "$hook" || fail "the hook does not run on upgrade"
grep -q 'Operation = Install' "$hook" || fail "the hook does not run on install"
grep -q 'When = PostTransaction' "$hook" || fail "the hook does not run after the transaction"
for package in omarchy omarchy-dev omarchy-settings omarchy-settings-dev; do
  grep -Fxq "Target = $package" "$hook" || fail "the hook does not target $package"
done
grep -q 'Exec = /usr/lib/omarchy-gaming-session/omarchy-handheld-autologin-guard' "$hook" ||
  fail "the hook does not run the guard"
if grep -q 'AbortOnFail' "$hook"; then
  fail "the hook can fail the transaction"
fi
grep -q 'usr/share/libalpm/hooks/omarchy-handheld-autologin-guard.hook' "$pkgbuild" ||
  fail "the package does not install the hook"
grep -q 'usr/lib/omarchy-gaming-session/omarchy-handheld-autologin-guard' "$pkgbuild" ||
  fail "the package does not install the guard"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/package"
cp "$script" "$ROOT/default/gaming/sddm-user.sh" "$work/package/"
script=$work/package/${script##*/}
root=$work/root
dropin=$root/etc/sddm.conf.d/zz-omarchy-handheld.conf
user=$root/etc/sddm.conf.d/omarchy-handheld-user.conf
sudoers=$root/etc/sudoers.d/omarchy-handheld-autologin
tpm=$root/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf
log=$work/logger.log

mkdir -p "$work/bin"
cat > "$work/bin/pacman" <<'EOF'
#!/bin/bash
if [[ -n ${FAKE_PACMAN_LOG:-} ]]; then
  printf '%s\n' "$*" >> "$FAKE_PACMAN_LOG"
fi
if [[ $1 == -Q && $2 == omarchy && -n ${FAKE_OMARCHY_VERSION:-} ]]; then
  printf 'omarchy %s\n' "$FAKE_OMARCHY_VERSION"
  exit 0
fi
if [[ $1 == -Q && $2 == omarchy-dev && -n ${FAKE_OMARCHY_DEV_VERSION:-} ]]; then
  printf 'omarchy-dev %s\n' "$FAKE_OMARCHY_DEV_VERSION"
  exit 0
fi
if [[ $1 == -Q && $2 == omarchy-settings && -n ${FAKE_OMARCHY_SETTINGS_VERSION:-} ]]; then
  printf 'omarchy-settings %s\n' "$FAKE_OMARCHY_SETTINGS_VERSION"
  exit 0
fi
if [[ $1 == -Q && $2 == omarchy-settings-dev && -n ${FAKE_OMARCHY_SETTINGS_DEV_VERSION:-} ]]; then
  printf 'omarchy-settings-dev %s\n' "$FAKE_OMARCHY_SETTINGS_DEV_VERSION"
  exit 0
fi
if [[ $1 == -Q && ${FAKE_STOCK_PROVIDERS:-} == "1" ]]; then
  case $2 in
    omarchy) printf 'omarchy-dev %s\n' "$FAKE_OMARCHY_DEV_VERSION" ;;
    omarchy-settings) printf 'omarchy-settings-dev %s\n' "$FAKE_OMARCHY_SETTINGS_DEV_VERSION" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
EOF
cat > "$work/bin/logger" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${OMARCHY_TEST_LOGGER_LOG:?}"
exit 0
EOF
chmod +x "$work/bin/pacman" "$work/bin/logger"

seed() {
  rm -rf "$root"
  mkdir -p "$root/etc/sddm.conf.d" "$root/etc/sudoers.d" "$root/etc/mkinitcpio.conf.d"
  printf '[Autologin]\nSession=omarchy-handheld.desktop\nRelogin=true\n' > "$dropin"
  printf '[Autologin]\nUser=daniel\n' > "$user"
  printf '%s\n' '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-handheld-autologin fail, /usr/bin/omarchy-handheld-autologin reset, /usr/bin/omarchy-handheld-autologin apply' > "$sudoers"
  printf '%s\n' 'HOOKS=(base systemd plymouth sd-encrypt)' > "$tpm"
  cp "$dropin" "$work/dropin.orig"
  cp "$user" "$work/user.orig"
  cp "$sudoers" "$work/sudoers.orig"
  cp "$tpm" "$work/tpm.orig"
  : > "$log"
}

read_status() {
  status_rc=0
  status_word=$(FAKE_OMARCHY_DEV_VERSION=${1:-} \
    FAKE_OMARCHY_SETTINGS_DEV_VERSION=${2:-} \
    OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
    OMARCHY_TEST_LOGGER_LOG=$log \
    PATH="$work/bin:$PATH" \
    "$script" --status) || status_rc=$?
}

run_guard() {
  local status=0
  FAKE_OMARCHY_DEV_VERSION=${1:-} \
    FAKE_OMARCHY_SETTINGS_DEV_VERSION=${2:-} \
    OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
    OMARCHY_TEST_LOGGER_LOG=$log \
    PATH="$work/bin:$PATH" \
    "$script" || status=$?
  (( status == 0 )) || fail "the guard exits 0 for $1 ${2:-}" "$status"
}

unrelated_config_unchanged() {
  cmp -s "$sudoers" "$work/sudoers.orig" || fail "the sudoers grant changed for $1"
  cmp -s "$tpm" "$work/tpm.orig" || fail "the TPM config changed for $1"
}

expect_inactive_owner() {
  grep -Fxq '[OmarchyHandheld]' "$user" && grep -Fxq 'User=daniel' "$user" ||
    fail "the recorded owner is missing for $1"
  if grep -Fxq '[Autologin]' "$user"; then
    fail "the installer User= can still autologin into the last desktop for $1"
  fi
}

expect_disabled() {
  seed
  read_status "$1" "${2:-}"
  (( status_rc == 0 )) || fail "--status exits 0 for $1" "$status_rc"
  [[ $status_word == drop ]] || fail "--status is drop for $1" "$status_word"
  cmp -s "$dropin" "$work/dropin.orig" || fail "--status removes autologin for $1"
  cmp -s "$user" "$work/user.orig" || fail "--status changes the owner file for $1"
  run_guard "$1" "${2:-}"
  expect_inactive_owner "$1"
  unrelated_config_unchanged "$1"
  [[ ! -e $dropin ]] || fail "autologin stays enabled for $1" "$(cat "$dropin")"
  grep -q 'omarchy-handheld-autologin apply' "$log" ||
    fail "the journal does not say how to turn autologin back on for $1" "$(cat "$log")"
  run_guard "$1" "${2:-}"
  expect_inactive_owner "$1"
  [[ ! -e $dropin ]] || fail "a second run restores autologin for $1"
  pass "autologin is disabled for ${1:-<none>}${2:+ / $2}"
}

expect_kept() {
  seed
  read_status "$1" "${2:-}"
  (( status_rc == 0 )) || fail "--status exits 0 for $1" "$status_rc"
  [[ $status_word == keep ]] || fail "--status is keep for $1" "$status_word"
  cmp -s "$dropin" "$work/dropin.orig" || fail "--status changes autologin for $1"
  run_guard "$1" "${2:-}"
  cmp -s "$user" "$work/user.orig" || fail "User= changed for $1"
  unrelated_config_unchanged "$1"
  cmp -s "$dropin" "$work/dropin.orig" || fail "autologin changed for $1" "$(cat "$dropin" 2>/dev/null)"
  if grep -q 'removed' "$log"; then
    fail "a kept build removes the drop-in for $1" "$(cat "$log")"
  fi
  pass "autologin is unchanged for ${1:-<none>}${2:+ / $2}"
}

expect_disabled 4.0.0.r8045.gd54cde7
expect_disabled 4.0.0.r8045.gd54cde7-1
expect_disabled 4.0.1.r1.g0000000
expect_disabled 4.0.1.r1.g0000000-1
expect_kept 4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12
expect_kept 4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1
expect_kept 4.0.0.202611170435.r8085.handheld.d0d40b90
expect_kept 4.0.0.202611170435.r8085.handheld.d0d40b90-1
expect_kept 4.0.0.202611170222.r8072.handheld.e742281c
expect_kept 4.0.0.202611170222.r8072.handheld.e742281c-1
expect_kept dev.202611170222.e742281c
expect_kept dev.202611170222.e742281c-1

FAKE_OMARCHY_VERSION=4.0.1-1 expect_disabled "" dev.202611170222.e742281c-1
FAKE_OMARCHY_SETTINGS_VERSION=4.0.1-1 expect_disabled dev.202611170222.e742281c-1
FAKE_OMARCHY_VERSION=4.0.0.202611170222.r8072.handheld.e742281c-1 \
  FAKE_OMARCHY_SETTINGS_VERSION=4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1 \
  expect_kept ""

# After a handheld upgrade, stock-name queries resolve to the installed providers.
seed
provider_version=4.0.0.20261126101543.r8947.handheld.df69115b-1
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-$provider_version" \
  "$root/var/lib/pacman/local/omarchy-settings-dev-$provider_version"
: > "$root/var/lib/pacman/db.lck"
read_status "" ""
[[ $status_word == keep ]] || fail "--status is keep for locked handheld providers" "$status_word"
run_guard "" ""
cmp -s "$user" "$work/user.orig" && cmp -s "$dropin" "$work/dropin.orig" ||
  fail "the locked guard changes active autologin for handheld providers"
pass "a held pacman lock keeps the active owner and session for handheld providers"

rm -- "$root/var/lib/pacman/db.lck"
FAKE_STOCK_PROVIDERS=1 read_status "$provider_version" "$provider_version"
[[ $status_word == keep ]] || fail "--status is keep for unlocked handheld providers" "$status_word"
FAKE_STOCK_PROVIDERS=1 run_guard "$provider_version" "$provider_version"
cmp -s "$user" "$work/user.orig" && cmp -s "$dropin" "$work/dropin.orig" ||
  fail "the unlocked guard changes active autologin for handheld providers"
pass "unlocked stock-name queries keep the active owner and session for handheld providers"

# The hook runs while pacman holds db.lck. A nested pacman -Q would wait on
# that lock, so the guard reads the local database and does not call pacman.
seed
mkdir -p "$root/var/lib/pacman/local/omarchy-4.0.1-1" \
  "$root/var/lib/pacman/local/omarchy-settings-4.0.1-1"
: > "$root/var/lib/pacman/db.lck"
: > "$work/pacman.log"
FAKE_PACMAN_LOG=$work/pacman.log \
  FAKE_OMARCHY_DEV_VERSION=dev.202611170222.e742281c \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
[[ ! -s $work/pacman.log ]] || fail "the guard calls pacman while db.lck is held" "$(cat "$work/pacman.log")"
[[ ! -e $dropin ]] || fail "a locked database leaves upstream autologin enabled"
expect_inactive_owner "the locked stock pair"
legacy_owners=("${user%/*}"/.omarchy-handheld-user.conf.omarchy-disabled.*)
legacy_sessions=("${dropin%/*}"/.zz-omarchy-handheld.conf.omarchy-disabled.*)
cmp -s "${legacy_owners[0]}" "$work/user.orig" && cmp -s "${legacy_sessions[0]}" "$work/dropin.orig" ||
  fail "rollback does not preserve the legacy SDDM fragments"
pass "a held pacman lock disables autologin for stock runtime and settings"

seed
rm -f -- "$dropin"
FAKE_OMARCHY_VERSION=4.0.1-1 run_guard ""
expect_inactive_owner "an earlier rollback that removed only the session"
pass "a legacy owner is deactivated even when the session was already removed"

seed
printf '[Autologin]\nUser=operator\nSession=omarchy.desktop\n' > "$user"
cp "$user" "$work/operator.conf"
ln -s "$work/operator.conf" "$root/etc/sddm.conf.d/autologin.conf"
rm -f -- "$dropin"
ln -s "$work/dropin.orig" "$dropin"
FAKE_OMARCHY_SETTINGS_VERSION=4.0.1-1 run_guard ""
cmp -s "$user" "$work/operator.conf" && [[ -L $dropin && -L $root/etc/sddm.conf.d/autologin.conf ]] ||
  fail "stock rollback changes operator SDDM configuration"
pass "stock rollback preserves edited files and symlinks"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.0.202611170222.r8072.handheld.e742281c-1"
: > "$root/var/lib/pacman/db.lck"
FAKE_OMARCHY_DEV_VERSION=4.0.1.r1.g0000000 \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
cmp -s "$dropin" "$work/dropin.orig" || fail "a locked handheld database disables autologin"
pass "a held pacman lock keeps a .handheld build"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1"
: > "$root/var/lib/pacman/db.lck"
FAKE_OMARCHY_DEV_VERSION=4.0.1.r1.g0000000 \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
cmp -s "$dropin" "$work/dropin.orig" || fail "a locked allypreview database disables autologin"
pass "a held pacman lock keeps an .allypreview build"

# A directory whose name merely starts with omarchy-dev- is another package.
# It must not count as a second omarchy-dev, and it must not be omarchy-dev
# on its own.
seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.0.r8045.gd54cde7-1"
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-utils-1.2.3-1"
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-debug-1.0-1"
: > "$root/var/lib/pacman/db.lck"
: > "$work/pacman.log"
FAKE_PACMAN_LOG=$work/pacman.log \
  FAKE_OMARCHY_DEV_VERSION=dev.202611170222.e742281c \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
[[ ! -s $work/pacman.log ]] || fail "a neighbouring package makes the guard call pacman" "$(cat "$work/pacman.log")"
[[ ! -e $dropin ]] || fail "omarchy-dev-utils or omarchy-dev-debug keeps upstream autologin"
pass "a neighbouring omarchy-dev-* package is not omarchy-dev"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-utils-1.2.3-1"
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-debug-1.0-1"
: > "$root/var/lib/pacman/db.lck"
FAKE_OMARCHY_DEV_VERSION=4.0.1.r1.g0000000 \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
cmp -s "$dropin" "$work/dropin.orig" || fail "a database without omarchy-dev disables autologin"
pass "omarchy-dev-utils and omarchy-dev-debug are not omarchy-dev"

# The db.lck read is the same keep list as pacman -Q. --status, not only the
# file, has to say keep for dev.* and .allypreview.
seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-dev.202611170222.e742281c-1"
: > "$root/var/lib/pacman/db.lck"
read_status 4.0.1.r1.g0000000
(( status_rc == 0 )) || fail "--status exits 0 for a locked dev database" "$status_rc"
[[ $status_word == keep ]] || fail "--status is keep for a locked dev database" "$status_word"
cmp -s "$dropin" "$work/dropin.orig" || fail "--status removes autologin for a locked dev database"
pass "a held pacman lock keeps a dev.* build"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1"
: > "$root/var/lib/pacman/db.lck"
read_status 4.0.1.r1.g0000000
[[ $status_word == keep ]] || fail "--status is keep for a locked allypreview database" "$status_word"
pass "a held pacman lock reports keep for an .allypreview build"

# Replacing omarchy-settings-dev alone is the same decision as omarchy-dev.
expect_disabled "" 4.0.1.r1.g0000000
expect_kept "" 4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1
expect_kept "" dev.202611170222.e742281c-1

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-settings-dev-4.0.1.r1.g0000000-1"
: > "$root/var/lib/pacman/db.lck"
: > "$work/pacman.log"
FAKE_PACMAN_LOG=$work/pacman.log \
  FAKE_OMARCHY_DEV_VERSION=dev.202611170222.e742281c \
  FAKE_OMARCHY_SETTINGS_DEV_VERSION=dev.202611170222.e742281c \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
[[ ! -s $work/pacman.log ]] || fail "the guard calls pacman while db.lck is held for settings-dev" "$(cat "$work/pacman.log")"
[[ ! -e $dropin ]] || fail "a locked upstream settings-dev leaves autologin enabled"
expect_inactive_owner "locked stock settings-dev"
pass "a held pacman lock disables autologin for settings-dev alone"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.0.202611170222.r8072.handheld.e742281c-1"
mkdir -p "$root/var/lib/pacman/local/omarchy-settings-dev-4.0.1.r1.g0000000-1"
: > "$root/var/lib/pacman/db.lck"
FAKE_OMARCHY_DEV_VERSION=4.0.0.202611170222.r8072.handheld.e742281c \
  FAKE_OMARCHY_SETTINGS_DEV_VERSION=4.0.0.202611170222.r8072.handheld.e742281c \
  OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
  OMARCHY_TEST_LOGGER_LOG=$log \
  PATH="$work/bin:$PATH" \
  "$script"
[[ ! -e $dropin ]] || fail "a handheld omarchy-dev keeps autologin when settings-dev is upstream"
pass "a handheld omarchy-dev does not keep autologin for an upstream settings-dev"

seed
mkdir -p "$root/var/lib/pacman/local/omarchy-settings-dev-dev.202611170222.e742281c-1"
: > "$root/var/lib/pacman/db.lck"
read_status "" ""
[[ $status_word == keep ]] || fail "--status is keep for a locked settings-dev dev database" "$status_word"
pass "a held pacman lock keeps a dev.* settings-dev build"
