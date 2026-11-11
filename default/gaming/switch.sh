#!/bin/bash

# Run only in the transient user job, outside the departing graphical target.
set -uo pipefail
(( $# == 1 )) || exit 2
runtime=$1
[[ -d $runtime && ! -L $runtime && -O $runtime ]] || exit 1
exec 9>"$runtime/switch.lock"
flock -n 9 || exit 0
[[ -f $runtime/active && $(cat "$runtime/active") == "desktop" ]] || exit 1

cleanup() { rm -f "$runtime/switch"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
printf 'gaming\n' >"$runtime/switch"
if omarchy-system logout --execute; then
  # The supervisor consumes this request when UWSM actually exits.
  trap - EXIT
else
  exit $?
fi
