# Speaker DSP for the ROG Ally RC71L

16 Nov 2026. Docs only. Gap 5 in [feature-parity-audit.md](feature-parity-audit.md). Nothing here was run on an RC71L. Reuse the speaker host already in this tree. Do not copy the CachyOS or Bazzite filter files, `game.wav`, or anyone else's coefficients into this MIT tree.

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

[valve-hardware-audio-processing](https://github.com/evlaV/valve-hardware-audio-processing) targets Deck cards (`acp5x`, `sof-nau8821-max`): Faust to LV2, WirePlumber routing, UCM. Not an Ally profile. The pinned files are under Code to reuse. Jupiter also loads `cs35l41-dsp1-spk-prot.wmfw` ([holoiso #426](https://github.com/theVakhovskeIsTaken/holoiso/issues/426)). Whether Ally `cs35l41-hda` requests that name was not read (**unverified**).

## Code to reuse

Reuse this tree's speaker host.

- This repo at [`ff1020916`](https://github.com/DanielJBurbridge/omarchy/commit/ff1020916fe6518d8835cc91b2a1f8cbe308adca). The root `LICENSE` is the MIT text (SPDX `MIT`). Keep [`bin/omarchy-audio-tuning`](../../../bin/omarchy-audio-tuning) and [`default/audio/filter-chain-host.conf`](../../../default/audio/filter-chain-host.conf). Copy the shape of [`default/audio/tunings/asus-proart-p14-n1x/filter-chain.conf`](../../../default/audio/tunings/asus-proart-p14-n1x/filter-chain.conf) and its `tuning.conf`: stereo links, `node.dont-move`, `node.dont-fallback`, and the LSP limiter URI. Do not copy that laptop's gains. Its `tuning.conf` says they were fitted from an ASUS Dolby curve for the H7407BA.

- PipeWire [`8e3a214e`](https://github.com/PipeWire/pipewire/commit/8e3a214ecfd9aece7eaabb67d29ade3496b9bbdf) (2026-11-16), `src/daemon/filter-chain/sink-eq6.conf`. [`COPYING`](https://github.com/PipeWire/pipewire/blob/8e3a214ecfd9aece7eaabb67d29ade3496b9bbdf/COPYING) is the MIT Expat text (SPDX `MIT`). The file has no SPDX line. It is six `builtin` bands (`bq_lowshelf`, four `bq_peaking`, `bq_highshelf`) with `Freq`, `Q` and `Gain`, every gain 0. Vendor those bands into that skeleton, keep the copyright notice, and set the controls from a new RC71L measurement.

- [asahi-audio](https://github.com/AsahiLinux/asahi-audio) `v4.2` ([`f5b118a8`](https://github.com/AsahiLinux/asahi-audio/commit/f5b118a8a2fb150b145cb667b4738cdab0304eb0)). `LICENSE` is MIT. `conf/wireplumber.conf` matches `hw:AppleJ*` and renames the raw sink. `conf/asahi-lock-volume.lua` forces the Apple speaker route to unity. `firs/` is per-MacBook impulse data. Do not vendor: wrong machine. On `main` ([`ab1b4692`](https://github.com/AsahiLinux/asahi-audio/commit/ab1b46928d056bb02bb4ad72d522dab57dc9efe1)) those two configs are `SPDX-License-Identifier: GPL-2.0-or-later`. Do not depend on the package. The host already hides the fronted sink and leaves volume on the physical sink. [speakersafetyd](https://github.com/AsahiLinux/speakersafetyd) estimates TAS2764 coil temperature. It does not speak CS35L41. Do not port it.

- Valve [`027c7bbe`](https://github.com/evlaV/valve-hardware-audio-processing/commit/027c7bbe2145fcc7ec4cb511d692baf9d302de5e) (2026-11-11). `LICENSE` is the Faust compiler's GPL notice: SPDX `GPL-2.0-or-later`. `src/faust/valve_deck_speakers.dsp` says "Speaker tuning for the Steam Deck speakers" and sets `IN_GAIN_DB = 10.5`. `pipewire-confs/hardware-profiles/valve-jupiter/filter-chain.conf.d/filter-chain.conf` is a microphone chain (`valve_deck_microphone`, rnnoise). `ucm2/conf.d/acp5x/HiFi.conf` is the Deck card. Do not vendor, and do not depend on the package for the Ally.

- EasyEffects [`c8081b8d`](https://github.com/wwmm/easyeffects/commit/c8081b8df73a89ae14dc5b9f76ecc81b376a9188) (2026-11-15) is `GPL-3.0-or-later`. No licensed RC71L preset was found. A Reddit "ROG Ally X Speakers" EQ has no licence. [g14.json](https://github.com/WontonOP/g14-easyeffects-preset/blob/42c9d8e7557bf09eea90619d28b224dfc3519e5c/g14.json) at [`42c9d8e7`](https://github.com/WontonOP/g14-easyeffects-preset/commit/42c9d8e7557bf09eea90619d28b224dfc3519e5c) is MIT and was tuned by ear for a Zephyrus G14. [Cupertino Laptop Speakers.json](https://github.com/M0Rf30/easyeffects-presets/blob/654f94b780183c2fa5c78ed002b288e15ffca20f/Cupertino%20Laptop%20Speakers.json) at [`654f94b7`](https://github.com/M0Rf30/easyeffects-presets/commit/654f94b780183c2fa5c78ed002b288e15ffca20f) is one of that repo's own MIT files; the README says it is not from a measurement. Other files there are not all MIT. Do not vendor those gains. Do not run EasyEffects beside a tuning ([docs/audio-tuning.md](../../audio-tuning.md)).

CachyOS and Bazzite `game.wav`, and both Ally `filter-chain.conf` files, have no usable licence. Nothing there is reusable.

## What to ship

Opt-in package `omarchy-rog-ally-speaker`. Not a base package. [`install/hardware/asus/rog-ally.sh`](../../../install/hardware/asus/rog-ally.sh) must not install it. No new WirePlumber file and no `pipewire.conf.d` fragment.

- `/usr/share/omarchy-rog-ally-speaker/tuning.conf`
- `/usr/share/omarchy-rog-ally-speaker/filter-chain.conf`

`match_command` is `omarchy-hw-rog-ally`. `sink_pattern` stays empty until `pactl list sinks` on an RC71L names the Ryzen analog sink (`1022:15e3`), not HDMI. Do not ship before that, and do not match a PCI slot. The graph is the vendored `sink-eq6` skeleton plus the host limiter (`http://lsp-plug.in/plugins/lv2/limiter_stereo`, `alr` and `boost` off, threshold -1 dBFS). High-pass for excursion. No broadband boost. No `convolver`. No `bq_raw`. Bands come from the new measurement. `derived_from` is "measured on this RC71L", with `magnitude_rms_db`, `bass_group_delay_swing_ms`, `limiter_headroom_db` and `dynamic_range_delta_lu`. One volume control: `omarchy-audio-output-sink` stays the control, and the fronted sink stays hidden. That is the fix for the linked pair. If the amps loaded their firmware, protection stays in the amp DSP. Confirm that before any boost.

## Omarchy core fit

Working is `omarchy audio tuning on` on an RC71L: one speaker in the panel, volume keys on the physical sink, headphone and HDMI left alone. Fit for core is those two files later moving under `default/audio/tunings/`, still gated by `omarchy-hw-rog-ally`, with `omarchy-*` names, no GPL blob, and no unlicensed impulse in this MIT tree.

## On-device test

1. `omarchy-hw-rog-ally` is true. `dmesg` shows two `cs35l41-hda` probes and whether firmware loaded. Record the codec id. Stop if the amps failed to bind.
2. `pactl list sinks` and `wpctl status` before install. Write the Ryzen analog name into `sink_pattern`. Do not match HDMI.
3. `omarchy audio tuning on`. One speaker in the panel. Volume keys move the physical sink (`omarchy-audio-output-sink`). PipeWire's PID is unchanged. Headphone and HDMI get no speaker EQ.
4. Listen low, then moderate: speech, a bass-heavy track, pink noise. Stop on rattle, crackle or heat. No full-scale tones.
5. Electrical check, as [docs/audio-tuning.md](../../audio-tuning.md): capture the physical sink monitor, upstream of volume, and fill the four `tuning.conf` fields.
6. A hot master stays at or under -1 dBFS. Reboot and suspend leave one speaker and no sink named `ROG Ally`. `omarchy audio tuning off` restores the raw sink and leaves no `pipewire.conf.d` fragment.
