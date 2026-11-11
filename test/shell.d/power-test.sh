#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
const states = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }

assertEqual(power.selectProfileIndex(0, 1, ['balanced', 'performance']), 1, 'power advances profile selection')
assertEqual(power.selectProfileIndex(1, 1, ['balanced', 'performance']), 1, 'power clamps profile selection')

assertDeepEqual(power.parseKeyValue('time\t2:00\nenergy\t42\n'), { time: '2:00', energy: '42' }, 'power parses key-value output')
assertDeepEqual(
  power.parseProfiles('power-saver\t0\nbalanced\t1\nperformance\t0\n', 5),
  { profiles: ['power-saver', 'balanced', 'performance'], activeProfile: 'balanced', profileIndex: 2 },
  'power parses profile output and clamps selection'
)

assert(power.profileIcon('performance').length > 0, 'power maps profile icons')
assertEqual(power.batteryFraction({ isPresent: true, percentage: 1.5 }), 1, 'power clamps battery fraction')

assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.PendingCharge }, false, states), 'power detects threshold by pending charge state')
assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states), 'power detects threshold by stalled charging')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states), 'power does not flag active charging as threshold')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'power does not flag discharging as threshold')
assertEqual(power.modeLabel({ isPresent: true, percentage: 1, state: states.FullyCharged }, false, states), 'Fully charged', 'power labels full battery')
assertEqual(power.localizeReading('13.1W'), '13.1W', 'power keeps battery readings in English digits by default')
assertEqual(power.localizeReading('75-80%', function(v, d) { return '<' + v + '>' }), '<75>-<80>%', 'power localizes every number in a battery reading')
assertEqual(power.localizeReading('13.10W', function(v, d) { return v.toFixed(d).replace('.', ',') }), '13,10W', 'power keeps a reading\'s decimals when localizing')
assertEqual(power.localizeReading(undefined), '', 'power reads a missing battery field as empty')
assertEqual(power.modeLabel({ isPresent: true, percentage: 0.5, state: states.Discharging }, true, states), 'On battery', 'power labels battery mode')
assertEqual(power.modeLabel({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'Charging', 'power treats external power as newer than stale discharging state')
assert(power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging }, false, states).length > 0, 'power maps battery icons')
assertEqual(
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Discharging }, false, states),
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states),
  'power shows charging icon when external power is present before battery state refreshes'
)
assertEqual(
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging }, true, states),
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Discharging }, true, states),
  'power shows battery icon when unplugged before battery state refreshes'
)
JS

# These regressions guard unsafe requests, optimistic success and policy leakage.
ROOT="$ROOT" python3 -B <<'PY'
import importlib.util
import os
import signal
from pathlib import Path
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ally_power', Path(os.environ['ROOT']) / 'default/handheld/power.py')
power = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power)

def check(description, condition):
    if not condition:
        raise AssertionError(description)
    print('ok - ' + description)

def rejects(callback):
    try:
        callback()
    except (RuntimeError, ValueError):
        return True
    return False

class Backend:
    battery = False
    clamp = False
    missing = False
    def __init__(self):
        self.values = {
          'PerformanceProfile': 'performance', 'AvailablePerformanceProfiles': ['quiet', 'balanced', 'performance'],
          'TdpLimit': 15, 'TdpLimitMin': 5, 'TdpLimitMax': 35,
          'CpuBoostState': 1, 'CpuScalingGovernor': 'powersave', 'AvailableCpuScalingGovernors': ['powersave', 'performance'],
          'GpuPerformanceLevel': 'auto', 'AvailableGpuPerformanceLevels': ['auto', 'manual'],
          'ManualGpuClock': 800, 'ManualGpuClockMin': 400, 'ManualGpuClockMax': 2700,
          'MaxChargeLevel': 80, 'SuggestedMinimumLimit': 10,
        }
        self.writes = []
    def source(self): return 'battery' if self.battery else 'ac'
    def get(self, suffix, prop):
        if self.missing: raise RuntimeError('backend lost')
        return self.values[prop]
    def set(self, suffix, prop, signature, value):
        self.writes.append((prop, signature, value))
        if not self.clamp: self.values[prop] = value
    def wait_tdp(self): pass

backend = Backend()
cap = power.capability(backend, 'tdp', 'ac')
check('RC71L limits intersect backend range with conservative 30W ceiling', cap['max'] == 30)
check('battery ceiling is 25W', power.capability(backend, 'tdp', 'battery')['max'] == 25)
for invalid in ['nan', 'inf', '-1', '15.5', '1e2', '31', '0', '１５']:
    check('rejects invalid watts ' + invalid, rejects(lambda: power.write_control(backend, 'tdp', invalid)))
check('invalid requests never reach backend setter', not backend.writes)
backend.battery = True
check('rejects AC-only watts while on battery', rejects(lambda: power.write_control(backend, 'tdp', '30')))
backend.battery = False
check('manual GPU clock requires manual mode', rejects(lambda: power.write_control(backend, 'gpu-clock', '900')))
check('unknown governor rejected', rejects(lambda: power.write_control(backend, 'governor', 'invalid')))
check('documented default charge state reads back', power.write_control(backend, 'charge', 'default') == -1)
backend.clamp = True
with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, XDG_STATE_HOME=tmp), patch.object(power, 'conflicts', return_value=[]):
    check('writes require explicit ownership', rejects(lambda: power.remember(backend, 'tdp', '20')))
    power.state_dir().mkdir(parents=True)
    (power.state_dir() / 'enabled').touch()
    check('backend clamp is reported as failure', rejects(lambda: power.remember(backend, 'tdp', '20')))
    check('failed readback never persists preferences', not (power.state_dir() / 'preferences.json').exists())
    backend.clamp = False
    power.remember(backend, 'tdp', '20')
    backend.battery = True
    power.remember(backend, 'tdp', '12')
    policy = power.load('preferences.json')
    check('AC/DC preferences remain separate', policy['ac']['tdp'] == 20 and policy['battery']['tdp'] == 12)
    backend.values['TdpLimit'] = 7
    result = power.restore(backend)
    check('resume restore uses current source and backend readback', result['controls']['tdp']['value'] == 12)
    power.remember(backend, 'profile', 'quiet')
    check('quiet mode removes hidden custom watts', 'tdp' not in power.load('preferences.json')['battery'])
    with patch.object(power, 'conflicts', return_value=['powerstation.service']):
        count = len(backend.writes)
        check('competing writer blocks changes', rejects(lambda: power.remember(backend, 'boost', '0')))
        check('competing writer never reaches setter', len(backend.writes) == count)
    backend.missing = True
    status = power.snapshot(backend)
    check('backend failure clears controls and reports error', status.get('error') and not any(c['available'] for c in status['controls'].values()))
    backend.missing = False
    partial = power.snapshot(backend)
    partial['controls']['profile'] = {'available': False}
    count = len(backend.writes)
    with patch.object(power, 'snapshot', return_value=partial):
        check('per-game override requires a restorable profile', rejects(lambda: power.run_game(backend, '15', ['/bin/true'])))
    check('partial snapshot never reaches per-game setter', len(backend.writes) == count)
    with patch.object(power.subprocess, 'Popen', side_effect=FileNotFoundError('missing game')):
        try:
            power.run_game(backend, '15', ['/missing-game'])
        except FileNotFoundError:
            pass
        else:
            raise AssertionError('missing game must fail')
    check('failed game launch restores current source profile', backend.values['PerformanceProfile'] == 'quiet')
    check('failed game launch removes its override', not (power.state_dir() / 'game.json').exists())
    # Explicit target source is distinct from the currently connected source.
    backend.battery = False
    power.remember(backend, 'profile', 'balanced', 'ac')
    power.remember(backend, 'profile', 'quiet', 'battery')
    policy = power.load('preferences.json')
    check('plugged-in battery preference does not overwrite AC', policy['ac']['profile'] == 'balanced' and policy['battery']['profile'] == 'quiet')
    backend.battery = True
    power.remember(backend, 'profile', 'performance', 'ac')
    check('unplugged AC preference does not overwrite battery', power.load('preferences.json')['battery']['profile'] == 'quiet')
    count = len(backend.writes)
    check('invalid source rejected before mutation', rejects(lambda: power.remember(backend, 'profile', 'balanced', 'invalid')))
    check('invalid source never reaches setter', len(backend.writes) == count)
    # Profile-only policy must bound the watts that performance mode exposes.
    power.save('preferences.json', {'ac': {'profile': 'performance'}, 'battery': {'profile': 'performance'}})
    backend.battery = False
    backend.values['TdpLimit'] = 30
    power.restore(backend)
    backend.battery = True
    result = power.restore(backend)
    check('profile-only AC to battery restore bounds existing 30W to 25W', result['controls']['tdp']['value'] == 25)
    backend.battery = False
    backend.values['TdpLimit'] = 35
    power.write_control(backend, 'profile', 'performance')
    check('performance selection also bounds current AC watts', backend.values['TdpLimit'] == 30)
    backend.battery = True
    backend.values['TdpLimit'] = 30
    backend.clamp = True
    check('failed profile safety write is explicitly reported', rejects(lambda: power.write_control(backend, 'profile', 'performance')))
    backend.clamp = False
    # Deliver a real TERM during startup mutations, before a child exists.
    power.save('preferences.json', {'battery': {'profile': 'quiet'}})
    for phase in ('setter', 'launch'):
        backend.values['PerformanceProfile'] = 'quiet'
        backend.values['TdpLimit'] = 12
        actual_set = backend.set
        signalled = []
        def terminate_set(suffix, prop, signature, value):
            actual_set(suffix, prop, signature, value)
            if prop == 'PerformanceProfile' and value == 'performance' and not signalled:
                signalled.append(True)
                os.kill(os.getpid(), signal.SIGTERM)
        def terminate_launch(*args, **kwargs):
            os.kill(os.getpid(), signal.SIGTERM)
            raise FileNotFoundError('missing game')
        previous_term = signal.getsignal(signal.SIGTERM)
        with patch.object(backend, 'set', side_effect=terminate_set if phase == 'setter' else actual_set), patch.object(power.subprocess, 'Popen', side_effect=terminate_launch):
            check('TERM during startup ' + phase + ' is handled', rejects(lambda: power.run_game(backend, '15', ['/missing-game'])))
        check('TERM during ' + phase + ' restores profile', backend.values['PerformanceProfile'] == 'quiet')
        check('TERM during ' + phase + ' removes override', not (power.state_dir() / 'game.json').exists())
        check('TERM during ' + phase + ' restores signal handler', signal.getsignal(signal.SIGTERM) == previous_term)
PY

# The rejected Manager package must never reach takeover, even when installed.
setup_tmp=$(mktemp -d)
trap 'rm -rf "$setup_tmp"' EXIT
mkdir -p "$setup_tmp/bin" "$setup_tmp/home"
printf '#!/bin/bash\nexit 0\n' >"$setup_tmp/bin/omarchy-hw-rog-ally"
for command in pacman sudo systemctl busctl omarchy-power-ally; do
  cat >"$setup_tmp/bin/$command" <<'SH'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$SETUP_CALLS"
if [[ ${0##*/} == "pacman" ]]; then echo 'steamos-manager 26.4.1-3'; else exit 97; fi
SH
done
chmod +x "$setup_tmp/bin/"*
if HOME="$setup_tmp/home" XDG_STATE_HOME="$setup_tmp/home/state" XDG_CONFIG_HOME="$setup_tmp/home/config" \
  SETUP_CALLS="$setup_tmp/calls" PATH="$setup_tmp/bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-power" --configure-reviewed-package >"$setup_tmp/output" 2>&1; then
  fail "power setup refuses the rejected Manager package"
fi
[[ ! -s $setup_tmp/calls && ! -e $setup_tmp/home/state && ! -e $setup_tmp/home/config ]] ||
  fail "power setup hold precedes package, service and state work" "$(cat "$setup_tmp/calls" 2>/dev/null)"
pass "power setup rejects takeover before package queries, service changes or state writes"
