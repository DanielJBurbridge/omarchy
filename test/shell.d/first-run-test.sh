#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"

cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
[[ $1 == "check" && $2 == "first-run-user" ]]
SH
cat >"$mock_bin/omarchy-provision-user" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_FINALIZE_CALLED"
SH
chmod +x "$mock_bin/omarchy-done" "$mock_bin/omarchy-provision-user"

finalize_called="$test_tmp/finalize-called"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_FINALIZE_CALLED="$finalize_called" \
  bash "$ROOT/bin/omarchy-provision-first-run" >"$test_tmp/output"

[[ ! -e $finalize_called ]] || fail "completed first-run exits before any setup step"
grep -F 'First-run already complete' "$test_tmp/output" >/dev/null || fail "completed first-run reports its lifecycle gate"

pass "completed first-run exits at its lifecycle gate"

# systemctl enables none of a list when one unit in it is unknown, so a unit
# missing from a build must cost first-run only that unit.
cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
[[ $* != *"$OMARCHY_TEST_MISSING_UNIT"* ]] || exit 1
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH
cat >"$mock_bin/omarchy-hook-install" <<'SH'
#!/bin/bash
echo "hook $*" >>"$OMARCHY_TEST_CALLS"
SH
chmod +x "$mock_bin/systemctl" "$mock_bin/omarchy-hook-install"

enable_user_units() {
  rm -f "$test_tmp/calls"
  PATH="$mock_bin:$PATH" OMARCHY_TEST_CALLS="$test_tmp/calls" OMARCHY_TEST_MISSING_UNIT="$1" \
    bash "$ROOT/install/user/first-run/enable-user-units.sh"
}

enable_user_units no-such-unit || fail "first-run enables its user units"
clean_run=$(<"$test_tmp/calls")
grep -Fq 'hook theme-set' <<<"$clean_run" || fail "first-run installs the theme hook"
mapfile -t units < <(sed -n 's/^--user enable --now //p' <<<"$clean_run")

for unit in "${units[@]}"; do
  [[ $unit != *" "* ]] || fail "first-run enables each unit on its own" "$unit"
  if enable_user_units "$unit"; then
    fail "first-run reports a unit it could not enable" "$unit"
  fi
  [[ $(<"$test_tmp/calls") == "$(grep -Fvx -- "--user enable --now $unit" <<<"$clean_run")" ]] ||
    fail "a unit missing from the build costs first-run only that unit" "$unit"
done
(( ${#units[@]} > 1 )) || fail "first-run enables each unit on its own"
pass "a unit missing from the build costs first-run only that unit"

# First run offers an update only when there is one. A fresh install from
# current media is already current, and a critical toast that leads to
# "nothing to do" teaches people to dismiss the next one.
cat >"$mock_bin/nm-online" <<'SH'
#!/bin/bash
exit 0
SH
# Like the real one, it looks for Omarchy's package with checkupdates.
cat >"$mock_bin/omarchy-update-available" <<'SH'
#!/bin/bash
checkupdates >/dev/null
exit "$OMARCHY_TEST_OMARCHY_UPDATE"
SH
cat >"$mock_bin/checkupdates" <<'SH'
#!/bin/bash
echo checkupdates >>"$OMARCHY_TEST_CALLS"
exit "$OMARCHY_TEST_CHECKUPDATES"
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH
cat >"$mock_bin/omarchy-i18n" <<'SH'
#!/bin/bash
echo "$1"
SH
printf '#!/bin/bash\nexit 1\n' >"$mock_bin/omarchy-hw-rog-ally"
chmod +x "$mock_bin/nm-online" "$mock_bin/omarchy-update-available" \
  "$mock_bin/checkupdates" "$mock_bin/omarchy-notification-send" "$mock_bin/omarchy-i18n" \
  "$mock_bin/omarchy-hw-rog-ally"

# Arguments: OMARCHY_PATH, omarchy-update-available's exit status, then
# checkupdates'.
offers_update() {
  : >"$test_tmp/calls"
  OMARCHY_PATH="$1" PATH="$mock_bin:$PATH" OMARCHY_TEST_CALLS="$test_tmp/calls" \
    OMARCHY_TEST_OMARCHY_UPDATE="$2" OMARCHY_TEST_CHECKUPDATES="$3" \
    bash -c 'source "$1"; wait' _ "$ROOT/install/user/first-run/wifi.sh"
  grep -Fq -- '--exec omarchy-launch-floating-terminal-with-presentation omarchy-update' "$test_tmp/calls"
}

installed=/usr/share/omarchy
checkout="$test_tmp/omarchy-checkout"
mkdir -p "$checkout"
ln -s "$ROOT/install" "$checkout/install"

if offers_update "$installed" 1 2; then
  fail "first run offers no update when nothing is pending"
fi
[[ $(grep -c '^checkupdates$' "$test_tmp/calls") == 1 ]] ||
  fail "first run syncs the package databases once"
offers_update "$installed" 1 0 || fail "first run offers an update when packages are pending"
offers_update "$installed" 1 1 || fail "first run offers an update when it cannot tell whether one is pending"
offers_update "$checkout" 0 2 || fail "first run offers an update when a development checkout is behind"
if offers_update "$checkout" 1 2; then
  fail "first run offers no update when a current checkout has nothing pending"
fi
pass "first run offers an update only when there is one"

# Choosing an agent installs it, so the invitation waits for a connection, not
# for the first update.
cat >"$mock_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
SH
cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
[[ $1 == "ensure" ]]
SH
chmod +x "$mock_bin/omarchy-default-agent" "$mock_bin/omarchy-done"
offers_update "$checkout" 1 2 || true
grep -Fq -- '--exec omarchy menu summon agent.harness' "$test_tmp/calls" ||
  fail "first run invites a default agent once there is a connection"
pass "first run invites a default agent once there is a connection"

# Arguments: the git name and email already configured, empty for unset.
offers_git_setup() {
  : >"$test_tmp/calls"
  local home="$test_tmp/git-home"
  rm -rf "$home" && mkdir -p "$home"
  [[ -z $1 ]] || HOME="$home" git config --global user.name "$1"
  [[ -z $2 ]] || HOME="$home" git config --global user.email "$2"
  HOME="$home" PATH="$mock_bin:$PATH" OMARCHY_TEST_CALLS="$test_tmp/calls" \
    bash "$ROOT/install/user/first-run/git.sh"
  grep -Fq 'omarchy-setup-git' "$test_tmp/calls"
}

offers_git_setup "" "" || fail "first run offers git setup on a fresh account"
offers_git_setup "Jane" "" || fail "first run offers git setup when the email is missing"
if offers_git_setup "Jane" "jane@example.com"; then
  fail "first run offers no git setup when the install already set an identity"
fi
pass "first run offers git setup only when the identity is missing"

# The network waiter is scoped to the first graphical session. If that login
# ends offline, only the pending Ally offer should wait on the next login.
ally_root=$test_tmp/ally
ally_steps=$ally_root/install/user/first-run
ally_done=$test_tmp/home/.local/state/omarchy/done
mkdir -p "$ally_steps"
for script in enable-user-units.sh gnome-theme.sh gtk-primary-paste.sh audio-tuning.sh superwhisper.sh welcome.sh git.sh; do
  printf 'echo ordinary-first-run >>"$OMARCHY_TEST_CALLS"\n' >"$ally_steps/$script"
done
for hook in setup-agent.hook setup-fingerprint.hook; do
  printf 'echo ordinary-online-setup >>"$OMARCHY_TEST_CALLS"\n' >"$ally_steps/$hook"
done
ln -s "$ROOT/install/user/first-run/wifi.sh" "$ally_steps/wifi.sh"
ln -s "$ROOT/install/user/first-run/setup-rog-ally.hook" "$ally_steps/setup-rog-ally.hook"
ln -sf "$ROOT/bin/omarchy-done" "$mock_bin/omarchy-done"

for helper in omarchy-provision-user omarchy-lifecycle-dispatch omarchy-notification-wait omarchy-hw-rog-ally; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$helper"
done
printf '#!/bin/bash\nexit 1\n' >"$mock_bin/omarchy-cmd-present"
cat >"$mock_bin/nm-online" <<'SH'
#!/bin/bash
case " $* " in
  *" -s "*) exit 0 ;;
  *" -x "*) [[ -f $ALLY_ONLINE ]]; exit $? ;;
esac
if [[ ! -f $ALLY_ONLINE ]]; then
  printf '%s\n' waiting >>"$OMARCHY_TEST_CALLS"
  exec sleep 30
fi
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
if [[ $* == *firstRun.rogAllyTitle* ]]; then
  printf '%s\n' ally-attempted >>"$OMARCHY_TEST_CALLS"
  [[ ${ALLY_FAIL_NOTIFY:-0} != "1" ]] || exit 1
  printf '%s\n' ally-delivered >>"$OMARCHY_TEST_CALLS"
fi
SH
chmod +x "$mock_bin/"*

ally_login=(env "HOME=$test_tmp/home" "OMARCHY_PATH=$ally_root" "PATH=$mock_bin:$PATH"
  "OMARCHY_TEST_CALLS=$test_tmp/calls" "ALLY_ONLINE=$test_tmp/online"
  OMARCHY_TEST_CHECKUPDATES=2 OMARCHY_TEST_OMARCHY_UPDATE=1)
: >"$test_tmp/calls"
setsid "${ally_login[@]}" "$ROOT/bin/omarchy-provision-first-run" >"$test_tmp/ally-login.log" 2>&1 &
ally_session=$!
trap 'kill -- "-$ally_session" 2>/dev/null; rm -rf "$test_tmp"' EXIT
wait "$ally_session" || fail "first run can finish while the Ally is offline"
for _ in {1..40}; do
  grep -Fxq waiting "$test_tmp/calls" && break
  sleep 0.05
done
grep -Fxq waiting "$test_tmp/calls" || fail "the first login was waiting for the network"
[[ -f $ally_done/first-run-user && ! -e $ally_done/rog-ally-gaming-invitation ]] ||
  fail "offline first run leaves the gaming invitation undelivered"
kill -- "-$ally_session" || fail "the logout stops the first session's network waiter"
trap 'rm -rf "$test_tmp"' EXIT
touch "$test_tmp/online"

online_ally_login() {
  (set -o pipefail
    timeout 5 "${ally_login[@]}" "$@" "$ROOT/bin/omarchy-provision-first-run" |
      cat >"$test_tmp/ally-login.log")
}

: >"$test_tmp/calls"
ALLY_FAIL_NOTIFY=1 online_ally_login || fail "later online Ally login completes"
[[ $(<"$test_tmp/calls") == "ally-attempted" && ! -e $ally_done/rog-ally-gaming-invitation ]] ||
  fail "a new online login attempts only the pending Ally offer and a failed send leaves it pending" "$(cat "$test_tmp/calls")"
online_ally_login || fail "online Ally login completes with notification server recovered"
online_ally_login || fail "online Ally login completes after invitation delivery"
[[ $(grep -Fxc ally-attempted "$test_tmp/calls") == "2" && $(grep -Fxc ally-delivered "$test_tmp/calls") == "1" ]] ||
  fail "the next login retries the failed offer and later logins skip it" "$(cat "$test_tmp/calls")"
[[ -f $ally_done/rog-ally-gaming-invitation ]] || fail "only a successful delivery marks the offer done"

mkdir -p "$test_tmp/provisioned/.local/state/omarchy/done"
touch "$test_tmp/provisioned/.local/state/omarchy/done/first-run-user"
: >"$test_tmp/calls"
online_ally_login "HOME=$test_tmp/provisioned" || fail "existing provisioned login completes"
[[ ! -s $test_tmp/calls ]] || fail "existing provisioned users receive no unscheduled first-login offer"
pass "the pending Ally offer survives logout, retries failed delivery and appears only once"
