# Prior art for an Omarchy handheld mode

Researched 16 Nov 2026 (AWST). This is a research note. It does not change code. The branch it was read against is [`feat/ally-parity-integration-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-parity-integration-20261111). Omarchy's own licence file is the MIT text, copyright David Heinemeier Hansson ([LICENSE](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/LICENSE)).

Four projects. Each section records what it does, the SPDX id taken from its LICENSE file, how it starts Steam or gamescope and how it returns to the desktop, how it handles a keyboard-free install, login, Wi-Fi, an on-screen keyboard and password prompts, and the date of its last commit. A direct fetch of the Reddit thread timed out. Where a claim comes from a search index of that thread, the sentence says so.

**Unverified** means this note did not read a primary page for that claim, or the page that was read did not say it. Nothing here was run on an RC71L or a Steam Deck.

## 1. Pizzarchy

Repo: [villenull/Pizzarchy](https://github.com/villenull/Pizzarchy), found from the r/omarchy post [1vrp7n6](https://www.reddit.com/r/omarchy/comments/1vrp7n6/project_pizzarchy_omarchy_on_your_steam_deck/). The search index of that post (16 Nov 2026) describes a controller-only Omarchy Quattro install for a physical Steam Deck, with STEAM+X for an on-screen keyboard, and points at GitHub for the instructions. The README matches that description and names the project. The post body itself was not re-fetched.

What it is: a fork of Omarchy's installer with a Steam Deck overlay. One USB image installs Omarchy. The Deck's buttons and trackpads drive the install. Boot lands in Gaming Mode. Desktop Mode is Omarchy on Hyprland. The README says it was verified on one Steam Deck OLED, by eye, on 2026-09-20, and that the LCD model is not tested. It wipes the device. It is not dual-boot. ([README](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/README.md))

Licence: `MIT`. The LICENSE file is the MIT text, copyright (c) 2026 Diego Huyke. There is no SPDX header in the file. The SPDX id is the one that text is. ([LICENSE](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/LICENSE))

### Session start and return

It does not launch gamescope itself. `src/deck-session.sh` says Valve's `jupiter-staging/gamescope` already ships the session, and this script only switches between that session and the Omarchy desktop. The names it records:

| Piece | Path |
|---|---|
| Session entry | `/usr/share/wayland-sessions/gamescope-wayland.desktop` |
| Entry point | `/usr/bin/start-gamescope-session` |
| Launcher | `/usr/lib/steamos/gamescope-session` |
| Unit | `/usr/lib/systemd/user/gamescope-session.target` |
| SDDM name | `gamescope-wayland` (`GAMING_SESSION`) |

Pinned at [`daa9376`](https://github.com/villenull/Pizzarchy/commit/daa9376ab733880e612569467164754096a5f0f4), `src/deck-session.sh` header and the `GAMING_SESSION` constant. The same header says Arch's gamescope package ships no `wayland-sessions` file and no `start-gamescope-session`. That was checked by the author with `pacman -Ql` on a Deck. This note did not repeat that query.

Switch to desktop: Steam runs `steamos-session-select`, and the argument the author observed in a sudo audit was `plasma`. `stage_steam_hook` installs `/usr/bin/steamos-session-select`. `render_steam_shim` is `exec sudo -n /usr/local/bin/deck-session-select "$@"`. The real writer is `stage_session_select`, which generates `deck-session-select`. That program accepts `gamescope|gaming|gamescope-wayland` and `desktop|plasma|omarchy`, checks the `.desktop` exists, and writes `/etc/sddm.conf.d/zz-deck-session.conf` with `User=`, `Session=` and `Relogin=true`. It then starts a transient systemd unit so SDDM restarts outside the session cgroup. A sudoers drop-in, `/etc/sudoers.d/99-deck-session-select`, is `NOPASSWD` for that one binary. The comment says Steam's runtime PATH is `/usr/bin:/bin`, read from a running Steam process, so a copy in `/usr/local/bin` is invisible to Steam.

Return to Gaming Mode: both the desktop file `deck-return-to-gaming.desktop` and the Quickshell menu row `system.gaming` run `/usr/bin/steamos-session-select gamescope` (`RETURN_ACTION`). `stage_default_session` sets Gaming Mode as the default and says Steam's own Switch to Desktop rewrites that default. `stage_boot_default_gaming` installs `deck-boot-default-gaming.service`, which runs `render_boot_default_helper`. On each boot the helper re-asserts Gaming Mode, unless too many boots failed to leave a compositor alive.

### Keyboard-free install, login, Wi-Fi, OSK, passwords

The installer form is `iso/overlay/configs/airootfs/usr/share/omarchy-iso/deck-form.sh`. `DECK_MAPPER_ARGS` is `--osk-backend=tty --osk-start-shown`. The on-screen keyboard is drawn on the console. `deck_form_disk_encryption_mode` prints `false`, and `confirm_disk_overwrite` stores that. Encryption is off.

Wi-Fi is required. The form parses `iwctl station wlan0 get-networks` in `deck_form_parse_iwctl_networks`. That function's own comment says the column layout was inferred and should be confirmed against a live Deck. `deck_wifi.py` (`carry_wifi`, `install_first_boot_unit`, `carry_wifi_step`) copies a staged profile onto the installed system and installs `omarchy-deck-wifi-first-boot.service`. This note did not read every branch of that copy.

Login: `deck_autologin.py` writes the same SDDM drop-in at install time. `render_dropin` writes `User=`, `Session=` and `Relogin=true`. `parse_autologin` only counts keys inside `[Autologin]`. `assert_sorts_last` checks the filename sorts after the other files in `sddm.conf.d`. The module's header says a `Session=` without `User=` makes SDDM ignore the block, measured on their hardware, and that `Relogin=false` leaves a dead session on a password greeter no controller can answer.

The desktop on-screen keyboard is STEAM+X, from the README controls table, which is labelled desktop only. The implementation is `src/deck_osk_layout.py` (grid, hit testing, two trackpad cursors) plus `src/deck_osk_tty.py` (console) and `src/deck_osk_wayland.py` (layer-shell). `stage_input_mapper` installs `deck-input-mapper.py` as a user service. It picks the device by `BTN_SOUTH` and opens `/dev/uinput`. The comment says Gaming Mode does not use it, because Steam takes the controller.

Password prompts: the design treats an SDDM greeter as a dead end, so autologin retries. The session switch does not prompt, because of the `NOPASSWD` sudoers line. `deck_form_pin_console_keymap` runs `loadkeys us` (`DECK_CONSOLE_KEYMAP=us`) while the installer keyboard is up, so a masked password is not typed under a different keymap. A polkit keypad inside a desktop dialog was not found in the files read for this note.

### Maintenance

Last commit: 2026-09-24, [`daa9376ab733880e612569467164754096a5f0f4`](https://github.com/villenull/Pizzarchy/commit/daa9376ab733880e612569467164754096a5f0f4), "v2: SD reboot check fixed in harness; docs for the v2 ISO (flow, microSD, name/email)". The GitHub repository metadata fetched the same day is not archived. Issue [#16](https://github.com/villenull/Pizzarchy/issues/16), "OS updates break 'Gaming Mode'", was opened 29 Oct 2026 and was still open with no comments when read on 16 Nov 2026. The body says Arch's `extra/gamescope` ships no session files, Valve's repos are appended last, and a plain `pacman -Syu` or `omarchy update` can replace Valve's gamescope so the Deck boots to the desktop. The workaround named there is `IgnorePkg = gamescope`. The same failure is already in `stage_valve_repos`: on 2026-09-17 an update replaced Valve's gamescope with Arch's build and the next boots could not find `gamescope-wayland.desktop`.

## 2. cephalization/omarchy-steam-gaming-mode

Repo: [cephalization/omarchy-steam-gaming-mode](https://github.com/cephalization/omarchy-steam-gaming-mode). One setup script. It adds a Steam Big Picture session on an existing Omarchy (or Arch + Hyprland) install. ([README](https://github.com/cephalization/omarchy-steam-gaming-mode/blob/b58f7b9cf5b837362c99d7656db95fd1ee3e5cea/README.md))

Licence: `MIT`. The LICENSE file is the MIT text, copyright (c) 2025 Tony Powell. No SPDX header. ([LICENSE](https://github.com/cephalization/omarchy-steam-gaming-mode/blob/b58f7b9cf5b837362c99d7656db95fd1ee3e5cea/LICENSE))

### Session start and return

`setup-gaming-mode.sh` function `create_gaming_script` writes `/usr/local/bin/switch-to-gaming`. That script reads the first Hyprland monitor with `hyprctl monitors -j`, kills any running Steam, stops `hypridle`, touches `~/.local/state/omarchy/toggles/screensaver-off`, and runs:

```
/usr/bin/gamescope --mangoapp -f -W "$WIDTH" -H "$HEIGHT" -r "$REFRESH" -e -- /usr/bin/steam -tenfoot
```

Gamescope is nested in the Hyprland session. `-f` is fullscreen. There is no `-steamos3`, no `-steamdeck`, and no separate login. `create_return_script` writes `/usr/local/bin/return-to-desktop`, whose body is `pkill -9 gamescope`. The README says return with Super+w, or by adding that binary as a non-Steam game. Super+F12 is written into `~/.config/hypr/bindings.lua` or `bindings.conf` by `add_hyprland_keybind`. A desktop file `~/.local/share/applications/gaming-mode.desktop` calls the same switch script. Emergency exit in the README is Ctrl+Alt+F2, then `pkill -9 gamescope`.

### Keyboard-free install, login, Wi-Fi, OSK, passwords

None of these are in the script or the README. The install is a shell script the user runs. The switch is a keyboard bind. There is no autologin, no Wi-Fi step, and no on-screen keyboard. The only password-adjacent behaviour is killing `hypridle` for the duration of the nested session, then starting it again from the EXIT trap.

### Maintenance

Last commit: 2026-07-05, [`b58f7b9cf5b837362c99d7656db95fd1ee3e5cea`](https://github.com/cephalization/omarchy-steam-gaming-mode/commit/b58f7b9cf5b837362c99d7656db95fd1ee3e5cea), merge of a Lua Hyprland keybind fix. GitHub repository metadata fetched 16 Nov 2026 marks the repository archived.

## 3. DeckShift

Announcement: [omacom/omarchy discussion #4534](https://github.com/omacom/omarchy/discussions/4534), "Omarchy STEAM DECK MODE", opened 7 Feb 2026 by 28allday. The post describes an installer that uses ChimeraOS gamescope-session packages, binds Super+Shift+S to launch and Super+Shift+R to shut down, refuses Intel-only graphics, and installs Steam plus gamescope. It says the Git link will come later and that the link is in the YouTube description. This note did not open the video, so that description is unverified.

Repo: [28allday/deckshift](https://github.com/28allday/deckshift). GitHub metadata fetched 16 Nov 2026 says it was created 6 May 2026, default branch `master`. The README's own lineage line says it was forked from Super-Shift-S-Omarchy-Deck-Mode, briefly renamed Omarchy Deck, then renamed DeckShift. The discussion does not contain the URL `github.com/28allday/deckshift`. The link is the same author, the same two binds, and that lineage sentence.

What it is: an installer for an already-installed Omarchy desktop. Version 0.2.3 in the README. Desktop Mode stays Hyprland. Gaming Mode is fullscreen Steam Big Picture inside Gamescope. A Quickshell plugin, `plugins/nosignal.deckshift`, is a bar icon and a panel for monitor, resolution, refresh and GPU. Launching Gaming Mode restarts SDDM. ([README](https://github.com/28allday/deckshift/blob/a46123426843a78ed6d5af22402f27c2554e5edb/README.md))

Licence: no licence. There is no LICENSE or COPYING file in the tree at [`a4612342`](https://github.com/28allday/deckshift/commit/a46123426843a78ed6d5af22402f27c2554e5edb). The README's licence section says "This project is provided as-is for the Omarchy community." That sentence is not a grant. The plugin `manifest.json` has `"license": "MIT"`. A field in one JSON file is not a LICENSE file for `deckshift.sh` or the QML. No licence = all rights reserved, can't reuse code.

### Session start and return

The comment above the session function in `deckshift.sh` (the block titled "SESSION SWITCHING") describes the flow:

1. Super+Shift+S in Hyprland.
2. `switch-to-gaming` points SDDM at the Gaming session.
3. SDDM restarts and autologins into that session.
4. `gamescope-session-nm-wrapper` starts performance tuning, NetworkManager, drive mounts and a keybind monitor, then Gamescope and Steam.
5. Super+Shift+R, or Steam's Switch to Desktop, runs the reverse.

The packages it tells the user to install from the AUR are `gamescope-session-git` and `gamescope-session-steam-git`. It expects these files once they are installed: `/usr/bin/gamescope-session`, `/usr/share/wayland-sessions/gamescope-session.desktop`, `/usr/bin/steamos-session-select`. `patch_gamescope_session_plus` edits `/usr/share/gamescope-session-plus/gamescope-session-plus` after install, because Arch's gamescope lacks `--custom-refresh-rates`. The scripts `switch-to-gaming` and `switch-to-desktop` are written by the installer. They are not separate files in the repo. This note did not extract those generated bodies line by line. The README's usage table is the user-facing contract: Super+Shift+S enters, Super+Shift+R returns, and Steam → Power → Switch to Desktop is the other return.

### Keyboard-free install, login, Wi-Fi, OSK, passwords

The installer is interactive and expects a keyboard. The binds are Super chords. Recovery from a black screen is Super+Shift+R, then a TTY with Ctrl+Alt+F2, then `loginctl terminate-user` or `sudo systemctl restart sddm`. There is no install-time on-screen keyboard and no autologin design for a machine with no keyboard. The README does not describe an on-screen keyboard.

Wi-Fi: the same function says Omarchy uses iwd, and Steam wants NetworkManager, so on gaming start it starts NetworkManager and on exit it stops it and starts iwd again. If iwd is active it writes `/etc/NetworkManager/conf.d/10-iwd-backend.conf` with `wifi.backend=iwd`.

Passwords: v0.2.3 exists because the passwordless sudoers rules for performance controls ended in `*` and matched extra arguments. The new rules allow only the exact commands. Re-running the installer replaces the old file. A password prompt during ordinary desktop polkit or at the greeter is not given a keyboard in anything read here.

### Maintenance

Last commit: 2026-10-31, [`a46123426843a78ed6d5af22402f27c2554e5edb`](https://github.com/28allday/deckshift/commit/a46123426843a78ed6d5af22402f27c2554e5edb), "v0.2.3 — security fix: stricter sudoers rules". Not archived in the metadata fetched the same day. This is the one project in the set with a commit in the last month.

## 4. deckarchy

Repo: [aorumbayev/deckarchy](https://github.com/aorumbayev/deckarchy). The README title is "Linux Neptune Kernel Setup". It is a script that runs after a vanilla Arch install and before Omarchy configuration. It detects a Steam Deck, adds Valve's repos, installs `linux-neptune-611`, and copies speaker firmware on OLED hardware. It is marked experimental and only tested on the Steam Deck OLED. The Omarchy manual's "Omarchy on…" page points at this script for the Steam Deck ([manual page](https://omarchy.org/manual/omarchy-on/)). The manual was fetched via search; this note did not re-read the live manual HTML beyond that index snippet.

Licence: `MIT`. The LICENSE file is the MIT text, copyright (c) 2025 Deckarchy. No SPDX header. ([LICENSE](https://github.com/aorumbayev/deckarchy/blob/a537556501758f08e8e1fc5fe7e94ce453da2834/LICENSE)) The README says `common-script.sh` is a modified helper from [ChrisTitusTech/linutil](https://github.com/ChrisTitusTech/linutil). That upstream LICENSE was not opened, so the helper's other obligations are unverified. The repo's own LICENSE still covers the files as they sit in this tree.

### Session start and return

There is no gamescope launch and no desktop return. `linux-neptune.sh` functions are `detectSteamDeck`, `setUpRepos`, `installKernel` and `copyFirmwareFiles`. `detectSteamDeck` matches `Jupiter` or `Galileo` in `/sys/class/dmi/id/product_name`. `setUpRepos` appends `[jupiter-staging]` and `[holo-staging]` with `SigLevel = Never` and the host `steamdeck-packages.steamos.cloud`. `installKernel` installs `linux-neptune-611`, headers, and on a Deck also `steamdeck-dsp`, `jupiter-staging/alsa-ucm-conf` and `linux-firmware-neptune`. Bootloader handling is GRUB (`grub-mkconfig`) or systemd-boot (`kernel-install`). If neither is present it prints an error and tells the user to configure the bootloader. Omarchy's x86 boot path on this branch is Limine (`docs/handheld/09-keyboard-free-boot.md`).

### Keyboard-free install, login, Wi-Fi, OSK, passwords

None. The documented install is `curl …/linux-neptune.sh | bash` from a shell, on a machine that already has Arch and sudo. The script sources `./common-script.sh` from the current directory, so the piped one-liner cannot see that file unless the repo has been cloned. That is visible from the first line of `linux-neptune.sh`. No login, Wi-Fi, on-screen keyboard or password UI.

### Maintenance

Last commit: 2025-08-19, [`a537556501758f08e8e1fc5fe7e94ce453da2834`](https://github.com/aorumbayev/deckarchy/commit/a537556501758f08e8e1fc5fe7e94ce453da2834), "Fix common script path in Neptune kernel installer". Not archived. No commit since. The AUR RPC search for `deckarchy` on 16 Nov 2026 returned `resultcount` 0 ([RPC](https://aur.archlinux.org/rpc/?v=5&type=search&arg=deckarchy)). A web search for the name on Reddit did not return a thread about this repo. Whether a thread exists that the search missed is unverified.

## 5. Comparison

What this branch already does, read from the tree, so the comparison is against code and not only against the specs:

| Piece | Where | What it does |
|---|---|---|
| Session supervisor | `bin/omarchy-session-start` | On an RC71L, runs gamescope in a user scope, or `uwsm start` for Hyprland. Gamescope command is `gamescope --backend drm -e --xwayland-count 2 --default-touch-mode 4`. One retry, then `desktop()`. |
| Steam | `bin/omarchy-gaming-steam` | `steam -steamos3 -steampal -steamdeck -gamepadui`. Puts `default/gaming/bin` on `PATH`. Writes `started` when Steam holds the X socket for `$DISPLAY`. |
| Switch to desktop | `default/gaming/bin/steamos-session-select` | Accepts only `plasma`, then execs `omarchy-launch-gaming-desktop`. The comment says it must not change SDDM policy. |
| Autologin | `bin/omarchy-handheld-autologin` `write_dropin` | Writes `Session=omarchy-handheld.desktop` and `Relogin=` into `/etc/sddm.conf.d/zz-omarchy-handheld.conf`. Does not write `User=`. Three misses in 60 s set `Relogin=false`. |
| First-boot autologin | `bin/omarchy-provision-owner` `configure_login` | Writes `User=` and `Session=omarchy.desktop` to `/etc/sddm.conf.d/autologin.conf`. An unencrypted install enables `omarchy-provision-autologin-once.service`, which deletes that file. |

Specs on top of that: [02](../02-mode-switch-and-dock.md) (separate sessions, Steam's Switch to Desktop, lock choke point, no SDDM restart as the switch), [03](../03-first-boot-and-install.md) (controller plus touch, TPM auto-unlock, buffyboard only after review), [09](../09-keyboard-free-boot.md) (autologin into the gamescope session that already ships).

### Reuse, where the licence allows

Pizzarchy is MIT, so its code can be adapted into this MIT tree if the copyright and permission notice travel with it. The pieces worth adapting are in the port list. They are small: a SteamOS update stub, a PATH check, an autologin drop-in that SDDM will actually apply, and the console-keymap pin for an installer keyboard.

cephalization is also MIT. Its nested gamescope launcher is the kind of session this branch already replaced. Adapting it would mean putting a fullscreen gamescope window inside Hyprland and leaving the desktop with `pkill -9`. Leave it.

deckarchy is MIT and is a Steam Deck kernel installer. The RC71L does not boot a Neptune kernel, and this branch's bootloader is Limine. Leave the script. `SigLevel = Never` on Valve's repos is not something to copy onto an Ally.

DeckShift has no licence. Ideas only. The ChimeraOS session packages it installs are someone else's project. This note did not re-read those packages' LICENSE files. [touch-first-boot.md](touch-first-boot.md) already records ChimeraOS `gamescope-session` as MIT. Depending on that package would be a separate decision, and it would still not make DeckShift's wrappers reusable.

### Ideas only

From DeckShift, and only as behaviour:

- Steam's own Power → Switch to Desktop is the return a controller user already knows. This branch's shim already does that, and it accepts the `plasma` argument Steam sends.
- A gamescope that Arch ships does not grow ChimeraOS flags by itself. DeckShift patches `gamescope-session-plus` for that reason. Our supervisor passes its own arguments and does not need that patch.
- Passwordless sudo that ends in `*` is a hole they had to fix in v0.2.3. Our rule is already the other way: turning `desktop-lock` off needs a real password prompt ([02 §7.4](../02-mode-switch-and-dock.md)).
- Restarting SDDM to change session drops the desktop, which their panel confirms before it does it. Our switch stays inside one login.

From DeckShift's Wi-Fi handoff: do not take it. This tree enables NetworkManager and disables `iwd.service` ([touch-first-boot.md](touch-first-boot.md) §5). Writing `wifi.backend=iwd` fights that.

On 23 Feb 2026 the same author wrote that a gamescope session launched as a nested Wayland compositor clamped the mouse in some games, and that the separate session is the one that feels like a Deck desktop ([comment](https://github.com/omacom/omarchy/discussions/4534#discussioncomment-15894110)). That matches why `bin/omarchy-session-start` uses `--backend drm` rather than a window inside Hyprland. A later comment, 3 Apr 2026, points at [28allday/Super-Shift-S-Omarchy-Deck-Mode](https://github.com/28allday/Super-Shift-S-Omarchy-Deck-Mode), not at `28allday/deckshift` ([comment](https://github.com/omacom/omarchy/discussions/4534#discussioncomment-16436805)).

### Where this branch is already ahead

| Area | What the others do | What this branch already has |
|---|---|---|
| Session | Pizzarchy restarts SDDM into Valve's Deck session. cephalization nests gamescope and kills it. DeckShift restarts SDDM into a ChimeraOS session. | One supervisor, a gamescope scope, a ready FIFO, one retry, then `desktop()`. Ally flags are `--default-touch-mode 4` and `--xwayland-count 2`. |
| Return | Pizzarchy and DeckShift rewrite SDDM autologin and restart the display manager. cephalization sends SIGKILL. | `steamos-session-select plasma` writes a return request. SDDM policy stays put. |
| Crash loop | Pizzarchy sets `Relogin=true` with no counted stop in the drop-in, then a boot helper that watches compositor PIDs. Its own comment says a gamescope with a wedged Steam looks the same as a healthy one. DeckShift's README has no counter. | Three misses in 60 s, judged by the ready FIFO, then the greeter. The open hole is which X socket counts as ready ([09](../09-keyboard-free-boot.md)). |
| Lock | None of the four mention a desktop lock on an autologin handheld. | `desktop()` in `bin/omarchy-session-start` is the choke point. `default-off` until the lock has a touch keyboard. |
| Device | All four are Steam Deck or a generic PC. deckarchy matches Jupiter/Galileo. | `bin/omarchy-hw-rog-ally`. InputPlumber is the chosen owner ([buttons-and-input.md](buttons-and-input.md)). `bin/omarchy-gaming-input-profile` loads `gaming` from `default/inputplumber/profiles/gaming.yaml` when the profile service is active ([ALPHA.md](../ALPHA.md)). |
| Wi-Fi backend | Pizzarchy's installer talks to iwd. DeckShift swaps iwd and NetworkManager per session. | NetworkManager stays, `wpa_supplicant` stays, iwd stays disabled. |

## Does any of this make our work redundant?

**Session start.** No. Nobody in this set supervises an Ally gamescope scope, waits on a Steam ready signal, retries once, and falls into `desktop()`. Pizzarchy autologins into a session file that Arch's gamescope does not ship. cephalization starts a nested window. DeckShift restarts SDDM into ChimeraOS's session, and its wrappers cannot be copied. deckarchy never starts gamescope.

**Mode switch.** No. The useful idea is already ours: Steam calls `steamos-session-select plasma`, and the desktop comes back without a second product. Their switches restart SDDM, or kill gamescope with SIGKILL. Ours stays in the login and does not rewrite SDDM.

**Autologin.** No. Pizzarchy is the closest, and it shows a hole we still have: `write_dropin` omits `User=`, and `configure_login` deletes `autologin.conf` on an unencrypted install. Their drop-in is also the wrong shape for us, because `Relogin=true` there has no three-failure stop and the session name is `gamescope-wayland`. The Ally autologin work remains.

**Touch-first boot.** No. Pizzarchy is a Deck OLED ISO with trackpads, an installer keyboard, encryption forced off, and a boot into Gaming Mode. That is the right shape of product, on the wrong device, with an input model the Ally does not have. The other three assume a keyboard at install or at the switch. Greeter submit, the polkit keypad, and the Ally first-boot wizard are still this branch's work ([09](../09-keyboard-free-boot.md), [03](../03-first-boot-and-install.md)).

**Input.** No. Pizzarchy's mapper is a second uinput owner, aimed at a Steam Deck gamepad and two trackpads. This branch already chose InputPlumber and refuses a second grabber. cephalization, DeckShift and deckarchy do not map the Ally's composite device.

## Port list for dev-blue

Licence gate used here. MIT, BSD and Apache can be adapted into this tree with the copyright and permission notice kept. GPL stays a separate package. No licence means the code stays out. DeckShift is the last of those, so it has no row.

Pinned commits:

| Project | SHA | Tree |
|---|---|---|
| Pizzarchy | [`daa9376ab733880e612569467164754096a5f0f4`](https://github.com/villenull/Pizzarchy/commit/daa9376ab733880e612569467164754096a5f0f4) | 2026-09-24 |
| cephalization/omarchy-steam-gaming-mode | [`b58f7b9cf5b837362c99d7656db95fd1ee3e5cea`](https://github.com/cephalization/omarchy-steam-gaming-mode/commit/b58f7b9cf5b837362c99d7656db95fd1ee3e5cea) | 2026-07-05 |
| deckarchy | [`a537556501758f08e8e1fc5fe7e94ce453da2834`](https://github.com/aorumbayev/deckarchy/commit/a537556501758f08e8e1fc5fe7e94ce453da2834) | 2025-08-19 |

Attribution that has to travel with any adapted Pizzarchy file. The LICENSE file is the whole notice below. The condition in it is that the copyright line and the permission notice stay with the copy. Keep the disclaimer with them.

```
Copyright (c) 2026 Diego Huyke

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

cephalization, if a later change does adapt it: copyright (c) 2025 Tony Powell, plus the same MIT permission paragraph from that repo's LICENSE. deckarchy: copyright (c) 2025 Deckarchy, same paragraph. Do not adapt either of those two.

### Adapt these

Priority is Steam-ready and session start, then keyboard-free login, then the rest. The rest produced no row that should be adapted.

| # | Piece | Upstream, at the SHA above | SPDX | Our files | Notes |
|---|---|---|---|---|---|
| 1 | SteamOS update stub, so Gaming Mode first-run does not stop on a fake network error or reboot | [`src/deck-session.sh`](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/src/deck-session.sh) `render_update_stub`, `stage_update_stub`. Installed path in that script: `/usr/bin/steamos-polkit-helpers/steamos-update` (`UPDATE_STUB`). Verbs: `check` exits 7, `apply` and no argument exit 7, `--supports-duplicate-detection` exits 1, `help` exits 0, an unknown verb exits 7. Exit 0 on `apply` is what they measured as a reboot. | MIT | New file, installed to that absolute path by the gaming session package. Steam calls the path itself. Does not replace `bin/omarchy-session-start` or `bin/omarchy-gaming-steam`. Those two stay the launcher. | Their help text says `sudo pacman -Syu` (`REAL_UPDATE_HINT`). DeckShift's README says Omarchy blocks a direct `pacman -Syu` and its installer runs `omarchy update`. This tree's command is `bin/omarchy-update`. Use that in the help text. Header must say the stub updates nothing. Their generated shebang is `#!/usr/bin/env bash`. The adapted script uses `#!/bin/bash`. Keep the Pizzarchy notice on the file. |
| 2 | Proof that Steam can see `steamos-session-select` | Same file, `stage_steam_hook`. Constants `STEAM_SHIM=/usr/bin/steamos-session-select`, `STEAM_SHIM_LEGACY=/usr/local/bin/steamos-session-select`, `STEAM_RUNTIME_PATH=/usr/bin:/bin`. The check is `env -i PATH="$STEAM_RUNTIME_PATH" sh -c 'command -v steamos-session-select'`. | MIT | `bin/omarchy-gaming-steam` (it prepends `default/gaming/bin` to `PATH` before `steam`). `default/gaming/bin/steamos-session-select` stays the shim. | Do not copy `render_steam_shim`. That shim is `exec sudo -n` into a root writer, and its shebang is `#!/usr/bin/env bash`. Ours accepts `plasma` and execs `omarchy-launch-gaming-desktop`, and its comment says it must not change SDDM. Their PATH finding was read from a Deck Steam process. On the Ally, confirm Steam's environ before moving the shim to `/usr/bin`. If the parent `PATH` survives, leave the private directory. |
| 3 | Autologin drop-in SDDM will apply | [`deck_autologin.py`](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/iso/overlay/configs/airootfs/usr/share/omarchy-iso/orchestrator/deck_autologin.py) `render_dropin`, `parse_autologin`, `write_dropin`, `assert_sorts_last`, `configure_autologin`. Drop-in name there: `zz-deck-session.conf`. | MIT | `bin/omarchy-handheld-autologin` function `write_dropin`. `bin/omarchy-provision-owner` functions `configure_login` and `install_autologin_once_cleanup`. | `write_dropin` writes `Session=` and `Relogin=` and omits `User=`. `configure_login` writes `User=` into `autologin.conf` with `Session=omarchy.desktop`, and the unencrypted path deletes that file on the next boot. Put `User=<installer-created user>` in a file `apply` does not replace. Keep our session name `omarchy-handheld.desktop`. Keep our `Relogin=false` after three misses. Their `render_dropin` hard-codes `Relogin=true` and `gamescope-wayland`. `parse_autologin` is the check to lift: a `User=` outside `[Autologin]` does not count. Do not guess the user at runtime ([02 §7.1](../02-mode-switch-and-dock.md)). |
| 4 | Console keymap pinned to the installer keyboard while a password is masked | [`deck-form.sh`](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/iso/overlay/configs/airootfs/usr/share/omarchy-iso/deck-form.sh) `deck_form_pin_console_keymap`, constant `DECK_CONSOLE_KEYMAP=us`. | MIT | `install/provisioning/setup-form.sh`, and only if a console on-screen keyboard is still the first-boot plan. Spec 03 already requires `us` for the whole account screen while buffyboard is up. | The function runs `loadkeys`. A failed `loadkeys` has to be loud, because the password field is masked. Their comment distinguishes the live console keymap from the installed `kb_layout`. Keep that split. Do not copy the trackpad keyboard around it. |

### Licence allows a copy. Leave them.

| Piece | Upstream | SPDX | Why it stays out | Our files it would have collided with |
|---|---|---|---|---|
| SDDM rewrite and `NOPASSWD` sudoers | `stage_session_select`, generated `deck-session-select`, unit that restarts `sddm.service`, `/etc/sudoers.d/99-deck-session-select` | MIT | Restarts the display manager and grants passwordless root for the switch. Spec 02 keeps the switch inside one login, and `desktop-lock off` needs a real password. | `bin/omarchy-session-start`, `default/gaming/bin/steamos-session-select`, `bin/omarchy-launch-gaming-desktop` |
| Boot re-assert by compositor PID | `render_boot_default_helper`, `stage_boot_default_gaming`, unit `deck-boot-default-gaming.service` | MIT | The helper's own comment says it cannot tell a wedged Steam from a live gamescope. Our stop is the ready FIFO, three times in 60 s. | `bin/omarchy-handheld-autologin`, `bin/omarchy-session-start` |
| Valve repos and Valve's gamescope session | `stage_valve_repos`, `GAMESCOPE_VALVE_SPEC=jupiter-staging/gamescope`, `SigLevel = Never` | MIT | Deck session files, Deck firmware repos, and a package-name overlap the script itself warns about. Arch gamescope plus our own arguments is the Ally session. | `bin/omarchy-session-start`, `bin/omarchy-gaming-steam` |
| Deck input mapper and trackpad OSK | `stage_input_mapper`, [`src/deck-input-mapper.py`](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/src/deck-input-mapper.py), [`src/deck_osk_layout.py`](https://github.com/villenull/Pizzarchy/blob/daa9376ab733880e612569467164754096a5f0f4/src/deck_osk_layout.py), `src/deck_osk_tty.py`, `src/deck_osk_wayland.py` | MIT | Second uinput owner. Two trackpad cursors. The Ally has a touchscreen and sticks. InputPlumber stays the owner. Desktop OSK stays wvkbd. Greeter OSK stays Qt Virtual Keyboard. `default/rog-ally-input/bridge.py` is named in [docs/handheld/README.md](../README.md) and is not a file on this tip. | `bin/omarchy-gaming-input-profile`, `bin/omarchy-toggle-desktop-keyboard`, `bin/omarchy-setup-rog-ally-keyboard`, `default/sddm/omarchy/Main.qml` |
| Installer Wi-Fi via iwd | `deck_form_parse_iwctl_networks` in `deck-form.sh`. `carry_wifi` and `install_first_boot_unit` in `deck_wifi.py` | MIT | Talks to `iwctl`. This tree disables `iwd.service`. The parser comment says the columns were inferred. | `install/hardware/network.sh`, `install/provisioning/setup-form.sh` |
| Nested gamescope toggle | `create_gaming_script`, `create_return_script`, `add_hyprland_keybind` in [`setup-gaming-mode.sh`](https://github.com/cephalization/omarchy-steam-gaming-mode/blob/b58f7b9cf5b837362c99d7656db95fd1ee3e5cea/setup-gaming-mode.sh). Return is `pkill -9 gamescope`. Bind is Super+F12. | MIT | Nested fullscreen client. No separate login, no ready signal, no Ally target. Repository is archived. | `bin/omarchy-session-start` |
| Neptune kernel installer | `detectSteamDeck`, `setUpRepos`, `installKernel`, `copyFirmwareFiles` in [`linux-neptune.sh`](https://github.com/aorumbayev/deckarchy/blob/a537556501758f08e8e1fc5fe7e94ce453da2834/linux-neptune.sh) | MIT | Jupiter/Galileo only. GRUB or systemd-boot. `common-script.sh` is derived from LinUtil and that upstream licence was not read. Last commit 2025-08-19. | No session file. Would fight Limine and `bin/omarchy-hw-rog-ally`. |
| Timezone helper | `stage_timezone_helper`, `render_timezone_helper`. Installed path `/usr/bin/steamos-polkit-helpers/steamos-set-timezone` (`TIMEZONE_HELPER`). Sudoers `/etc/sudoers.d/99-deck-set-timezone` is `NOPASSWD` for `timedatectl set-timezone *`. | MIT | Steam's OOBE picker calls that absolute path. The grant is the part that makes it work, and the trailing `*` is the shape their own comment cites from an Omarchy sudoers bug. Spec 02 does not add passwordless root for a session feature. Without the grant the helper does not answer the picker, so there is nothing left to adapt. | No timezone command in this tree. Do not add the sudoers file. |
| Brightness writer | `stage_priv_write_helper`, `render_priv_write_helper`. Installed path `/usr/bin/steamos-polkit-helpers/steamos-priv-write`. Sudoers `/etc/sudoers.d/99-deck-priv-write`. | MIT | A second root writer for sysfs, behind `NOPASSWD` on that one binary. Brightness on this branch is not that helper. | Do not add the helper. Power work stays with the Ally powerbutton package and `bin/omarchy-session-start`'s existing TDP-shim restart. |

DeckShift's `deckshift.sh`, `uninstall.sh`, and `plugins/nosignal.deckshift/` are not in either table. No LICENSE file, so the code stays where it is. The behaviour notes are in §5.

## Ported from Pizzarchy

The four rows in "Adapt these" are adapted on this branch, not pasted. The copyright line, the permission notice and the disclaimer from Diego Huyke's MIT licence stay on each adapted file. Pizzarchy commit `daa9376ab733880e612569467164754096a5f0f4`.

| Piece | Where it landed | What changed from upstream |
|---|---|---|
| Update stub | `default/gaming/steamos-update`, installed only by `packages/omarchy-gaming-session` to `/usr/bin/steamos-polkit-helpers/steamos-update` | `#!/bin/bash`. Help says `omarchy update`. The stub updates nothing. Exit 0 is only help, so apply cannot reboot the machine. Core does not copy it into `/usr/bin`. |
| PATH probe | `default/gaming/steam-path.sh`, called from `bin/omarchy-gaming-steam` | The `env -i PATH=/usr/bin:/bin` check. The private shim stays. A parent PATH that still contains it, a missing environ, or a shim already on that PATH does not install `/usr/bin/steamos-session-select`. The sudo shim was not copied. |
| `User=` | `default/gaming/sddm-user.sh`, path `/etc/sddm.conf.d/omarchy-handheld-user.conf` | The installer writes it from `configure_login`. The name is that account, so the file is not a package payload. The gaming-session scriptlet copies the installer record only when no `[Autologin] User=` is counted, and only on an Ally with the package. `parse_autologin` ignores a `User=` outside `[Autologin]`. After `autologin.conf` is gone, `[Last] User=` in SDDM's state is the same installer record. apply does not write `User=` while the variant is installed, and deletes the file when the variant is gone. `pre_remove` and `post_remove` delete it too. No second file. |
| Console keymap | `omarchy_form_pin_console_keymap` in `install/provisioning/setup-form.sh` | Live console only, and only while `OMARCHY_FORM_CONSOLE_OSK=1` on an Ally VT. The installed `$keyboard` layout is not changed. A failed `loadkeys` is loud because the password is masked. |

The SDDM rewrite, the timezone helper and the brightness writer were not ported. The `fail` / `reset` / `apply` grant ships in `packages/omarchy-gaming-session`, not in the base `etc/sudoers.d` tree.
