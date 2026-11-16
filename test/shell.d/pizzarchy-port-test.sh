#!/bin/bash
# Pizzarchy adaptations: the SteamOS update stub's exit codes, the Steam PATH
# probe that leaves the private shim in place, and the console keymap pin.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"

stub=$ROOT/default/gaming/steamos-update
stub_status() {
  "$stub" "$@" >/dev/null
  printf '%s' "$?"
}

[[ $(stub_status check) == 7 ]] || fail "check exits 7"
[[ $(stub_status apply) == 7 ]] || fail "apply exits 7"
[[ $(stub_status) == 7 ]] || fail "no argument exits 7"
[[ $(stub_status --supports-duplicate-detection) == 1 ]] || fail "duplicate detection exits 1"
[[ $(stub_status help) == 0 ]] || fail "help exits 0"
[[ $(stub_status no-such-verb) == 7 ]] || fail "an unknown verb exits 7"
help_text=$("$stub" help)
[[ $help_text == *"omarchy update"* ]] || fail "help tells the user to run omarchy update" "$help_text"
[[ $help_text != *"pacman -Syu"* ]] || fail "help points at pacman -Syu" "$help_text"
[[ $help_text == *"updates nothing"* ]] || fail "help says the stub updates nothing" "$help_text"
pass "the SteamOS update stub answers Steam and updates nothing"

for file in \
  "$ROOT/default/gaming/steamos-update" \
  "$ROOT/default/gaming/steam-path.sh" \
  "$ROOT/default/gaming/sddm-user.sh" \
  "$ROOT/install/hardware/asus/gaming-session.sh" \
  "$ROOT/migrations/1794827890.sh"
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
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
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
