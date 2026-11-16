# shellcheck shell=bash
# Adapted from Pizzarchy src/deck-session.sh stage_steam_hook, commit
# daa9376ab733880e612569467164754096a5f0f4. Only the PATH check is adapted.
# The Pizzarchy shim escalates to a root writer. This file does not install a
# shim, does not write /usr/bin, and does not grant sudo.
#
# Copyright (c) 2026 Diego Huyke
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Steam's runtime PATH on a Deck was measured as /usr/bin:/bin, so a copy of
# steamos-session-select that lives only in a private directory is invisible
# once that runtime replaces the parent PATH. On the Ally that environ is not
# measured yet. If the parent PATH is still the process PATH, or the live
# environ cannot be read, the private directory stays. This probe never moves
# the shim.

steam_session_select_resolved() {
  local path=${1:-${OMARCHY_STEAM_RUNTIME_PATH:-/usr/bin:/bin}}
  # /bin/sh is absolute so the PATH under test is only what command -v searches.
  # Steam's runtime PATH is /usr/bin:/bin, which would also find sh, but a
  # probe of any other directory must not depend on that.
  env -i PATH="$path" /bin/sh -c 'command -v steamos-session-select' 2>/dev/null || true
}

steam_environ_path() {
  local root=$1 pid=$2 file=$root/$pid/environ line
  [[ -f $file && ! -L $file ]] || return 0
  while IFS= read -r -d '' line || [[ -n $line ]]; do
    if [[ $line == PATH=* ]]; then
      printf '%s' "${line#PATH=}"
      return 0
    fi
  done <"$file"
}

# Prints leave-private or runtime-invisible. leave-private means do not install
# a /usr/bin copy. runtime-invisible means Steam's own PATH cannot see the
# shim and the parent PATH did not survive; the shim still stays private until
# that environ is confirmed on an Ally.
steam_session_select_decision() {
  local root=$1 pid=$2 private_dir=$3
  local runtime_path=${OMARCHY_STEAM_RUNTIME_PATH:-/usr/bin:/bin}
  local runtime_hit steam_path
  runtime_hit=$(steam_session_select_resolved "$runtime_path")
  steam_path=$(steam_environ_path "$root" "$pid")
  if [[ -n $runtime_hit ]]; then
    printf 'leave-private\n'
    return 0
  fi
  if [[ -n $private_dir && -n $steam_path && $steam_path == *"$private_dir"* ]]; then
    printf 'leave-private\n'
    return 0
  fi
  if [[ -z $steam_path ]]; then
    printf 'leave-private\n'
    return 0
  fi
  printf 'runtime-invisible\n'
}

steam_session_select_record() {
  local root=$1 pid=$2 private_dir=$3 dest=$4 decision
  local runtime_path=${OMARCHY_STEAM_RUNTIME_PATH:-/usr/bin:/bin}
  decision=$(steam_session_select_decision "$root" "$pid" "$private_dir")
  if [[ -n $dest && ! -L $dest ]]; then
    printf '%s\n' "$decision" >"$dest" || true
  fi
  if [[ $decision == runtime-invisible ]]; then
    printf 'steamos-session-select is not on Steam PATH %s; the private gaming directory stays in place\n' "$runtime_path" >&2
  fi
}
