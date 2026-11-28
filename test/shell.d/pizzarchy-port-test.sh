#!/bin/bash
# Pizzarchy adaptations: the SteamOS update helper's exit codes, the Steam PATH
# probe that leaves the private shim in place, and the console keymap pin.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"

stub=$ROOT/default/gaming/steamos-update
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/update-bin" "$work/update-runtime" "$work/update-home" "$work/update-tmp"

stub_status() {
  "$stub" "$@" >"$work/update.stdout" 2>"$work/update.stderr"
  printf '%s' "$?"
}

export GAMING_UPDATE_TEST_LOG=$work/update.log
export GAMING_UPDATE_TEST_TOAST=$work/update.toast
export GAMING_UPDATE_TEST_STATUS=0
export GAMING_UPDATE_TEST_APPLIED=$work/update.applied
cat >"$work/update-bin/checkupdates" <<'SH'
#!/bin/bash
[[ $1 == "--nocolor" && -n ${CHECKUPDATES_DB:-} && -d $CHECKUPDATES_DB ]] || exit 1
printf '%s\n' "$CHECKUPDATES_DB" >> "$GAMING_UPDATE_TEST_LOG"
exit "$GAMING_UPDATE_TEST_STATUS"
SH
cat >"$work/update-bin/omarchy-update" <<'SH'
#!/bin/bash
touch "$GAMING_UPDATE_TEST_APPLIED"
SH
cat >"$work/update-bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$GAMING_UPDATE_TEST_TOAST"
SH
printf '#!/bin/bash\nexit 0\n' > "$work/update-bin/logger"
chmod +x "$work/update-bin/"*

test_steam_update() (
  export PATH="$work/update-bin:$ROOT/bin:$PATH"
  export HOME=$work/update-home
  export TMPDIR=$work/update-tmp
  export XDG_DATA_HOME=$work/update-data
  export XDG_STATE_HOME=$work/update-state
  export XDG_CURRENT_DESKTOP=gamescope
  export OMARCHY_GAMING_RUNTIME=$work/update-runtime

  [[ $(stub_status check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
    fail "Steam setup defers update checks"
  [[ $(stub_status --enable-duplicate-detection check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
    fail "Steam setup defers duplicate-detection checks"
  [[ $(stub_status apply) == 7 && ! -e $GAMING_UPDATE_TEST_TOAST ]] ||
    fail "Steam setup can finish without launching the updater"
  [[ $(stub_status) == 7 && ! -e $GAMING_UPDATE_TEST_APPLIED ]] ||
    fail "Steam setup's argumentless apply changes no packages"
  [[ $(stub_status --supports-duplicate-detection) == 1 ]] ||
    fail "duplicate detection exits 1"
  [[ $(stub_status no-such-verb) == 7 ]] || fail "an unknown startup verb exits 7"
  pass "Steam setup still finishes without applying updates"

  mkdir -p "$XDG_DATA_HOME/Steam/config"
  local accounts=$XDG_DATA_HOME/Steam/config/loginusers.vdf
  printf '"users"\n{\n}\n' > "$accounts"
  touch "$OMARCHY_GAMING_RUNTIME/update-check-ready"
  [[ $(stub_status check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
    fail "a ready Steam sign-in page does not trigger an update check"
  printf '"users"\n{\n  "76561197960265729"\n  {\n    "AccountName" "test-account"\n  }\n}\n' > "$accounts"
  [[ $(stub_status check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
    fail "an existing desktop account cannot interrupt the first Gaming session"
  mkdir -p "$XDG_STATE_HOME/omarchy/gaming-session"
  printf '%s\n' completed > "$XDG_STATE_HOME/omarchy/gaming-session/update-checks"
  if (( EUID == 0 )); then
    [[ $(stub_status check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
      fail "a privileged Steam probe cannot query repositories"
    return 0
  fi

  [[ $(stub_status check) == 0 && -s $GAMING_UPDATE_TEST_LOG ]] ||
    fail "Steam reports pending repository updates after setup"
  database=$(<"$GAMING_UPDATE_TEST_LOG")
  [[ $database == "$TMPDIR"/* && ! -e $database ]] || fail "Steam leaves no check database behind"
  [[ $(GAMING_UPDATE_TEST_STATUS=2 stub_status --enable-duplicate-detection check) == 7 ]] ||
    fail "Steam reports up to date only after a successful empty check"
  [[ $(GAMING_UPDATE_TEST_STATUS=1 stub_status check) == 1 ]] ||
    fail "Steam distinguishes a failed check from up to date"
  [[ $(GAMING_UPDATE_TEST_STATUS=124 stub_status check) == 1 ]] ||
    fail "Steam does not report up to date on a timeout"
  pass "Steam checks pending repository updates using the isolated Omarchy checker"

  [[ $(stub_status apply) == 1 && ! -e $GAMING_UPDATE_TEST_APPLIED ]] ||
    fail "Steam does not apply Omarchy updates or report success"
  grep -Fq 'Switch to Desktop' "$GAMING_UPDATE_TEST_TOAST" ||
    fail "Steam update guidance gives the Desktop route"
  [[ $(stub_status --enable-duplicate-detection) == 1 && ! -e $GAMING_UPDATE_TEST_APPLIED ]] ||
    fail "Steam's alternate apply route also updates nothing"
  rm -f "$GAMING_UPDATE_TEST_LOG"
  [[ $(XDG_CURRENT_DESKTOP=Hyprland stub_status check) == 7 && ! -e $GAMING_UPDATE_TEST_LOG ]] ||
    fail "the Steam helper checks only in Gaming Mode"
  pass "Steam routes applying updates to Desktop Mode without updating or rebooting"
)

test_steam_update || exit $?
[[ $(stub_status help) == 0 ]] || fail "help exits 0"
help_text=$("$stub" help)
[[ $help_text == *"omarchy update"* ]] || fail "help tells the user to run omarchy update" "$help_text"
[[ $help_text != *"pacman -Syu"* ]] || fail "help points at pacman -Syu" "$help_text"

for file in \
  "$ROOT/default/gaming/steamos-update" \
  "$ROOT/default/gaming/steam-path.sh" \
  "$ROOT/default/gaming/sddm-user.sh" \
  "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install"
do
  if grep -v '^[[:space:]]*#' "$file" | grep -q 'NOPASSWD\|sudo -n'; then
    fail "ported file grants passwordless sudo" "$file"
  fi
done
pass "the ported files do not grant NOPASSWD"

# shellcheck source=/dev/null
source "$ROOT/default/gaming/sddm-user.sh"
sddm_parse_autologin $'[General]\nUser=other\n[Autologin]\nSession=omarchy-handheld.desktop\n'
[[ -z $sddm_autologin_user ]] || fail "a User= outside [Autologin] counts" "$sddm_autologin_user"
sddm_parse_autologin $'[Autologin]\n# User=ghost\nUser=\nUser=daniel\n'
[[ $sddm_autologin_user == daniel ]] || fail "the first counted User= is kept" "$sddm_autologin_user"
pass "only a User= inside [Autologin] counts"

# shellcheck source=/dev/null
source "$ROOT/default/gaming/steam-path.sh"
mkdir -p "$work/proc/4" "$work/bin" "$work/runtime"
printf 'leave\n' > "$work/runtime/steam-path"
private=$work/bin
export OMARCHY_STEAM_RUNTIME_PATH=$work/runtime-path
mkdir -p "$OMARCHY_STEAM_RUNTIME_PATH"
printf 'PATH=%s\0HOME=/tmp\0' "$private:/usr/bin" > "$work/proc/4/environ"
decision=$(steam_session_select_decision "$work/proc" 4 "$private")
[[ $decision == leave-private ]] || fail "a parent PATH that still contains the private directory is left there" "$decision"
printf 'PATH=/usr/bin:/bin\0' > "$work/proc/4/environ"
decision=$(steam_session_select_decision "$work/proc" 4 "$private")
[[ $decision == runtime-invisible ]] || fail "a scrubbed Steam PATH that cannot see the shim is reported" "$decision"
printf '#!/bin/sh\nexit 0\n' > "$OMARCHY_STEAM_RUNTIME_PATH/steamos-session-select"
chmod +x "$OMARCHY_STEAM_RUNTIME_PATH/steamos-session-select"
decision=$(steam_session_select_decision "$work/proc" 4 "$private")
[[ $decision == leave-private ]] || fail "a shim already on the runtime PATH is not replaced" "$decision"
rm -f "$OMARCHY_STEAM_RUNTIME_PATH/steamos-session-select" "$work/proc/4/environ"
decision=$(steam_session_select_decision "$work/proc" 4 "$private")
[[ $decision == leave-private ]] || fail "a missing environ moves the shim" "$decision"
printf 'PATH=/usr/bin:/bin\0' > "$work/proc/4/real-environ"
ln -s "$work/proc/4/real-environ" "$work/proc/4/environ"
decision=$(steam_session_select_decision "$work/proc" 4 "$private")
[[ $decision == leave-private ]] || fail "a symlinked environ is followed" "$decision"
steam_session_select_record "$work/proc" 4 "$private" "$work/runtime/steam-path"
[[ $(cat "$work/runtime/steam-path") == leave-private ]] || fail "the recorded decision follows a symlink" "$(cat "$work/runtime/steam-path")"
pass "the Steam PATH probe leaves the private shim in place"

# shellcheck source=/dev/null
source "$ROOT/install/provisioning/setup-form.sh"
keys=$work/loadkeys-log
cat > "$work/loadkeys" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$OMARCHY_LOADKEYS_LOG"
exit "${OMARCHY_LOADKEYS_RC:-0}"
EOF
chmod +x "$work/loadkeys"
export OMARCHY_LOADKEYS_LOG=$keys
export OMARCHY_FORM_LOADKEYS=$work/loadkeys
export PATH="$work:$PATH"
cat > "$work/omarchy-cmd-present" <<'EOF'
#!/bin/bash
command -v -- "$1" >/dev/null
EOF
cat > "$work/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
[[ ${HW:-ally} == ally ]]
EOF
chmod +x "$work/omarchy-cmd-present" "$work/omarchy-hw-rog-ally"

keyboard=fr
vconsole=$work/vconsole.conf
printf 'KEYMAP=fr\n' > "$vconsole"
: > "$keys"
unset OMARCHY_FORM_CONSOLE_OSK
export OMARCHY_FORM_TTY=/dev/tty1
omarchy_form_pin_console_keymap
[[ ! -s $keys ]] || fail "the keymap is pinned when the console keyboard is not up" "$(cat "$keys")"
[[ $keyboard == fr && $(cat "$vconsole") == KEYMAP=fr ]] || fail "an idle pin changes the installed layout"

export OMARCHY_FORM_CONSOLE_OSK=1
export OMARCHY_FORM_TTY=/dev/pts/3
omarchy_form_pin_console_keymap
[[ ! -s $keys ]] || fail "loadkeys runs off a virtual console" "$(cat "$keys")"

export OMARCHY_FORM_TTY=/dev/tty1
HW=laptop omarchy_form_pin_console_keymap
[[ ! -s $keys ]] || fail "a laptop pins the console keymap" "$(cat "$keys")"

HW=ally omarchy_form_pin_console_keymap
[[ $(cat "$keys") == us ]] || fail "the Ally console keyboard pins us" "$(cat "$keys")"
[[ $keyboard == fr && $(cat "$vconsole") == KEYMAP=fr ]] || fail "the live pin changes the installed layout"

export OMARCHY_LOADKEYS_RC=1
err=$(HW=ally omarchy_form_pin_console_keymap 2>&1) && fail "a failed loadkeys is ignored"
[[ $err == *"masked"* ]] || fail "a failed loadkeys does not say the password is masked" "$err"
[[ $keyboard == fr ]] || fail "a failed pin changes the stored layout"
notice() { printf 'notice:%s\n' "$1" >&2; }
if HW=ally omarchy_prompt_password; then
  fail "the password prompt continues after a failed keymap pin"
fi
pass "the console keymap pin is us, loud on failure, and leaves the installed layout"
