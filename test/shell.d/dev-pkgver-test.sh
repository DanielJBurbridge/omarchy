#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/bin/omarchy-dev-pkg-test"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

repo="$test_tmp/checkout"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "pkgver@example.com"
git -C "$repo" config user.name "pkgver"
git -C "$repo" config commit.gpgsign false
printf '4.0.0.alpha\n' >"$repo/version"
git -C "$repo" add version
GIT_AUTHOR_DATE='2026-11-17T02:22:00Z' GIT_COMMITTER_DATE='2026-11-17T02:22:00Z' \
  git -C "$repo" commit -q -m 'early'
early=$(handheld_pkgver_for_checkout "$repo")

printf 'later\n' >"$repo/note"
git -C "$repo" add note
GIT_AUTHOR_DATE='2026-11-17T12:00:00Z' GIT_COMMITTER_DATE='2026-11-17T12:00:00Z' \
  git -C "$repo" commit -q -m 'later'
later=$(handheld_pkgver_for_checkout "$repo")

[[ $early == 4.0.0.202611170222.r1.handheld.* ]] ||
  fail "handheld pkgver uses the version base, the commit stamp, and the revision" "$early"
pass "handheld pkgver uses the version base, the commit stamp, and the revision"

[[ $later == 4.0.0.202611171200.r2.handheld.* ]] ||
  fail "a later commit gets a later stamp" "$later"
pass "a later commit gets a later stamp"

pkgbuilds="$test_tmp/pkgbuilds"
pkg_test_home="$test_tmp/home"
pkg_test_bin="$test_tmp/bin"
pkg_test_calls="$test_tmp/calls"
pkg_test_output="$test_tmp/output"
mkdir -p "$pkg_test_bin" "$pkg_test_home/Work/omarchy" "$test_tmp/build space"
ln -s "$repo" "$pkg_test_home/Work/omarchy/omarchy-installer"

for pkg in omarchy-settings-dev omarchy-dev; do
  mkdir -p "$pkgbuilds/$pkg"
  printf 'pkgname=%s\npkgver=0\n' "$pkg" >"$pkgbuilds/$pkg/PKGBUILD"
  touch "$pkgbuilds/$pkg/$pkg-$later-1-any.pkg.tar.zst"
done

cat >"$pkg_test_bin/makepkg" <<'SH'
#!/bin/bash
set -eu
source ./PKGBUILD
[[ -d $OMARCHY_SRC ]]
output_dir=${PKGDEST:-$PWD}
archive="$output_dir/$pkgname-$pkgver-1-any.pkg.tar.zst"
debug_archive="$output_dir/$pkgname-debug-$pkgver-1-any.pkg.tar.zst"
if [[ $1 == "--packagelist" ]]; then
  printf '%s\n' "$archive" "$debug_archive"
  exit 0
fi

printf 'build %s %s\n' "$pkgname" "$*" >>"$PKG_TEST_CALLS"
if [[ $pkgname == "omarchy-dev" ]]; then
  case "$PKG_TEST_SCENARIO" in
    failed) exit 31 ;;
    skipped) exit 13 ;;
    missing) exit 0 ;;
  esac
fi
touch "$archive" "$archive.sig" "$debug_archive"
SH

cat >"$pkg_test_bin/sudo" <<'SH'
#!/bin/bash
set -eu
[[ $1 == "pacman" && $2 == "-U" && $3 == "--noconfirm" && $4 == "--overwrite=*" ]]
shift 4
printf 'install' >>"$PKG_TEST_CALLS"
for archive; do
  [[ -f $archive ]]
  printf ' %s' "${archive##*/}" >>"$PKG_TEST_CALLS"
done
printf '\n' >>"$PKG_TEST_CALLS"
SH
chmod +x "$pkg_test_bin/makepkg" "$pkg_test_bin/sudo"

run_pkg_test() {
  local scenario=$1
  shift
  : >"$pkg_test_calls"
  HOME="$pkg_test_home" TMPDIR="$test_tmp/build space" PKGDEST="$pkgbuilds/omarchy-dev" \
    OMARCHY_PKGBUILDS_DIR="$pkgbuilds" PATH="$pkg_test_bin:$PATH" \
    PKG_TEST_CALLS="$pkg_test_calls" PKG_TEST_SCENARIO="$scenario" \
    "$ROOT/bin/omarchy-dev-pkg-test" "$@" >"$pkg_test_output" 2>&1
}

expect_incomplete_build() {
  local scenario=$1 expected_status=$2 diagnostic=$3 status=0 calls
  shift 3
  run_pkg_test "$scenario" "$@" || status=$?
  calls=$(<"$pkg_test_calls")
  [[ $calls == *"build omarchy-dev "* && $calls != *install* ]] ||
    fail "a $scenario runtime build leaves both packages uninstalled" "$calls"
  [[ $status == "$expected_status" && $(<"$pkg_test_output") == *"$diagnostic"* ]] ||
    fail "pkg-test reports the $scenario runtime build with exit $expected_status" "$(<"$pkg_test_output")"
  pass "a $scenario runtime build leaves both packages uninstalled and returns exit $expected_status"
}

expect_incomplete_build failed 31 "omarchy-dev build failed"
expect_incomplete_build skipped 13 "omarchy-dev build was skipped" --all "$repo"
expect_incomplete_build missing 1 "omarchy-dev did not produce exactly one" --all "$repo"

(cd "$test_tmp" && run_pkg_test success --all checkout) ||
  fail "pkg-test --all builds and installs the pair" "$(<"$pkg_test_output")"
mapfile -t calls <"$pkg_test_calls"
[[ ${#calls[@]} == 3 && ${calls[0]} == "build omarchy-settings-dev "*--nodeps* &&
  ${calls[1]} == "build omarchy-dev "*--nodeps* &&
  ${calls[2]} == "install omarchy-settings-dev-$later-1-any.pkg.tar.zst omarchy-dev-$later-1-any.pkg.tar.zst" ]] ||
  fail "pkg-test installs both exact archives in one transaction after both builds" "$(<"$pkg_test_calls")"
pass "pkg-test installs both exact archives in one transaction after both builds"

run_pkg_test success omarchy "$repo" --nocheck || fail "pkg-test builds and installs a single package" "$(<"$pkg_test_output")"
mapfile -t calls <"$pkg_test_calls"
[[ ${#calls[@]} == 2 && ${calls[0]} == "build omarchy-dev "*--nocheck && " ${calls[0]} " == *" -s "* &&
  ${calls[1]} == "install omarchy-dev-$later-1-any.pkg.tar.zst" ]] ||
  fail "single-package mode keeps its alias, makepkg flags and install" "$(<"$pkg_test_calls")"
pass "single-package mode keeps its alias, makepkg flags and install"

if ! command -v vercmp >/dev/null 2>&1; then
  skip "vercmp is not available"
  exit 0
fi

newer() {
  local cmp
  cmp=$(vercmp "$1" "$2")
  [[ $cmp == 1 ]] || fail "$3" "vercmp $1 $2 → $cmp"
  pass "$3"
}

newer "$early" "4.0.0.r7967.g3b36b9e" "handheld pkgver sorts above upstream omarchy-dev"
newer "$early" "4.0.0.r12000.gabcdef0" "handheld pkgver sorts above a higher upstream rN"
newer "$early" "dev.202611170222.e742281c" "handheld pkgver upgrades from dev.<date>.<sha>"

newer "$later" "$early" "two handheld builds sort by commit date"
rebased=$(handheld_pkgver 4.0.0 202611180900 50 aaaaaaaa)
newer "$rebased" "$later" "a newer commit date sorts above an older revision"

cmp=$(vercmp "4.0.1.r1.g0000000" "$later")
[[ $cmp == 1 ]] || fail "upstream 4.0.1 sorts above the handheld pkgver" "vercmp 4.0.1.r1.g0000000 $later → $cmp"
pass "upstream 4.0.1 sorts above the handheld pkgver"
