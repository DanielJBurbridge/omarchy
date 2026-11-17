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
