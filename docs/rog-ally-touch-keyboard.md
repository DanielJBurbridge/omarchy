# ROG Ally desktop touch keyboard

On the original RC71L, the optional wvkbd keyboard accepts touch and right-trigger clicks in Omarchy menu search. Daniel tested both on build `71d6b055` and found the themed Retro 82 layout usable. The optional search-field and edge-swipe actions have separate acceptance checks. [Parity inventory](handheld/feature-parity.md#controller-touch-and-accessibility)

## Desktop operation

After optional setup, tap **Keyboard** in the bar to show or hide the keyboard without opening a menu. **Desktop Keyboard** in Apps does the same. Right-clicking the bar button hides it. The bar is a surface without keyboard focus; the wvkbd surface also requests no keyboard focus. Select a text field in an ordinary desktop app, then summon the keyboard. Steam can be closed.

On RC71L the Keyboard button and keyboard appear on the built-in display. The reviewed dock-capable build keeps the keyboard there even when an external display is focused. The editor keeps keyboard focus. Stock wvkbd opens only while the built-in display is the sole enabled output. The optional bottom-edge gesture still requires that single-display layout. A display set to mirror the built-in panel copies its entire image.

On RC71L with `wvkbd-mobintl` installed, `Super + Ctrl + Y` toggles it. This is a panel shortcut, has no locked binding, and does not remap any physical key. The ordinary laptop/desktop and Ally X do not receive it. Personal bindings loaded afterwards still take precedence. INPUT maps the upstream Keyboard capability (long Command Centre) to `KeyLeftMeta + KeyLeftCtrl + KeyY` in desktop mode. This contract is agreed in source; physical button delivery is still unverified.

The keyboard is a bottom overlay, not a draggable window. It does not resize applications, so it can cover a field at the bottom of a maximised window. Scroll the field above it or move the window. Both orientations use 264 logical units; the full layout has six rows, 44 units per row before upstream borders. DISPLAY owns monitor scaling and the optional touch bar size. A normal 26-unit bar is still 26 units high; the wide button does not silently enlarge the global bar. Verify the Ally touch preset and narrow/rotated outputs before accepting K10.

With DISPLAY's optional increment installed, `omarchy display rog ally touch-preset` selects internal 1.5× scale and a bar at least 44 logical units thick in either orientation, preserving larger effective bar dimensions and the current font scale. At native landscape 1080p this gives a 1280×720 logical desktop; this keyboard occupies the bottom 264 units. The preset leaves widget placement alone, so run the keyboard setup separately. Its independent rollback is `omarchy display rog ally touch-preset reset`, which restores its saved shell tokens and monitor settings only if they have not been edited since. See the [DISPLAY increment's install and rollback guide](https://github.com/DanielJBurbridge/omarchy/blob/4357ecd01c4a39b28c162943158d784af42e9841/docs/rog-ally-display.md). Physical geometry remains unverified; test the delivered 264-unit keyboard rather than the earlier 240-unit proposal.

Use the normal top bar for touch access to both show and hide. A bottom-positioned bar can be covered by the keyboard; the shortcut/controller command remains available, but touch-only hide from that covered bar is not supported by this increment. Hiding the entire bar also hides its summon button.

The bottom-left keyboard symbol switches between `full` and `special`; it does not hide the keyboard. `full` has letters, numbers, Shift, Ctrl, Escape, Tab, arrows and Backspace. `special` adds Alt, Super (`Sup`), AltGr, punctuation, Delete, Home/End and Page Up/Down. Modifiers other than Caps Lock are one-shot: tap Ctrl, then the next key. Use Shift before a symbol for its shifted form.

`Cmp` followed by a letter opens accents; `Cmp` followed by Space opens the built-in layout index, including Cyrillic, Greek, Arabic, Persian, Georgian and Hebrew. The keyboard supplies its own keymap. Changing the physical keyboard layout does not change its labels or arrangement, and this setup leaves physical layouts and Fcitx settings alone. It is not a general AZERTY/Dvorak layout editor. Exercise the actual characters needed before relying on a particular script or compose sequence. These are upstream [v0.21 layout and compose features](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/README.md), not copied layouts.

## Ownership and session lifecycle

The stable command contract is:

```bash
omarchy-toggle-desktop-keyboard         # toggle
omarchy-toggle-desktop-keyboard show    # idempotent
omarchy-toggle-desktop-keyboard hide    # idempotent, removes the keyboard from view
omarchy-toggle-desktop-keyboard stop    # hide, then terminate this session's process
```

State and output logs live in `$XDG_RUNTIME_DIR/omarchy-desktop-keyboard-<WAYLAND_DISPLAY>/`. The helper serialises requests and validates PID, process birth time and executable before signalling it. Repeated shows reuse the owned process; hide/stop while inactive start nothing. A killed or failed keyboard is relaunched by the next show. No daemon, polling or automatic startup is added.

With stock wvkbd 0.21, use a tapped Shift or Ctrl before hiding the keyboard. An unused modifier can carry over to the next keystroke, including one from a connected keyboard. Hiding the keyboard keeps its process alive.

The existing Big Picture launcher hides the desktop keyboard. SESSION must call `stop` from the departing desktop environment before entering `omarchy-gamescope.desktop`; wvkbd also exits when its Wayland connection disappears. New show/toggle requests require a Hyprland session and reject a Gamescope desktop. Hide/stop remain usable for teardown without the Hyprland signature. Returning to Hyprland starts no keyboard automatically; summon it again when needed. On RC71L with `wvkbd-mobintl` installed, Hyprland is set to `input:virtualkeyboard:release_pressed_on_close` so a crashed keyboard does not leave a key or a latched Shift or Ctrl down.

Gaming Mode uses Steam's keyboard: `Guide + X` (West), or Steam's text-field UI. INPUT maps the upstream Keyboard capability to Guide+West in gamepad/DS5 mode, while keeping manual Guide+West Steam-owned. Steam documents the chord in [its controller shortcuts](https://help.steampowered.com/en/faqs/view/69e3-14af-9764-4c28). A desktop layer-shell keyboard does not cross into a separate Gamescope session. Verify Steam search and in-game text entry separately; this helper does not configure Steam Input or claim every game accepts Steam's keyboard.

Sign-in and unlock use their own keyboards. On the physical Ally, Daniel opened the desktop keyboard, then the Omarchy menu, and typed into its search field with both touch and RT. In disposable Hyprland, opening menu search first and tapping its field also showed a working keyboard with the option enabled. The Apps grid still needs a typing and selection check.

## Optional bottom-edge keyboard handle

Set `"desktopKeyboard": { "edgeSwipe": true }` in `~/.config/omarchy/shell.json`. On an empty workspace or with an app text field focused, tap the handle at the bottom centre of the built-in screen. It changes colour under your finger and opens the themed keyboard when you lift. You can also swipe up from the strip around the handle and lift. Once the keyboard is open, swipe down from the handle just above the keys to hide it. The **Keyboard** button in the bar can also hide it. Removing the setting or setting it to `false` also removes the handle and its reserved space.

The handle reserves 36 logical pixels along the bottom of the desktop. The tap target extends 12 pixels past each end of the visible handle and fills the strip vertically. For a swipe, start anywhere within the middle 480 pixels, or the middle half on a narrower screen. Swipe up at least 48 pixels. Your thumb can follow a gentle diagonal as it moves up. The handle changes colour while it tracks the gesture. All distances are logical pixels. A mouse drag leaves the keyboard alone. The handle sits below application windows. A floating or fullscreen window covering it keeps the input. A bottom bar takes precedence. The normal bar button and controller shortcut are available when the handle is covered.

The lower handle disappears when the keyboard, a menu or a panel is open. The dismiss handle appears above an unobstructed keyboard. The bottom reservation stays in place so tiled windows keep their size. After rotating the display, start a fresh swipe.

The shell enables the handle only on an opted-in RC71L with a single internal display. At release the keyboard helper checks for the sole built-in Novatek touchscreen, an unlocked Hyprland session, an empty active workspace or a focused app, and the expected desktop layers. A second touchscreen, another display, Gamescope, an authentication prompt or an unreadable desktop state suppresses the summon. Hyprland’s configurable swipes are trackpad gestures. Using a Quickshell layer gives this touchscreen control a bounded input area and leaves the compositor’s gesture bindings and device permissions alone. [Hyprland gestures](https://wiki.hypr.land/configuring/core/binds/gestures/)

## Wi-Fi passphrase entry

Open the Network panel, choose the network and tap **Keyboard** in the bar. The masked field keeps focus. Enter submits the passphrase and Esc cancels. A manually opened keyboard stays available for another attempt. In the desktop candidate, the same sequence works with the keyboard already open. Both orders were checked with a dummy network in disposable Hyprland. At 2× the keyboard covers the lower edge of the card, but the masked text, Enter and Esc are visible. Physical Wi-Fi entry remains to be checked.

## Optional keyboard on menu search

Add `"menu": { "onScreenKeyboard": true }` to your `shell.json` to show the keyboard when you deliberately tap or click Omarchy menu search. A keyboard opened this way hides when search loses focus or the menu closes. The bar, app and keyboard shortcuts still provide manual control. This setting defaults to off.

Use the bar, shortcut or optional edge swipe for other applications. Omarchy starts Fcitx5, which uses Hyprland's single input-method slot. Both manual summon and menu search use wvkbd's virtual-keyboard path. Application-wide activation needs a supported adapter through the existing input-method owner and real application tests. [Hyprland input-method implementation](https://github.com/hyprwm/Hyprland/blob/main/src/managers/input/InputMethodRelay.cpp) · [wvkbd v0.21](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c)

## Install and rollback for the rollout owner

Only the designated deployment thread applies this increment to the Ally. Review and build the normal Omarchy package from the integrated source, retaining its previous package for rollback. This change adds no separate system service, udev rule, fixed-system configuration or companion package. Its `bin/`, `default/` and `shell/` files travel in the normal package; do not copy files over the installed package tree. A documented development link can expose these runtime files for a temporary check, but it is not evidence a release package was installed.

On 11 November 2026, the [primary AUR API](https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=wvkbd) reported `wvkbd 0.21-1`, GPL3, built from the upstream SourceHut release. [Upstream v0.21](https://github.com/jjsullivan5196/wvkbd/releases/tag/v0.21) fixes hide crashes and missing key releases. The configure-only setup accepts the reviewed stock `0.21-1` and the reviewed output-selecting `0.21-1.1` candidate. Keep the stock artifact available for rollback. Review the recipe at installation time when using the explicit AUR path.

Before setup, record package versions and preserve any existing `~/.config/omarchy/shell.json` and `~/.local/share/applications/omarchy-desktop-keyboard.desktop`, using the corresponding XDG locations when set. Then, inside the user's Hyprland desktop:

```bash
omarchy-setup-rog-ally-keyboard --configure-reviewed-package
```

If wvkbd is absent, inspect the current AUR PKGBUILD/source first and use `--install-reviewed-aur` only after that review. Setup preserves an existing launcher and existing widget placement. With a running shell it rescans plugins and puts the Keyboard widget in the right bar section; without one it reports that placement is deferred until setup is rerun in the desktop. It never starts the keyboard or restarts the shell. The new shortcut appears at the next Hyprland reload/login; only the rollout owner should trigger that on the device.

Rollback the optional UI from the same desktop:

```bash
omarchy-toggle-desktop-keyboard stop
omarchy-plugin-disable omarchy.desktop-keyboard
```

Restore the saved launcher (or remove only the launcher created by this setup if none existed). Restore the earlier Omarchy package for a source rollback. If wvkbd was newly installed solely for this feature, remove it with `omarchy-pkg-drop wvkbd`; the conditional shortcut disappears on the next Hyprland reload. `omarchy-setup-rog-ally-keyboard --remove` drops the bar button and the launcher this setup created, including when the machine no longer passes the RC71L check. A tap with wvkbd missing shows a notification instead of failing silently. Preserve a pre-existing wvkbd installation. No input-device permissions, PAM rules, services or global keymaps need undoing. Avoid restoring an entire shell config over later unrelated bar edits; disabling just this widget preserves them.

## Focused evidence and physical acceptance

Run source checks with full logs:

```bash
bash test/shell.d/desktop-keyboard-test.sh >/tmp/ally-touch-keyboard-test.log 2>&1
bash test/shell.d/hw-rog-ally-test.sh >/tmp/ally-touch-hw-test.log 2>&1
bash test/shell.d/capture-picker-binds-test.sh >/tmp/ally-touch-capture-picker-binds-test.log 2>&1
bash test/shell.d/i18n-test.sh >/tmp/ally-touch-i18n-test.log 2>&1
```

The native signal fixture tests the real helper's arguments, signal routing, concurrency, executable replacement and stale-PID isolation. Its dependency lookup uses a private PATH containing only the fixture keyboard, real standard tools and the real command-presence helper. The runner supplies a decoy installed keyboard on the caller's PATH, so the missing-dependency case also catches accidental host fallback. It does not emulate keyboard behaviour or establish focus retention. The Lua check loads the actual defaults and central DMI predicate, verifying that only RC71L with optional wvkbd acquires the unlocked shortcut.

The rollout owner must record the source commit, installed package versions, active session, backups, screenshots reviewed and the result of each check:

1. Close Steam. Focus a browser address bar and a terminal/editor. Tap Keyboard in the bar, type `Ally 123 !@#$% / \\ é`, use Shift, Ctrl+A, Backspace, arrows, Home/End and Delete, and submit with Enter. Verify the selected app receives characters and the bar/keyboard never become the text target. Do not record real passwords.
2. Toggle repeatedly with the bar and controller Keyboard capability; run repeated `show`/`hide`, then `stop` and summon again. Hide during a held/repeating key and check subsequent physical/controller typing for stuck keys. Retain a physical-keyboard baseline and a non-US desktop layout.
3. Exercise `Cmp`, symbols and at least one required non-Latin layout. Confirm the keyboard's independent keymap does not change the physical layout or Fcitx method. Check touch targets, clipping and the covered application area at the agreed display scale, in both orientations and when docked.
4. Open Omarchy menu/Apps before and after showing the keyboard. Attempt actual search typing and dismiss/selection. Record focus or stacking failures separately from ordinary app entry; existing user clones are not proof the packaged shell works.
5. Launch Big Picture through its wrapper, then the dedicated gaming session. Confirm no desktop keyboard remains, and Guide+West opens Steam's keyboard in a focused Steam field. Test one game's text entry. Exit/fail gaming back to Hyprland, summon wvkbd again with Steam closed, log out/in and repeat. Lock/unlock acceptance belongs to AUTH.
6. With the optional swipe enabled, check the handle in landscape and portrait. Focus a field, swipe from the bezel, type, then hide from the bar. Check short swipes, mouse drags, a docked display and the locked screen. Record how reliably the first swipe opens the keyboard and whether ordinary scrolling beside the handle still works.

Source-ready and installed/physically verified are separate milestones. A failing physical check remains open with its exact session, application and reproduction; do not replace it with a fixture pass.
