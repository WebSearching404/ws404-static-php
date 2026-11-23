"""Validate the downloaded release set and print the existing PHP-BUILT fields."""

import hashlib
import json
from pathlib import Path
import re
import sys

minors = json.loads(sys.argv[1])
if not isinstance(minors, list) or not minors or not all(
    isinstance(minor, str) and re.fullmatch(r"[0-9]+\.[0-9]+", minor) for minor in minors
):
    sys.exit("Invalid PHP version matrix")
if len(minors) != len(set(minors)):
    sys.exit("Duplicate PHP version in the matrix")

assets = {f"php-{minor}-cli-linux-x86_64.tar.gz": minor for minor in minors}
expected = set(assets) | {name + ".version" for name in assets}
actual = {path.name for path in Path.cwd().iterdir()}
if actual != expected:
    sys.exit("Release files differ from the expected matrix")

lines = []
for name, minor in sorted(assets.items()):
    archive = Path(name)
    record = Path(name + ".version")
    if any(path.is_symlink() or not path.is_file() for path in (archive, record)):
        sys.exit(f"Unexpected file type in release for PHP {minor}")
    if record.stat().st_size > 256:
        sys.exit(f"Oversized build record for PHP {minor}")
    fields = record.read_text(encoding="ascii").split()
    if len(fields) != 3 or fields[0] != name or not re.fullmatch(re.escape(minor) + r"\.[0-9]+", fields[2]):
        sys.exit(f"Invalid build record for PHP {minor}")
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1048576), b""):
            digest.update(chunk)
    if digest.hexdigest() != fields[1]:
        sys.exit(f"Archive digest differs from the build record for PHP {minor}")
    lines.append(f"PHP-BUILT {minor} {fields[2]}")
print("\n".join(lines))
