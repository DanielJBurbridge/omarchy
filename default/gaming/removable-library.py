"""Select and mount one removable filesystem using the session owner's UDisks rights."""

import os
import re
import subprocess
import sys
from collections import defaultdict

import gi

gi.require_version("UDisks", "2.0")
from gi.repository import Gio, GLib, UDisks


def volumes(client):
  by_uuid = defaultdict(list)
  for obj in client.get_object_manager().get_objects():
    block = obj.get_block()
    if block and block.props.id_uuid:
      by_uuid[block.props.id_uuid].append(obj)
  return by_uuid


def insertion(obj):
  return next((link for link in obj.get_block().props.symlinks
               if link.startswith("/dev/disk/by-diskseq/")), None)


def eligible(client, obj):
  block = obj.get_block()
  drive = client.get_drive_for_block(block)
  filesystem = obj.get_filesystem()
  return (filesystem and "/" not in filesystem.props.mount_points
          and block.props.id_usage == "filesystem"
          and re.fullmatch(r"[a-zA-Z0-9-]+", block.props.id_uuid)
          and block.props.hint_auto and not block.props.hint_system and not block.props.hint_ignore
          and not block.props.configuration.n_children()
          and insertion(obj) and drive and drive.props.removable
          and drive.props.seat == os.getenv("XDG_SEAT", "seat0"))


def select(client, saved, title, forget, back):
  choices = {}
  for uuid, objects in sorted(volumes(client).items()):
    if len(objects) == 1 and eligible(client, objects[0]):
      props = objects[0].get_block().props
      label = "".join(c if c.isprintable() else " " for c in props.id_label)
      choices[f"{label or props.device}\t{uuid}"] = uuid

  options = ["󰋊\t" + row for row in choices]
  if saved:
    row = forget + "\t" + saved
    choices[row] = "forget"
    options.append("󰅖\t" + row)
  options.append("󰌑\t" + back)
  picker = subprocess.run(["omarchy-menu-select", title, *options,
                           "--", "--width", "640"], stdout=subprocess.PIPE, text=True)
  if picker.returncode not in (0, 1):
    raise SystemExit(picker.returncode)
  if picker.returncode == 0:
    print(choices.get(picker.stdout.rstrip("\n"), ""))


def mount_interrupted(error):
  return (error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT)
          or error.matches(UDisks.error_quark(), UDisks.Error.TIMED_OUT)
          or any(error.matches(Gio.dbus_error_quark(), code) for code in (
            Gio.DBusError.NO_REPLY, Gio.DBusError.NAME_HAS_NO_OWNER, Gio.DBusError.SERVICE_UNKNOWN)))


def watch(client, uuid):
  # An unmount or UDisks restart retains the kernel disk sequence. Reinserting
  # the medium gives it a fresh sequence, even at the same device path.
  # None marks a handled insertion. After an interrupted Mount, keep the
  # daemon's D-Bus owner so only a replacement daemon can trigger one retry.
  insertions = {}
  manager = client.get_object_manager()

  def reconcile(client):
    objects = volumes(client).get(uuid, [])
    if len(objects) > 1:
      sequences = {insertion(obj) for obj in objects}
      if sequences.difference(insertions):
        print("Gaming library: duplicate filesystem UUID; mount skipped.", file=sys.stderr)
      insertions.update(dict.fromkeys(sequences))
      return
    if not objects:
      return

    obj = objects[0]
    sequence = insertion(obj)
    if (sequence in insertions and insertions[sequence] is None) or not eligible(client, obj):
      return

    fs = obj.get_filesystem()
    paths = fs.props.mount_points
    if paths:
      path = paths[0]
    else:
      owner = manager.get_name_owner()
      if not owner or insertions.get(sequence) == owner:
        return
      options = GLib.Variant("a{sv}", {"auth.no_user_interaction": GLib.Variant("b", True)})
      try:
        path = fs.call_mount_sync(options, None)
      except GLib.Error as error:
        insertions[sequence] = owner if sequence not in insertions and mount_interrupted(error) else None
        print(f"Gaming library: {str(error)!r}", file=sys.stderr)
        return

    insertions[sequence] = None
    try:
      if os.statvfs(path).f_flag & os.ST_RDONLY:
        print(f"Gaming library: {path!r} is read-only.", file=sys.stderr)
    except OSError as error:
      print(f"Gaming library: {str(error)!r}", file=sys.stderr)

  client.connect("changed", reconcile)
  reconcile(client)
  try:
    os.write(1, b"ready\n")
  except BrokenPipeError:
    pass  # Steam already started after its bounded wait.
  GLib.MainLoop().run()


if __name__ == "__main__":
  mode, uuid, *labels = sys.argv[1:]
  client = UDisks.Client.new_sync()
  if mode == "select":
    select(client, uuid, *labels)
  elif mode == "watch" and uuid:
    watch(client, uuid)
