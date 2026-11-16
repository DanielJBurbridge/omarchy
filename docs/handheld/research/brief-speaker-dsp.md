# Speaker DSP for the ROG Ally RC71L

16 Nov 2026. Docs only. Gap 5 in [feature-parity-audit.md](feature-parity-audit.md). Nothing here was run on an RC71L. Do not copy the CachyOS or Bazzite filter files, `game.wav`, or anyone else's coefficients into this MIT tree.

## What this branch already has

[ally-hw-dump.md](ally-hw-dump.md) (12 Nov 2026, kernel `7.2.15-2-omarchy`) records DMI `ROG Ally RC71L_RC71L`, board `RC71L`. It has no codec, no sink list, and no `cs35l41` line. The raw captures are off-repo.

There is no RC71L directory under [`default/audio/tunings/`](../../../default/audio/tunings/). Existing DSP is a separate PipeWire client ([docs/audio-tuning.md](../../audio-tuning.md)): [`bin/omarchy-audio-tuning`](../../../bin/omarchy-audio-tuning) scans only that directory, names the sink `omarchy_speaker_tuning`, substitutes `@SPEAKER_SINK@`, and requires `node.dont-move` and `node.dont-fallback`. Volume stays on the physical sink; the fronted sink is hidden. A smart filter on PipeWire 1.6.8 / WirePlumber 0.5.15 links and then passes audio unprocessed. First-run applies a match by itself, so the Ally graph stays out of that directory until it is opt-in.

## CachyOS Handheld

Pin: [`d38b9f0`](https://github.com/CachyOS/CachyOS-Handheld/commit/d38b9f0bc1d801262f71335ddc9763446ac087e9) (2026-10-29). The filter last changed in [`f4fe9c20`](https://github.com/CachyOS/CachyOS-Handheld/commit/f4fe9c20af6d135c57a37ec674138b7c0e4c0d66) (2025-05-23, "new convolver file").

- `usr/share/cachyos-handheld/rog-ally/pipewire/filter-chain.conf` loads `libpipewire-module-filter-chain`: two `builtin` `convolver` nodes, channels 0 and 1 of `game.wav`, capture description `ROG Ally/X`, playback `node.target` `alsa_output.pci-0000_09_00.6.analog-stereo`.
- `usr/share/cachyos-handheld/rog-ally/game.wav` is 524402 bytes (blob `b2cc0275e207bc9f716ac7d34cc98ced43d75d4c`). It is an impulse, not an EQ table.
- `usr/share/cachyos-handheld/rog-ally/wireplumber/alsa-card0.conf` matches that node and sets `priority.driver`, `priority.session`, `api.alsa.period-size`, `api.alsa.headroom` and `session.suspend-timeout-seconds`. `alsa-card0-x.conf` is the same keys on `pci-0000_64_00.6` (not RC71L). `common/wireplumber/alsa-card1.conf` matches Deck cards `acp5x`, `acp6x` and `sof-nau8821-max` only.

[`chwd` `b5278a3`](https://github.com/CachyOS/chwd/commit/b5278a3aa999c5ea243a67e4416257406a5fe57c) profile `handheld.rog-ally` uses `board_name_pattern` `^(RC71L|RC72LA|RC73XA|RC73YA)$`, symlinks the filter into `/etc/pipewire/pipewire.conf.d`, and picks `alsa-card0.conf` when `product_name` matches `RC71L` (`alsa-card0-x.conf` for `RC72LA`). Every board in the pattern also gets `alsa-card1.conf`.

The Handheld repo has no `LICENSE`. The [`PKGBUILD`](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/cachyos-handheld/PKGBUILD) says `GPL-3.0-later`, which is not an SPDX id. chwd's README says "GNU General Public License v3.0" and its `LICENSE` is the GPL-3 text: SPDX `GPL-3.0-only`. The filter comment points at Bazzite, but Bazzite's wav below is 1832 bytes (blob `3e11c4d0`), so it is not this file. No notice on the wav. Do not vendor it.

## Bazzite and HHD

Pin: [`e13f4fda`](https://github.com/ublue-os/bazzite/commit/e13f4fdade42f9de66567b3b60f589860feb9781) (2026-11-15). Repository `LICENSE` is the Apache-2.0 text (SPDX `Apache-2.0`).

Still present: `system_files/deck/shared/usr/share/pipewire/hardware-profiles/asustek computer inc.-rog ally rc71l_rc71l/pipewire.conf.d/filter-chain.conf` and `game.wav`. Same shape: two convolvers, playback target `alsa_output.pci-0000_09_00.6.analog-stereo`, sink description `ROG Ally`. Added in [`245305de`](https://github.com/ublue-os/bazzite/commit/245305def4f3a883b762d1168b9ac13b8dea2972) (2024-07-09), message "from Aru's repo", with no URL and no licence for the wav. The directory name looks like a DMI string. The script that picks it was not read (**unverified**).

[HHD's README](https://github.com/hhd-dev/hhd) describes controller, TDP, fan, RGB and an overlay. It does not list speaker DSP. A search for `filter-chain`, `convolver` and `game.wav` there did not return a speaker graph. GitHub reports SPDX `LGPL-2.1`.

The [ASUS page](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/) says audio is soft, and that "Family 17h/19h/1ah HD Audio Controller" and "ROG Ally" each change the volume, so both must be set the same. The page says the wiki may be outdated. The second name is the filter sink, not a second codec.

## Two volumes, and the amps

The linked pair is the virtual sink plus the hardware sink it targets. The WirePlumber rule does not hide either or tie their volumes. Loading the graph in the PipeWire daemon creates the second control. Omarchy's host already avoids that.

The amps are separate. At Linux [`a2dac609`](https://github.com/torvalds/linux/blob/a2dac609bfcc395a8c2e87d3ba1fc26ac50811d0/sound/hda/codecs/realtek/alc269.c), `SND_PCI_QUIRK(0x1043, 0x17f3, "ROG Ally NR2301L/X", ALC294_FIXUP_ASUS_ALLY)` calls `cs35l41_fixup_i2c_two`: two I2C `CSC3551` (`cs35l41-hda`) amps. At [`c58471d8`](https://github.com/torvalds/linux/blob/c58471d848a7a62c0651d85983743e9e6b2e6396/sound/hda/codecs/side-codecs/cs35l41_hda_property.c) SSID `104317F3` is two internal amps, left and right. A public probe of `ROG Ally RC71L_RC71L` shows PCI `1022:15e3:1043:17f3` (Ryzen HD Audio) plus Radeon HDMI audio ([probe d9dc289509](https://linux-hardware.org/?probe=d9dc289509)). This dumped unit was not checked (**unverified**). [`COPYING`](https://github.com/torvalds/linux/blob/a2dac609bfcc395a8c2e87d3ba1fc26ac50811d0/COPYING) says `GPL-2.0 WITH Linux-syscall-note`, "version 2 only". Do not copy the quirk.

CachyOS targets BDF `09:00.6`. One RC71L log shows `pci-0000_0a_00.6` ([Batocera #9795](https://github.com/batocera-linux/batocera.linux/issues/9795)). Do not match a BDF. A search of `alsa-ucm-conf` for `RC71L` returned motherboard USB codecs, not a handheld use-case. That is not proof none exists (**unverified**). Ally X in the same file is `0x1043:0x1eb3` (RC72LA). Do not use `alsa-card0-x.conf` here.

## Steam Deck, for comparison

[valve-hardware-audio-processing](https://github.com/evlaV/valve-hardware-audio-processing) is Deck cards (`acp5x`, `sof-nau8821-max`): Faust to LV2, WirePlumber routing, UCM. Not an Ally profile. `LICENSE` is GPL-2 text plus a Faust "version 2 or later" notice. Chimera packages 0.56 as `GPL-2.0-or-later` ([template](https://github.com/chimera-linux/cports/blob/master/main/valve-hardware-audio-processing/template.py)). Bazzite `steamdeck-dsp` at [`5c62bccc`](https://github.com/ublue-os/bazzite/blob/5c62bccc/spec_files/steamdeck-dsp/steamdeck-dsp.spec) says `GPLv2`, version 0.69. Jupiter also loads `cs35l41-dsp1-spk-prot.wmfw` ([holoiso #426](https://github.com/theVakhovskeIsTaken/holoiso/issues/426)). Whether Ally `cs35l41-hda` requests that name was not read (**unverified**).

## Other references, not coefficients

[asahi-audio](https://github.com/AsahiLinux/asahi-audio) is the shape to copy as an idea: a virtual device, a WirePlumber rule, the raw sink hidden. README: through 4.2 MIT, later check-ins GPL-2. The `LICENSE` file on `main` is still the MIT text. [speakersafetyd](https://github.com/AsahiLinux/speakersafetyd) estimates coil temperature from TAS2764 voltage and current (through 2.0.2 MIT, later GPL-2). It does not speak CS35L41. Do not port it. If firmware loaded, protection here is the amp DSP. Confirm that before any boost.

EasyEffects is `GPL-3.0-or-later` ([README](https://github.com/wwmm/easyeffects)) and cannot sit beside a tuning ([docs/audio-tuning.md](../../audio-tuning.md)). No licensed RC71L preset was found. A Reddit "ROG Ally X Speakers" EQ has no licence. The MIT [G14 preset](https://github.com/WontonOP/g14-easyeffects-preset) is another laptop, tuned by ear. [M0Rf30/easyeffects-presets](https://github.com/M0Rf30/easyeffects-presets) is MIT for its own files and says its laptop chain is not from a measurement. Do not reuse those gains.

## Clean-room design

Opt-in package `omarchy-rog-ally-speaker`. Not a base package. [`install/hardware/asus/rog-ally.sh`](../../../install/hardware/asus/rog-ally.sh) stays as it is: it must not install this.

Installed paths:

- `/usr/share/omarchy-rog-ally-speaker/tuning.conf`
- `/usr/share/omarchy-rog-ally-speaker/filter-chain.conf`
- `/usr/share/wireplumber/wireplumber.conf.d/51-omarchy-rog-ally-speaker.conf`

Later, `tuning_match` may select that `tuning.conf`. `match_command` is `omarchy-hw-rog-ally`. `sink_pattern` waits for `pactl list sinks` on the RC71L: the Ryzen analog sink (`1022:15e3`), not Radeon HDMI. Until then, leave it empty and do not ship the package.

Graph, new numbers only, SPDX `MIT` with Omarchy:

- `builtin` `param_eq`, or `bq_highpass` plus `bq_peaking`, using `Freq`, `Q` and `Gain` ([PipeWire filter-chain](https://docs.pipewire.org/page_module_filter_chain.html)). No `convolver`. No `bq_raw`.
- High-pass for excursion. No broadband boost. Cutoff and bands come from a new measurement.
- End on the host's LSP limiter (`http://lsp-plug.in/plugins/lv2/limiter_stereo`), `alr` and `boost` off, threshold -1 dBFS ([docs/audio-tuning.md](../../audio-tuning.md)). Peaks stay under 0 dBFS.
- Sink name `omarchy_speaker_tuning`, `@SPEAKER_SINK@`, `node.dont-move`, `node.dont-fallback`.

The WirePlumber rule matches the Ryzen analog node by card or vendor/product id, not by PCI slot. Confirm the keys with `wpctl inspect` (**unverified**). Do not copy CachyOS's period, headroom or suspend values. It adds no second volume: `omarchy-audio-output-sink` stays the control and the fronted sink stays hidden. That is the fix for the linked pair.

`tuning.conf` sets `derived_from` to "measured on this RC71L" and records `magnitude_rms_db`, `bass_group_delay_swing_ms`, `limiter_headroom_db`, `dynamic_range_delta_lu`.

## On-device test

1. `omarchy-hw-rog-ally` is true. `dmesg` shows two `cs35l41-hda` probes and whether firmware loaded. Record the codec id. Stop if the amps failed to bind.
2. `pactl list sinks` and `wpctl status` before install. Write the Ryzen analog name into `sink_pattern`. Do not match HDMI.
3. `omarchy audio tuning on`. One speaker in the panel. Volume keys move the physical sink (`omarchy-audio-output-sink`). PipeWire's PID is unchanged. Headphone and HDMI get no speaker EQ.
4. Listen low, then moderate: speech, a bass-heavy track, pink noise. Stop on rattle, crackle or heat. No full-scale tones.
5. Electrical check, as [docs/audio-tuning.md](../../audio-tuning.md): capture the physical sink monitor, upstream of volume, and fill the four `tuning.conf` fields.
6. A hot master stays at or under -1 dBFS. Reboot and suspend leave one speaker and no sink named `ROG Ally`. `omarchy audio tuning off` restores the raw sink and leaves no `pipewire.conf.d` fragment.
