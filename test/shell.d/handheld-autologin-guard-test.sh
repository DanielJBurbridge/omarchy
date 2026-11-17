#!/bin/bash
# An upstream omarchy-dev, once the base moves past the handheld pkgver,
# must drop the gaming autologin drop-in. A .handheld or dev.* build must
# leave it, and User=, the sudoers grant and the TPM config stay either way.

set -uo pipefail

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
grep -q 'Target = omarchy-dev' "$hook" || fail "the hook does not target omarchy-dev"
grep -q 'Target = omarchy-settings-dev' "$hook" || fail "the hook does not target omarchy-settings-dev"
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
if [[ $1 == -Q && $2 == omarchy-dev && -n ${FAKE_OMARCHY_DEV_VERSION:-} ]]; then
  printf 'omarchy-dev %s\n' "$FAKE_OMARCHY_DEV_VERSION"
  exit 0
fi
exit 1
EOF
cat > "$work/bin/logger" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${OMARCHY_TEST_LOGGER_LOG:?}"
exit 0
EOF
chmod +x "$work/bin/pacman" "$work/bin/logger" "$script"

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

run_guard() {
  local status=0
  FAKE_OMARCHY_DEV_VERSION=$1 \
    OMARCHY_HANDHELD_AUTOLOGIN_ROOT=$root \
    OMARCHY_TEST_LOGGER_LOG=$log \
    PATH="$work/bin:$PATH" \
    "$script" || status=$?
  (( status == 0 )) || fail "the guard exits 0 for $1" "$status"
}

secrets_unchanged() {
  cmp -s "$user" "$work/user.orig" || fail "User= changed for $1" "$(cat "$user")"
  cmp -s "$sudoers" "$work/sudoers.orig" || fail "the sudoers grant changed for $1"
  cmp -s "$tpm" "$work/tpm.orig" || fail "the TPM config changed for $1"
}

expect_disabled() {
  seed
  run_guard "$1"
  secrets_unchanged "$1"
  [[ ! -e $dropin ]] || fail "autologin stays enabled for $1" "$(cat "$dropin")"
  grep -q 'omarchy-handheld-autologin apply' "$log" ||
    fail "the journal does not say how to turn autologin back on for $1" "$(cat "$log")"
  run_guard "$1"
  secrets_unchanged "$1"
  [[ ! -e $dropin ]] || fail "a second run restores autologin for $1"
  pass "autologin is disabled for $1"
}

expect_kept() {
  seed
  run_guard "$1"
  secrets_unchanged "$1"
  cmp -s "$dropin" "$work/dropin.orig" || fail "autologin changed for $1" "$(cat "$dropin" 2>/dev/null)"
  if grep -q 'removed' "$log"; then
    fail "a kept build removes the drop-in for $1" "$(cat "$log")"
  fi
  pass "autologin is unchanged for $1"
}

expect_disabled 4.0.1.r1.g0000000
expect_disabled 4.0.1.r1.g0000000-1
expect_kept 4.0.0.202611170222.r8072.handheld.e742281c
expect_kept 4.0.0.202611170222.r8072.handheld.e742281c-1
expect_kept dev.202611170222.e742281c
expect_kept dev.202611170222.e742281c-1

# The hook runs while pacman holds db.lck. A nested pacman -Q would wait on
# that lock, so the guard reads the local database and does not call pacman.
seed
mkdir -p "$root/var/lib/pacman/local/omarchy-dev-4.0.1.r1.g0000000-1"
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
cmp -s "$user" "$work/user.orig" || fail "User= changed while the database was locked"
pass "a held pacman lock still disables upstream autologin"

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
