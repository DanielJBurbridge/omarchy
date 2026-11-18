"""Exercise saved-state decisions through the CLI with an isolated live-state reader."""
import contextlib
import io
import runpy
import sys
from pathlib import Path
from unittest.mock import patch

root, scratch = map(Path, sys.argv[1:])
main = runpy.run_path(str(root / "bin/omarchy-games-lighting"))["main"]
config = scratch / "aura_1abe.ron"
leds = scratch / "leds"
(leds / "asus::kbd_backlight").mkdir(parents=True)
modes = {10: "Pulse", 2: "RainbowCycle", 1: "Breathe", 3: "RainbowWave", 0: "Static"}
effects = {key: (key, 0, (10, 20, 30), (41, 51, 61), "High", "Left") for key in modes}


class Owner:
  path = "/xyz/ljones/aura/1abe_2_1"

  def read(self):
    return 1, 2, effects, ([(6, True, True, False, True)],)

  def set(self, *args):
    raise AssertionError(f"Unexpected setter during a refused request: {args}")


def invoke(*args):
  output = io.StringIO()
  with patch.object(sys, "argv", ["lighting", *args]), contextlib.redirect_stdout(output):
    main()
  return output.getvalue()


# A disabled optional map, permuted mode keys and struct fields, mixed trailing commas.
builtins = ", ".join(
  f"{name}: (colour2: (g: 51, b: 61, r: 41), mode: {name}, direction: Left, "
  "colour1: (b: 30, r: 10, g: 20,), speed: High, zone: r#None)"
  for name in modes.values()
)
saved = f"""(enabled: (states: [(awake: true, zone: Ally, shutdown: true, sleep: false, boot: true)]),
builtins: {{{builtins},}}, current_mode: Breathe, multizone: Some({{}},),
config_name: "aura_1abe.ron", multizone_on: false, brightness: Med, ally_fix: Some(true))"""
config.write_text(saved)
with patch.dict(main.__globals__, CONFIG=config, LEDS=leds, WRITE_LOCK=scratch / "lock", Aura=Owner):
  assert "Persistence: verified" in invoke()
  for changed in (
    saved.replace("brightness: Med", "brightness: Off"),
    saved.replace("current_mode: Breathe", "current_mode: Static"),
    saved.replace("r: 10", "r: 99"),
  ):
    config.write_text(changed)
    assert "Persistence: mismatch" in invoke("status")
    for request in [("preset", "pulse"), ("colour", "aabbcc"), ("brightness", "medium")]:
      try:
        invoke(*request)
      except ValueError as error:
        assert "mismatch" in str(error)
      else:
        raise AssertionError("Accepted a request with disk/live drift")
    assert config.read_text() == changed
  config.write_text(saved.replace("brightness: Med", "brightness: Med, brightness: Low"))
  assert "Persistence: unavailable" in invoke()
  config.unlink()
  assert "Persistence: unavailable" in invoke("status")
