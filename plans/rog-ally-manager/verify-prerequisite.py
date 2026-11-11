"""Verify pinned inputs and patch application in a temporary fixture, without building."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path, help="pristine extracted pinned upstream source")
args = parser.parse_args()
directory = Path(__file__).resolve().parent
manifest = json.loads((directory / "provenance.json").read_text())


def verify(path, expected):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"Input mismatch: {path}")


for relative, digest in manifest["source_sha256"].items():
    verify(args.source / relative, digest)
patch = directory / manifest["prerequisite_patch"]["path"]
verify(patch, manifest["prerequisite_patch"]["sha256"])
verify(directory / manifest["upstream"]["license_file"], manifest["upstream"]["license_sha256"])
with tempfile.TemporaryDirectory(prefix="ally-manager-prerequisite.") as temporary:
    fixture = Path(temporary)
    relative = Path("steamos-manager/src/daemon/root.rs")
    (fixture / relative).parent.mkdir(parents=True)
    shutil.copy2(args.source / relative, fixture / relative)
    subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-i", str(patch)], cwd=fixture, check=True)
    verify(fixture / relative, manifest["prerequisite_patch"]["patched_root_sha256"])
print("PASS: pinned inputs and zero-fuzz patch application; NO Rust build/runtime/security acceptance")
