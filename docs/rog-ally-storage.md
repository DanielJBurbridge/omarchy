# ROG Ally storage and save recovery

`bin/omarchy-drive-game-library` supplies A14's existing-filesystem path. It uses the central RC71L predicate, util-linux's block tree, jq and UDisks2 (already pulled in by the default `udiskie` package). It installs no service, writes no fstab entry and never formats, changes ownership or forces an unmount. UDisks2 owns authorisation through polkit. The command passes arguments directly to [udisksctl](https://storaged.org/doc/udisks2-api/latest/udisksctl.1.html); it does not parse that tool's human-readable output.

## Command contract

```bash
omarchy drive game library --menu
omarchy drive game library list
omarchy drive game library mount /dev/mmcblk0p1
omarchy drive game library check "/run/media/USER/Games/SteamLibrary"
omarchy drive game library unmount /dev/mmcblk0p1
```

Substitute a partition returned by `list` and the real mount directory. The native picker offers mount, check and unmount for an existing data partition; cancelling exits successfully. Launch the picker in a visible terminal when the caller needs to retain errors or software-check results. `mount` and `unmount` are harmless when already in the requested state. They use the existing filesystem and ordinary UDisks2 mount policy. A busy unmount fails; close the game, Steam downloads and file-manager windows before trying again.

Eligible partitions belong to a removable disk or a USB disk. The entire disk is excluded if any child holds `/`, `/boot`, `/efi`, `/home`, `/usr`, `/var` or swap. The JSON query explicitly requests a tree, because lsblk otherwise emits a flat list when the `NAME` column is omitted. The command refuses internal disks, whole disks, encrypted containers, unknown filesystems and paths not found in this allow-list. An encrypted external library can still be opened through the file manager's normal UDisks2 support; this command does not manage passphrases or unlocked mapper devices.

`list` prints device paths, filesystem types and mounted state, with no labels, UUIDs or serial numbers. UDisks2's interactive mount output can contain a personal mount path; do not include it in a public support report without review. The shared handheld diagnostic report must not call `list` or include library locations.

`check` requires an existing directory on an eligible mounted partition. It checks directory write/search permission and rejects read-only or `noexec` mounts. ext4, btrfs, xfs and f2fs are accepted. NTFS, exFAT and FAT can be mounted for file access, but the check refuses to advertise them as reliable Proton libraries because prefixes need Linux filesystem semantics. Passing these checks does not establish that a game actually starts or that media is healthy.

## Permissions and Steam

Add the writable library folder through Steam **Settings → Storage**. Keep existing libraries in place. A Linux filesystem's top directory can belong to root; choose a folder you already own or deliberately create one new library folder. Do not recursively change ownership of the drive or use `chmod 777`.

For an existing Linux mount with no library folder, a user can deliberately create a single new folder from a visible terminal. Replace the example mount path, check it is the intended external disk, and run:

```bash
library_dir="/run/media/USER/Games/SteamLibrary"
if [[ ! -e $library_dir ]]; then
  sudo install -d -m 0755 -o "$USER" -g "$(id -gn)" -- "$library_dir"
fi
omarchy drive game library check "$library_dir"
```

The folder is left in place on uninstall. If the card disappears during play, stop the game, reconnect and mount it, then select the existing library in Steam. Do not initialise or format a card in response to an absent mount. A controller/touch session needs an accessible filesystem before Steam can use it; this feature does not promise automatic mounting before login.

## User-data backup and restore (U14)

System snapshots and boot recovery do not replace an independent save backup. Steam Cloud is game dependent and can propagate a bad save. Steam's game-file backup also does not include all third-party saves. See Valve's [Steam Cloud guidance](https://help.steampowered.com/en/faqs/view/68d2-35ab-09a9-7678) and [game backup guidance](https://help.steampowered.com/en/faqs/view/4593-5CB7-DC3C-64F0). Locate each game's actual save directory; native games, Proton games and non-Steam launchers can store saves in different places.

Close the game and Steam before copying. Use a separate mounted backup disk with enough free space; a second folder on the same card is vulnerable to the same media failure. `rsync` is optional: install it with `omarchy pkg add rsync` if needed. Back up only the chosen save directory into a new dated directory, then check the copy. Replace both example paths first:

```bash
game_save_dir="$HOME/path/to/actual/game/saves"
backup_root="/run/media/USER/Backup"
backup_dir="$backup_root/ally-saves-$(date +%Y%m%d-%H%M%S)"
if [[ -d $game_save_dir && -d $backup_root && ! -e $backup_dir ]]; then
  mkdir -m 0700 -- "$backup_dir"
  rsync --archive --safe-links -- "$game_save_dir/" "$backup_dir/"
  rsync --archive --safe-links --checksum --dry-run --itemize-changes -- "$game_save_dir/" "$backup_dir/"
fi
```

No output from the comparison means the selected files match. Keep the backup private: saves can contain account or personal data. This copies the chosen directory only; it does not back up all saves, prefixes, Steam credentials or the OS. `--safe-links` skips symlinks that escape the selected directory; if a game links its saves elsewhere, back up the actual target separately. Never publish Steam `config`, `ssfn*`, tokens or a whole home-directory archive as diagnostic evidence.

Restore into a new empty directory first, compare and inspect it, then use the game's documented restore process with the game and Steam closed. Preserve the current saves separately before replacing any files. The copy itself does not reconcile a Steam Cloud conflict; choose the intended local/cloud version deliberately when Steam next asks. Do not add `--delete` to these commands.

```bash
restore_dir="$HOME/ally-save-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -m 0700 -- "$restore_dir"
rsync --archive --safe-links -- "$backup_dir/" "$restore_dir/"
rsync --archive --safe-links --checksum --dry-run --itemize-changes -- "$backup_dir/" "$restore_dir/"
```

## Source and physical verification

Run `bash test/shell.d/drive-game-library-test.sh >/tmp/ally-storage-test.log 2>&1` and read the log. Isolated fixtures verify selection guards, removable USB SSDs, idempotent mounts, backend errors, spaced directory paths, noexec/Windows-filesystem checks and picker cancellation. They do not mount a real disk.

The sole Ally deployment owner must check the actual package versions (`udisks2`, `udiskie`, `util-linux`, `jq`), insert a known existing-filesystem card or USB disk, use the picker twice, verify Steam can launch from the chosen writable directory, close the game and unmount it, then remove/reinsert it without losing the library. A separate save test creates a disposable save, backs it up, restores to a new directory and compares content. Record touch/controller operation separately. No storage, game or physical-media acceptance is claimed by source tests.

Rollback: close the game, unmount the selected partition through the same picker, and revert the source increment or reinstall the earlier Omarchy package. There is no persistent mount configuration to undo. Leave game folders and backups intact; deletion is a separate user decision.
