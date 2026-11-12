# 03 · First boot and install flow (handheld variant)

Status: draft, revision 1, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (profiles, OSK), [02](02-mode-switch-and-dock.md) (session supervisor, autologin, fallback). Lock-screen, greeter and disk-unlock **UI** are AUTH's; this spec lists only the requirements it places on them (§8).

**Desktop lock (lead ruling, 12 Nov 2026; spec 02 D10 revision 2).** AUTH K07, the lock-screen touch keyboard, lands as an additive PR on `feat/ally-parity-release-20261111`. The handheld variant is `omarchy-hw-rog-ally` and the `omarchy-gaming-session` package together. Marker path, ownership, who writes the marker, and how a read error is treated are [spec 02 §7.4](02-mode-switch-and-dock.md). This spec does not restate them. `default-off` is written only by a fresh install that chose the handheld variant, and only when §7.4 says the marker is absent. Adding `omarchy-gaming-session` to an existing desktop-only install writes `on` explicitly, so that desktop does not come up unlocked. `default-off` is not `explicit-off`. OQ-2 is resolved by this ruling.

**Review flag for dev-red.** AUR `buffybox` (split package `buffyboard`) is proposed for the first-boot keyboard and is not a reviewed package. It stays out of the package set until dev-red accepts §3.1. `wvkbd` 0.21-1 is the comparison: that package is already reviewed (`bin/omarchy-setup-rog-ally-keyboard` on this branch).

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | The whole install is doable with **controller + touchscreen**, no USB keyboard, for the default path (whole internal disk, no dual boot, no encryption, §4). Anything that needs a keyboard is marked so on screen before the user commits. | Brief; Bazzite/CachyOS gaps (§2) |
| D2 | Reuse Omarchy's existing TUI form and **deferred provisioning**: the ISO only picks the disk and installs; user, password, Wi-Fi and timezone are asked on **first boot** by `omarchy-provision-owner`, using the same `install/provisioning/setup-form.sh`. No second installer. | Baseline (§1) |
| D3 | Keyboardless input in the TUI = **InputPlumber `tty` profile** (controller → arrows/Enter/Esc/Tab/Backspace). `buffyboard` is the touch keyboard on **first boot only**, and only under §3.1. It does not run on the live ISO, and it is stopped before SDDM starts. | New (Δ-I1, Δ-I2); dev-red review, 12 Nov 2026 |
| D4 | `omarchy-hw-rog-ally` **preselects** the handheld variant on RC71L; the user can still choose “Desktop only”. Other handhelds get no automatic variant yet. | This branch (same file as PR #3), P2 |
| D5 | Password is **mandatory**, asked once (confirm field). Gaming Mode does not ask for it. `sudo` needs it. Unlock needs it only once `desktop-lock` is on (D7). The screen says so. | Daniel, 12 Nov; lock timing from the ruling above |
| D6 | After the wizard the handheld variant **autologins into gaming**; failure falls back to desktop (spec 02 D1/D2). | Daniel's decision, 12 Nov 2026. SESSION sign-off comes through dev-red's review. |
| D7 | `desktop-lock` is root-owned. When the effective value is `on`, it is enforced at **one choke point**: `desktop()` in `bin/omarchy-session-start`, before `uwsm start`, the first frame and autostart. It **fails closed** (back to gaming while a spec 02 D2 retry remains, otherwise to SDDM). `off` stores `explicit-off` and needs an interactive password prompt, never a passwordless polkit rule. `on` needs no password. `default-off` is written only for a fresh handheld-variant install, and only while spec 02 §7.4 says the marker is absent. A later install of `omarchy-gaming-session` on a desktop-only machine writes `on`. | Lead ruling, 12 Nov 2026; spec 02 §7.4 |
| D8 | First-boot wizard steps: Wi-Fi → controller test → InputPlumber enable → MCU firmware check (warn < 319) → `asusctl`/`asusd` check (kept off RC71L) → Steam sign-in hand-off. Each step is skippable except Wi-Fi-or-confirm-offline; none is hold-only. | Brief |
| D9 | Disk encryption is **off by default** on the handheld variant and offered as an explicit opt-in with a “needs a USB keyboard at every boot” warning until a touch unlock ships (AUTH K11). | Baseline K11 (§1), OQ-1 |
| D10 | Red-team rules: every input-profile hand-over sends explicit key-ups and waits for the new target; any failure drops **atomically** to the firmware gamepad / plain `tty` mapping; prompts ignore controller input for 500 ms and default to the safe choice. | Red review, 12 Nov |

## 1. Baseline: what is already built

Paths below were checked on `feat/ally-parity-integration-20261111` (`bbc819047`) and on the `feat/ally-*-20261111` branch that actually contains the file.

| Area | What exists (branch / path) | Constraint for this spec |
|---|---|---|
| Setup form | `install/provisioning/setup-form.sh` (this branch). `bin/omarchy-provision-owner` sources it. gum prompts for keyboard, username, password + confirm, hostname (empty ⇒ `omarchy`, `OMARCHY_HOSTNAME_DEFAULT`), timezone (`geo.omarchy.org`, else `OMARCHY_FORM_TIMEZONE_FALLBACK`, else the full `timedatectl` list in `gum filter`). Shared by the ISO configurator and first-boot setup “so the copies cannot drift”. Exit codes: 0 next, 1 Esc = unwind to the start of the form, 130 Ctrl+C = caller side channel (ISO: arm deferred provisioning or toggle encryption; first boot: offer a reboot). | Keep one form. Add handheld behaviour by caller variables, not a fork. Never map any controller button to **Ctrl+C**. |
| Deferred provisioning | `install/provisioning/omarchy-provision-owner.service`: runs `/usr/bin/omarchy-provision-owner` on **tty1 before `display-manager.service`**, armed by `/var/lib/omarchy/provisioning/pending`; blocked while `/var/lib/omarchy/provisioning/wipe-pending` exists. | Our wizard rides on this unit (Δ-P1). |
| Disk key | `install/provisioning/luks-rekey.sh`: resumable re-key from a staged install key to the owner's password. The journal records phase, slot numbers and a layout fingerprint, never key material. Boot-time unlock is the caller's `luks_auto_unlock_present` / `luks_auto_unlock_drop`. | Encryption opt-in reuses it; boot unlock still needs a keyboard (K11). |
| Login | `install/login/sddm.sh`: “The ISO owns autologin/session state because it knows whether the target is encrypted.” | Handheld autologin is written by the ISO/provisioning, not at runtime (spec 02 §7.1). |
| RC71L detection | `bin/omarchy-hw-rog-ally` (this branch; same file as PR #3, `cursor/rog-ally-rc71l-3178`): vendor `ASUSTeK COMPUTER INC.` and product `ROG Ally RC71L*` or board `RC71L`; excludes Ally X/Xbox Ally. | Single detector for ISO + installed system. |
| asusctl | `install/hardware/asus-rog.sh`: `asusctl` only if `omarchy-hw-asus-rog && ! omarchy-hw-rog-ally`. `install/hardware/asus/rog-ally.sh`: runs offline on an image's first boot, “never prompt or install a handheld control daemon here”. | Wizard must not install from the offline hardware leaf; it runs later (online, owner known). |
| First-run hooks | `install/user/first-run/wifi.sh` waits for NetworkManager (`nm-online`), then runs `install/user/first-run/setup-rog-ally.hook`. The hook posts one critical notification. The action is `omarchy-setup-gaming` when that command is present, otherwise `omarchy-menu summon install.gaming`. | Replaced on the handheld variant by the wizard (Δ-W3); kept for desktop-only installs. |
| Handheld hub | `bin/omarchy-setup-rog-ally` (`feat/ally-recovery-20261111` and `feat/ally-parity-release-20261111`; **not** on this branch): menu for Status, Controller input, Power setup, Gaming session, Display and touch layout, Game software, Desktop keyboard, Game libraries, Update and recovery. | Wizard steps call the same backends; the hub stays the “redo later” place. |
| Input enable | `bin/omarchy-setup-rog-ally-input --enable` (`feat/ally-input-20261111`): needs reviewed companion `omarchy-rog-ally-input 1.0.3-1` and `inputplumber ≥ 0.84.0`. Refuses competing owners `hhd`, `handheld-daemon`, `input-remapper`, `xboxdrv`, `chimera` and `opengamepadui`. Does not install packages. The hub runs it in a visible terminal. | Wizard step = same command, same refusals; consent screen replaces the terminal. |
| Gaming session | `docs/rog-ally-gaming-session.md` is on this branch and already records Daniel's autologin decision and handheld `default-off`. The commands `bin/omarchy-setup-gaming-session` and `bin/omarchy-session-start`, and `default/gaming/wayland-sessions/omarchy-handheld.desktop`, are on `feat/ally-session-20261111`. That command's help still says password sign-in is retained. Recovery latch is `$XDG_STATE_HOME/omarchy/gaming-session/recovery` (default `$HOME/.local/state/...`). The 60 s deadline is Gamescope starting its Steam child, not Steam's UI finishing. `desktop()` calls `uwsm start` and does not lock today. `default` accepts only `desktop`, `gaming` or `last`. There is no `auto` value and no `desktop-lock` argument yet. | The doc on this branch matches D6 and D7. SESSION still has to add `auto`, `desktop-lock`, and the choke point in `desktop()`. |
| Auth | `docs/rog-ally-authentication.md` (`feat/ally-auth-20261111`): SDDM greeter has Qt Virtual Keyboard (K06/K08/K09). The integrated lock has **no** touch keyboard; wvkbd cannot unlock it. K07 is a separately stageable, opt-in trusted lock host on that branch, not activated. K11 (LUKS touch) is investigated only (`unl0kr` / `sd-unl0kr`, AUR `buffybox`). Lock-state feed: `$XDG_RUNTIME_DIR/omarchy-lock-$HYPRLAND_INSTANCE_SIGNATURE.sock`, one JSON line `{"locked":true}` or `{"locked":false}`. | §8 and D7. Marker rules are spec 02 §7.4. `default-off` is only a fresh handheld-variant install. |
| Power | `docs/rog-ally-power.md` (`feat/ally-power-20261111`): **do not install `steamos-manager 26.4.1-3`**. Ordinary machines keep power-profiles-daemon. | Installer must not pull `steamos-manager` or CachyOS `cachyos-handheld`. PPD is masked only when the handheld variant and [backlog #10 (power writer)](tdp-decision-review.md) are both installed, and that mask is recorded. The handheld pair alone does not mask it. A desktop-only RC71L keeps PPD. [backlog #11 (Steam TDP shim)](tdp-decision-review.md) is the shim. Spec 04. |
| Hardware | `docs/handheld/research/ally-hw-dump.md` (this branch): kernel line `The MCU firmware version must be 319 or greater to avoid issues with suspend.` (`hid-asus.c` `validate_mcu_fw_version`, `ROG_ALLY_MIN_MCU 319`) means MCU < 319; `mcu_powersave`=0; `asusd` running. | MCU and asusd steps have real targets on Daniel's unit. |

## 2. How others do it

| | Bazzite (Deck images) | SteamOS 3.7/3.8 | CachyOS Handheld | Omarchy handheld (this spec) |
|---|---|---|---|---|
| Installer | Anaconda; pick the `-deck` image at download ([install guide](https://docs.bazzite.gg/General/Installation_Guide/install-guide/)) | Recovery image, “Wipe Device & Install”, no questions ([Valve recovery](https://help.steampowered.com/en/faqs/view/1B71-EDF2-EB6D-2BB3)) | Calamares in a KDE live session, Erase Disk advised ([wiki](https://wiki.cachyos.org/installation/installation_handheld/)) | Omarchy ISO, disk only; owner setup on first boot |
| Keyboardless? | Touch works; **no OSK in installer** for custom user, manual partitioning or MOK ([#715](https://github.com/ublue-os/bazzite/issues/715), [#1463](https://github.com/ublue-os/bazzite/issues/1463)) | Yes (nothing to type until Steam) | Touch + Maliit OSK in live session ([CachyOS-Handheld TODO #9](https://github.com/CachyOS/CachyOS-Handheld/issues/9)) | Controller on the ISO. Buffyboard on first boot only, after dev-red accepts §3.1 |
| Detection | Image choice | Device TOML in steamos-manager | `chwd` DMI profiles, RC71L board match ([profiles.toml](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml)) | `omarchy-hw-rog-ally` preselect |
| User / password | Default account ok; custom needs keyboard | `deck` user, **no password** until `passwd` in Desktop Mode ([guide](https://survivalconfigs.com/reference/steamos/install-steamos)) | User + password typed in Calamares | Mandatory password, explained |
| Encryption | Optional; “you will need a physical USB keyboard to decrypt” ([guide](https://docs.bazzite.gg/General/Installation_Guide/install-guide/)) | None | Optional; keyboard or manual `unl0kr` ([guide](https://discuss.cachyos.org/t/guide-luks-touchscreen-on-steam-deck-running-cachyos-handheld-edition-unl0kr/20293)) | Off by default, opt-in with warning |
| First boot | Steam Gaming Mode autologin (SDDM `zz-holo-autologin.conf`) | OOBE: language → Wi-Fi → timezone → Steam sign-in → update | Plasma Login autologin into gamescope; Steam downloads (≤ 2 min) | Wizard → autologin gaming |

Take: SteamOS's “type nothing until Steam” flow is the bar; Bazzite and CachyOS both trip on typing. Omarchy must type user + password, so it needs a real OSK in the TUI.

## 3. Input on install media and first boot (Δ-I1, Δ-I2)

The xpad pad sends gamepad events, not keys, so a TTY ignores it. Both stages use:

| Layer | Spec |
|---|---|
| Controller | InputPlumber started for the stage with a new **`tty` profile** (keyboard target only). Loaded only while `omarchy-hw-rog-ally` and the stage is running. |
| Touch / text | `buffyboard` (BuffyBox, AUR `buffybox`, split package `buffyboard` only, not `unl0kr`; [README](https://gitlab.postmarketos.org/postmarketOS/buffybox)): framebuffer touch keyboard, sends keys through uinput, resizes the VT. First boot only (§3.1). **Not reviewed.** |
| Physical keyboard | Always works in parallel (hotplug). |

`tty` profile map (built from spec 01 `desktop.yaml`, mouse targets removed):

| Button | Key | Note |
|---|---|---|
| D-pad / left stick | Arrows | Stick with 0.5 deflection threshold, auto-repeat 400 ms then 80 ms |
| A | Enter | Select / next |
| B | Esc | Back (form status 1 = back to start of form; that is acceptable and documented on screen) |
| X | Backspace | Text fields |
| Y | Tab | |
| Menu (Start) | Enter | |
| View (Select) | Nothing | Buffyboard has no show/hide control. The stage unit starts and stops the process (§3.1). |
| LB / RB | Page Up / Page Down | gum lists paginate |
| AC tap / CC tap | Nothing | No Omarchy menu exists here |
| Any | **Never Ctrl+C**, never Super | Ctrl+C is the form's side channel |

| Rule (red team) | Spec |
|---|---|
| Hand-over | Leaving the stage: send key-up for every key the profile holds, wait for InputPlumber to report the next target ready (D-Bus, ≤ 2 s), then load the next profile (spec 02 §8 gaming entry). |
| Daemon killed | If InputPlumber exits mid-form: firmware xpad pad returns (no keys). The form must still be finishable by touch: buffyboard has arrows, Enter, Esc, Tab. The **stage's own** unit restarts InputPlumber and reloads `tty`. The existing `Restart=on-failure` is on `default/rog-ally-input/omarchy-rog-ally-input.service` (`feat/ally-input-20261111`), the desktop bridge (`graphical-session.target`, Hyprland only). It does not run on tty1 and is not InputPlumber's unit. |
| Boot race | Form starts only after the composite device is on D-Bus (≤ 10 s, signal-driven) or the timeout passes; on timeout show “Controller not ready — use the touchscreen” and continue. |
| Unknown device | No `omarchy-hw-rog-ally` ⇒ no `tty` profile, no buffyboard; ordinary keyboard install. |

### 3.1 buffyboard, if dev-red accepts it

`buffyboard` stays out of the package set until every condition here is met. It is GPL-3.0-or-later. It is not K07 and it is not K11. Do not install the `unl0kr` split. It must not become the lock-screen keyboard or the disk-unlock keyboard.

1. It runs only as a child of first-boot provisioning (`BindsTo` and `PartOf` `omarchy-provision-owner.service`). It is stopped before `display-manager.service`. It is never a standalone enabled unit. It does not run on the live ISO and it does not keep running into SDDM, Gamescope or the lock.
2. It runs as root. It is not granted to a user, and uinput, input and tty access are not granted to a user or to the `input` group.
3. While it is up, the vconsole keymap is forced to `us`. The wizard still skips the layout step and takes the language default, but the keys buffyboard sends are US scancodes, so the stored password has to match that layout. When buffyboard stops, the language keymap is restored.
4. The shipped layout has no Ctrl, no Alt and no F-keys. It cannot send Ctrl+C (the form's 130 side channel) or an Alt+Fn VT switch.
5. Upstream resets the VT size only on SIGINT and SIGTERM. The stage unit's `ExecStopPost` resets the console size, including after SIGKILL.
6. Start and stop are the stage unit. There is no in-process show/hide. The unit starts buffyboard for a text field and stops it when that field is left.
7. Pin the version and the checksums. Review the PKGBUILD diff on every bump, the same way `wvkbd` 0.21-1 is pinned.

## 4. Install media flow (ISO)

| Step | Screen (gum, Omarchy styling) | Default (safe) | Keyboard needed? |
|---|---|---|---|
| 1 | Boot: hold **Volume Down + Power** for the boot menu ([Bazzite guide](https://docs.bazzite.gg/General/Installation_Guide/install-guide/)), pick USB | — | No |
| 2 | Language | From firmware locale / English | No |
| 3 | “ROG Ally detected” — **Handheld (Gaming Mode)** / Desktop only | Handheld | No |
| 4 | Disk: internal NVMe only listed; microSD and USB hidden behind “Show other disks” | Internal NVMe | No |
| 5 | Erase confirm: “Everything on <model, size> will be erased.” Erase / Back | **Back** focused; input ignored 500 ms | No |
| 6 | Encryption: Off / On (“needs a USB keyboard at every boot”) | **Off** (D9) | Only if On |
| 7 | Install progress (`install/provisioning/progress-icon.sh`); writes `/var/lib/omarchy/provisioning/pending`, `/etc/omarchy/variant` = `handheld` | — | No |
| 8 | “Remove the USB drive” → reboot | — | No |

Out of scope keyboardless: dual boot / manual partitioning (Advanced, labelled “keyboard recommended”), Secure Boot key enrolment.

Packages for the handheld variant (installed at step 7, from repos already used by Omarchy): `inputplumber` (Arch extra) + reviewed `omarchy-rog-ally-input`, `gamescope`, `steam` (multilib), `omarchy-gaming-session`, `wvkbd` (reviewed 0.21-1), `qt6-virtualkeyboard`, and `buffybox` **only after dev-red's review**. **Not**: `asusctl`, `steamos-manager`, `cachyos-handheld`, `jupiter-hw-support`, `hhd`, Decky. Installing a package never enables its service; the wizard does (§5).

## 5. First-boot wizard (tty1, before SDDM)

Runs inside `omarchy-provision-owner` (Δ-P1). One step per screen; footer always shows `A Select · B Back · View Keyboard`.

| # | Step | What it does | Skip? | Fail-safe |
|---|---|---|---|---|
| W1 | Account | `omarchy_prompt_username`, then **password screen** (§6), hostname (empty ⇒ `omarchy`). Keyboard layout step **skipped** on handheld (default from language; `OMARCHY_FORM_KEYBOARD_DEFAULT`). | No | Validation as baseline (reserved names, mismatch, blank) |
| W2 | Wi-Fi | List SSIDs (NetworkManager), pick, password via buffyboard; Ethernet auto. Comes **before** timezone so the geo guess works. | “Continue offline” (confirm: Steam needs internet on first start) | 30 s scan timeout ⇒ retry / offline |
| W3 | Timezone | `omarchy_prompt_timezone` (geo guess first; `gum filter` type-to-search via buffyboard) | No (Enter takes the guess when there is one) | No network and no `OMARCHY_FORM_TIMEZONE_FALLBACK` ⇒ full zone list, nothing leading it |
| W4 | Controller test | Live view: each button lights when pressed (incl. AC, CC, M1/M2 if present), sticks, triggers. Records which raw codes arrived (feeds spec 01 OQ-1). | Yes | Missing paddles ⇒ note “needs `hid-asus-ally` kernel”, not an error |
| W5 | Controller integration | Consent screen: “Use Omarchy controller mapping (InputPlumber)?” → `omarchy-setup-rog-ally-input --enable`. Shows refusals verbatim (competing owner, companion version). | Yes (“Use Steam only”: firmware pad) | Enable fails ⇒ disable cleanly, firmware pad, notice |
| W6 | MCU firmware | Kernel log of this boot contains `The MCU firmware version must be 319 or greater to avoid issues with suspend` (`validate_mcu_fw_version`), corroborated by `asus-armoury` `mcu_powersave` = 0. Warn: “Controller firmware is older than 319; sleep may lose the controller. Update it from Windows (Armoury Crate/MyASUS).” | Continue (warning only) | Log unreadable ⇒ “unknown”, no warning claim |
| W7 | ASUS services | If `asusd` is active or `asusctl` installed on RC71L: explain it competes with handheld power/input. The focused default is **Disable asusd** (stop + disable, receipt kept). Never installs `asusctl`. | Decline is allowed. The warning stays in hub Status | Disable fails ⇒ leave as is, report |
| W8 | Steam hand-off | “Next: Steam. It updates itself, then asks you to sign in. Use the **QR code** with the Steam app on your phone, or type with the Steam keyboard (CC tap → Steam, or the on-screen prompt).” | No | Offline (W2 skipped) ⇒ extra line: “Steam will fail without internet; you'll land in Desktop Mode.” |
| W9 | Finish | Writes autologin (`[Autologin] User=<owner> Session=omarchy-handheld.desktop Relogin=false`), `default auto` (spec 02 D6; today's verb has no `auto`), and `desktop-lock`. A fresh handheld-variant install writes `default-off` only when spec 02 §7.4's marker read is a clean absence. A real read error writes `on`, not `default-off`. A desktop-only finish writes `on`. Never writes `explicit-off`. Removes `pending`. Stops buffyboard, hands input over (§3 hand-over) and lets SDDM start. | No | Any write fails ⇒ no autologin; SDDM greeter with Qt touch keyboard (AUTH, built). SDDM is not left blocked when no user exists |

Wizard state is journalled per step under `/var/lib/omarchy/provisioning/` (like `luks-rekey.sh`) so a power loss resumes at the last unfinished step; W1's password is never written to the journal.

A journal that cannot be parsed is not a resume. The stage starts again at W1, and creating the user is idempotent. Each crash of buffyboard is counted. After two, the stage stops starting buffyboard and shows the plain baseline form, with the notice “A physical keyboard is needed.” The stage never leaves `display-manager.service` blocked when no user exists.

## 6. Password screen (D5)

| Element | Content |
|---|---|
| Title | Choose a password |
| Body | “Gaming Mode starts without it. You'll need it for `sudo`. On this handheld, Desktop Mode is not locked until the on-screen unlock keyboard ships; this password then unlocks that screen. Write it down.” |
| Fields | Password, Confirm (masked; baseline `omarchy_prompt_password`) |
| Rules | Baseline: non-empty, must match. OQ-4: minimum length. |
| Hint | “The on-screen keyboard is up for this screen.” The stage unit starts it. View does not toggle it. |
| Encrypted install | One extra line: “This also unlocks the disk at power-on (USB keyboard needed).” (`luks-rekey.sh` re-keys to it.) |

## 7. Autologin, desktop lock and fallback (D6, D7)

| Rule | Spec |
|---|---|
| Where autologin is written | W9 only (spec 02 §7.1). Desktop-only variant: unchanged Omarchy behaviour. This override is Daniel's decision (12 Nov 2026). SESSION sign-off comes through dev-red's review. |
| Setting | `omarchy-setup-gaming-session desktop-lock on` or `off` (new argument; today's verbs are `status`, `default`, `next`, `display`, `overlay` and `reset`). State is a **root-owned** file, not in `$XDG_STATE_HOME`. The stored values and the marker rules are spec 02 §7.4. `off` stores `explicit-off` only after an interactive password prompt. A passwordless polkit rule must not turn it off. `on` needs no password. |
| Defaults | `default-off` is written only by W9 on a fresh install that chose the handheld variant, and only when spec 02 §7.4 says the marker is absent. A marker read error at W9 writes `on` (spec 02 AC 32). Every other machine, including a laptop with only the package, is `on`. Adding `omarchy-gaming-session` to an existing desktop-only install writes `on` explicitly. It does not write `default-off` and it does not leave the value missing. |
| Migration | Spec 02 §7.4. This spec does not restate who writes the marker or what a downgrade does. |
| Choke point | `desktop()` in `bin/omarchy-session-start`, **before** `uwsm start`, the first Hyprland frame and any autostart, when the login was an autologin **and the effective value is `on`**. Runs `omarchy-system-lock` and waits for `{"locked":true}` on `$XDG_RUNTIME_DIR/omarchy-lock-$HYPRLAND_INSTANCE_SIGNATURE.sock`. When the effective value is `default-off` or `explicit-off`, this step is skipped and a missing lock host is not a failure. No other path (Steam “Switch to Desktop”, dock, fallback, menu) bypasses `desktop()`. |
| Fails closed | Applies when the effective value is `on`. Lock missing, timed out, or unacknowledged ⇒ do not show an unlocked desktop. If a spec 02 D2 retry remains, log out to gaming. If that budget is already spent, exit to the SDDM greeter (`Relogin=false`) and do not start another gaming attempt. |
| Gaming fallback (spec 02 D2) | Desktop entered after gaming failed still goes through the choke point. While the effective value is `default-off` or `explicit-off`, the desktop is not locked and the “Gaming Mode didn't start” notification shows at once. When it is `on`, the desktop is locked and the notification shows after unlock. |
| First boot | W9 writes `default-off` only for a fresh handheld-variant install when §7.4 says the marker is absent, so that first desktop entry is not locked. A desktop-only finish, and a later install of the gaming package onto that desktop, write `on`. There is no separate “just set a password” exemption. |

## 8. Requirements on AUTH (not designed here)

| # | Requirement | Why |
|---|---|---|
| R1 | The K07 touch keyboard ships as an additive PR on `feat/ally-parity-release-20261111`. wvkbd cannot unlock (`docs/rog-ally-authentication.md`). Buffyboard is not that keyboard (§3.1). | D7. A fresh handheld install stays `default-off` only while spec 02 §7.4 says the marker is absent. |
| R2 | Lock must publish a confirmed-locked state the supervisor can wait on before first frame. | D7 choke point. The feed on `feat/ally-auth-20261111` is `$XDG_RUNTIME_DIR/omarchy-lock-$HYPRLAND_INSTANCE_SIGNATURE.sock`. |
| R3 | Controller navigation on the lock: focus Password/Unlock/Cancel with d-pad, A = activate, no hold-only action. | Spec 01 P6 + red team. |
| R4 | “Return to Gaming” on the lock surface (no auth needed) so a user who can't type is not stuck. | Fail-safe exit; never unlocks the desktop. |
| R5 | Touch disk unlock (K11, `unl0kr`/`sd-unl0kr`) before encryption can default on. | D9. |

## 9. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Fresh keyboardless install | Vol− + Power → USB → Handheld → internal NVMe → Erase (after 500 ms) → Encryption Off → reboot → W1 username/password via buffyboard → Wi-Fi → timezone (guess) → controller test → enable InputPlumber → MCU warning → disable asusd → Steam hand-off → gaming autologin → Steam update → QR sign-in. |
| F2 | Offline install | As F1, W2 “Continue offline” → W8 warning → gaming start fails (Steam bootstrap) → spec 02 fallback → desktop. While the value is `default-off`, that desktop is **unlocked** and shows “Gaming Mode didn't start”. After the migration, unless `explicit-off`, it is locked and the notification shows after unlock. Then Wi-Fi panel → “Try Gaming again”. |
| F3 | Decline controller integration | W5 “Use Steam only” → firmware pad in gaming; desktop has no controller mouse; hub → Controller input later. |
| F4 | Power loss mid-wizard | Reboot → `pending` still set → resume at the unfinished step. |
| F5 | Desktop only on RC71L | Step 3 “Desktop only” → normal Omarchy first run; `setup-rog-ally.hook` invitation as baseline; no autologin to gaming. W9 writes `desktop-lock` `on`. PPD stays unmasked. Installing `omarchy-gaming-session` later writes `on` again and does not switch the value to `default-off`. |
| F6 | Turn desktop lock off | Desktop → hub → Gaming session → Desktop lock → Off → interactive password prompt → `explicit-off` saved. The K07 migration does not turn it back on. |

## 10. Acceptance criteria

1. On an RC71L with no USB keyboard, F1 completes to a signed-in Steam library using only controller and touch.
2. No controller button in the `tty` profile emits Ctrl+C or Super (profile file test + press test).
3. With InputPlumber killed during W1, the form can be completed by touch alone; the stage's unit restarts InputPlumber and reloads `tty` within 5 s. This does not depend on `omarchy-rog-ally-input.service`, which is not active on tty1.
4. If the composite device is absent for 10 s at form start, the “use the touchscreen” notice shows and the form proceeds.
5. Erase and every destructive or session-ending prompt ignores controller input for 500 ms after it appears, and the focused default is Back/Cancel.
6. Step 3 preselects Handheld only when `omarchy-hw-rog-ally` succeeds; on an Ally X (RC72LA) or non-ASUS device it is not shown.
7. The handheld package set contains no `asusctl`, `steamos-manager`, `hhd`, `cachyos-handheld` or Decky; `install/hardware/asus-rog.sh` still skips `asusctl` on RC71L. `buffybox` is absent until dev-red has accepted it.
8. A blank or mismatched password is rejected; the password screen shows the `sudo` explanation and that handheld Desktop Mode is unlocked until the lock-screen keyboard ships.
9. W2 before W3: with Wi-Fi joined, the timezone guess leads the list; offline, with no `OMARCHY_FORM_TIMEZONE_FALLBACK`, the full zone list shows and no guess leads it.
10. W5 runs `omarchy-setup-rog-ally-input --enable` and shows its refusal text unchanged when a competing owner exists (`hhd`, `handheld-daemon`, `input-remapper`, `xboxdrv`, `chimera`, `opengamepadui`); nothing else is disabled automatically.
11. W6 warns on Daniel's unit (the current boot's kernel log contains the 319 suspend warning) and shows “unknown” when the log is unreadable; it never blocks.
12. W7 focuses **Disable asusd** when `asusd` is active. Declining leaves it running and listed in hub Status.
13. Power loss at any wizard step resumes at that step; the password is never present in the journal.
14. After W9, a cold boot reaches Gaming Mode with no input, and the profile hand-over sends key-ups for every held key (held-A test across hand-over shows no stuck Enter).
15. While the effective value is `default-off` or `explicit-off`, an autologin desktop entry does not run `omarchy-system-lock`. When it is `on`, every such entry runs `omarchy-system-lock` before `uwsm start`, before the first Hyprland frame, and before any autostart app starts.
16. When the effective value is `on`, killing the lock host during desktop start never shows an unlocked desktop: gaming if a spec 02 D2 retry remains, otherwise the SDDM greeter with no further gaming attempt. When the value is `default-off` or `explicit-off`, desktop start does not wait on the lock host.
17. Marker presence, a missing or corrupt `desktop-lock` value, and a read error are spec 02 §7.4 (including AC 32). This install writes `default-off` only in the fresh-handheld case in the Defaults row. A passwordless polkit rule cannot write `explicit-off`. Any other machine treats a missing value as `on`.
18. F2 while the value is `default-off` ends at an unlocked desktop with “Gaming Mode didn't start” visible immediately. After the migration, unless `explicit-off`, F2 ends at a locked desktop and the notification is visible after unlock. “Try Gaming again” works once online.
19. Choosing Desktop only (F5) produces today's Omarchy install with no autologin change, `desktop-lock` `on`, and PPD still running.
20. Boot race: autologin before InputPlumber is ready still reaches gaming with the firmware pad (spec 02 §7.3).
21. At W9, a marker read that fails with EACCES or EIO writes `desktop-lock` `on`, not `default-off`.
22. Desktop only, then install `omarchy-gaming-session`: `desktop-lock` is the explicit value `on`. The next desktop entry is locked. `default-off` is not written.
23. Buffyboard is not running once SDDM starts. It is not enabled on its own. No user and no `input` group holds uinput, input or tty access for it. A non-US language, with the password set while buffyboard is up, is accepted unchanged by `sudo` and by the SDDM Qt keyboard. The layout under test has no Ctrl, Alt or F-keys. SIGKILL of buffyboard leaves tty1 at its previous size.
24. After two buffyboard crashes the plain baseline form is shown, with the physical-keyboard notice. A third start reaches that form, and a user can be created there. A journal that cannot be parsed starts at W1. SDDM is not held with no user.

## 11. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | Encryption default: off (D9) vs LUKS + TPM2 auto-unlock (`systemd-cryptenroll`, needs `sd-encrypt` instead of busybox `encrypt`) vs `unl0kr`. Trade-off: data at rest vs keyboardless boot. | Daniel / AUTH |
| OQ-2 | **Resolved (lead ruling, 12 Nov 2026).** The marker and the migration are spec 02 §7.4. This spec writes `default-off` only on a fresh handheld-variant install. | Daniel / AUTH |
| OQ-3 | **Flagged for dev-red.** §3.1 is the acceptance bar for AUR `buffybox` (split package `buffyboard`, GPL-3.0-or-later). Do not add it to the package set before that review. | dev-red |
| OQ-4 | Minimum password length/PIN policy for an OSK-typed password. | AUTH |
| OQ-5 | Does Omarchy's ISO configurator (separate repo, [omarchy-iso](https://github.com/omacom-io/omarchy-iso), not read) already support `pending` deferred provisioning for a disk-only ISO run? | dev-lead |
| OQ-6 | Can the ISO's kernel and the installed kernel expose N-KEY OEM buttons early enough for the `tty` profile (InputPlumber in the live image)? | Hardware test |
| OQ-7 | MCU version: is there a readable exact version (sysfs/hidraw) rather than the boot warning, and is there any Linux update path (LVFS)? | dev-research |
| OQ-8 | Steam first start offline: does the bootstrapper fail fast (counts as spec 02 failure class) or hang past the 60 s Gamescope Steam-child deadline? | Hardware test |
| OQ-9 | Generic handheld detection (Ally X, Legion Go, Deck) for the variant prompt: reuse CachyOS `chwd` DMI list? | dev-lead |
| OQ-10 | Wi-Fi in W2: NetworkManager in the provisioning stage is fine, but does Steam Gaming Mode's network page manage NM connections without `steamos-manager`? | dev-research |

## 12. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| “Password sign-in is retained”; no autologin in the setup command | `bin/omarchy-setup-gaming-session --help` on `feat/ally-session-20261111`. `docs/rog-ally-authentication.md` on `feat/ally-auth-20261111` still says no autologin. The gaming-session doc on **this** branch already records Daniel's decision. | Daniel's decision (12 Nov 2026) stands. SESSION sign-off comes through dev-red's review. SESSION adds the autologin write at W9 and the lock choke point in the command. |
| Absent preference = desktop; `default` is `desktop`, `gaming` or `last` | `omarchy-setup-gaming-session` on `feat/ally-session-20261111` | Handheld variant writes `default auto` at W9 (spec 02 D6). `auto` is not a current argument. Absent still means desktop until that value exists. |
| Spec 02 D10 used to default `desktop-lock` on | `docs/handheld/02-mode-switch-and-dock.md` §7.4, on this branch | Closed. This spec cites §7.4 and does not restate the marker. `default-off` is only the fresh handheld install. |
| Input enable is a terminal opt-in | `bin/omarchy-setup-rog-ally` / `omarchy-setup-rog-ally-input` | Wizard W5 is the opt-in screen; same command and refusals. |
| K07 not activated | `feat/ally-auth-20261111` trusted lock host is opt-in and unactivated | K07 lands as an additive PR on the release branch (D7 / OQ-2). This spec does not design the lock UI. |
| `setup-rog-ally.hook` invitation | `install/user/first-run/setup-rog-ally.hook` | Skipped when `/etc/omarchy/variant` = `handheld` and the wizard completed. |
| User-writable gaming state | `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session` | `desktop-lock` moves to a root-owned path (D7); other preferences stay per user. |

## Sources

- This branch (`feat/ally-parity-integration-20261111`, `bbc819047`): `install/provisioning/setup-form.sh`, `bin/omarchy-provision-owner`, `install/provisioning/omarchy-provision-owner.service`, `install/provisioning/luks-rekey.sh`, `install/provisioning/progress-icon.sh`, `install/login/sddm.sh`, `install/user/first-run/wifi.sh`, `install/user/first-run/setup-rog-ally.hook`, `install/hardware/asus-rog.sh`, `install/hardware/asus/rog-ally.sh`, `bin/omarchy-hw-rog-ally`, `bin/omarchy-setup-rog-ally-keyboard`, `bin/omarchy-system-lock`, `docs/rog-ally-gaming-session.md`, `docs/handheld/02-mode-switch-and-dock.md`, `docs/handheld/research/ally-hw-dump.md`, [tdp-decision-review.md](tdp-decision-review.md).
- `feat/ally-input-20261111`: `bin/omarchy-setup-rog-ally-input`, `bin/omarchy-hw-rog-ally-input`, `default/rog-ally-input/omarchy-rog-ally-input.service`.
- `feat/ally-session-20261111`: `bin/omarchy-session-start`, `bin/omarchy-setup-gaming-session`, `default/gaming/session.sh`, `default/gaming/wayland-sessions/omarchy-handheld.desktop`. The gaming-session doc on that branch is older than the copy on this branch.
- `feat/ally-recovery-20261111` and `feat/ally-parity-release-20261111`: `bin/omarchy-setup-rog-ally`.
- `feat/ally-auth-20261111`: `docs/rog-ally-authentication.md`, `docs/trusted-lock-host.md`.
- `feat/ally-power-20261111`: `docs/rog-ally-power.md`.
- `docs/handheld/research/ally-hw-dump.md` on this branch records `validate_mcu_fw_version`. The kernel file `hid-asus.c` is not in this repo.
- External: Bazzite [install guide](https://docs.bazzite.gg/General/Installation_Guide/install-guide/), [#715](https://github.com/ublue-os/bazzite/issues/715), [#1463](https://github.com/ublue-os/bazzite/issues/1463); CachyOS [Handheld wiki](https://wiki.cachyos.org/installation/installation_handheld/), [TODO #9](https://github.com/CachyOS/CachyOS-Handheld/issues/9), [unl0kr guide](https://discuss.cachyos.org/t/guide-luks-touchscreen-on-steam-deck-running-cachyos-handheld-edition-unl0kr/20293), [chwd profiles](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml); SteamOS [install/OOBE summary](https://survivalconfigs.com/reference/steamos/install-steamos); [buffyboard README](https://gitlab.postmarketos.org/postmarketOS/buffybox).
