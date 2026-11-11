# Gaming tools and data preservation

Source support and installed acceptance are separate. These commands have focused source tests; launcher sign-in, game compatibility, controllers, overlays and streaming still need verification on the target device by the sole rollout owner. The feature inventory is in `plans/rog-ally-parity.md`.

## Existing launchers

Keep the existing installers: `omarchy install gaming steam`, `heroic`, `lutris`, `battlenet` and `retroarch`. The Moonlight menu already uses `omarchy-install-and-launch Moonlight moonlight-qt com.moonlight_stream.Moonlight`; a second Moonlight installer is unnecessary. Steam includes Valve's selected Proton runtimes. Lutris and Battle.net already install UMU after selecting the correct lib32 Vulkan driver. Steam Remote Play is built into Steam.

The Steam, Heroic, Lutris, RetroArch and Moonlight removers now remove packages while retaining user data. Battle.net removal removes its desktop entry and keeps its prefix and shared runtimes. In particular, removing Lutris no longer deletes `~/.wine` or UMU data used by other launchers. Reinstalling RetroArch seeds defaults only when `retroarch.cfg` does not exist and preserves existing shader presets. Games, prefixes, ROMs, BIOS files and saves are never a package rollback target.

Before installation, save `pacman -Q` and back up launcher configuration and local saves to another device. Steam Cloud is per-game and may be disabled or incomplete. A filesystem snapshot does not replace a save backup. Record the existing Steam library folders and each launcher's prefix location; keep the same user account across desktop and gaming sessions.

For source rollback, revert the data-preservation commit; that restores the old destructive removal behaviour, so retain these fixes wherever possible. No user files need restoring after this increment. To undo a launcher package installation, run its `omarchy remove gaming ...` command after reviewing dependencies; these commands retain data. Battle.net can be restored by rerunning its installer against the retained prefix.

## Device acceptance for existing launchers

The rollout owner should record installed package versions, open each selected launcher, complete sign-in, and launch one already-owned game without moving its library or changing its runner. Save a known in-game state, switch desktop/gaming sessions, then load it again. Check Steam Cloud completion before closing Steam. Exercise an existing RetroArch core with the user's existing save path and a Moonlight host with actual video/audio/input; package presence alone proves none of those paths. Do not use a live library as a removal test fixture.
