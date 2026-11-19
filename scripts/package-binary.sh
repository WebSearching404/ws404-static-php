#!/usr/bin/env bash
# GNU tar on the Linux build runner. The archive digest should depend on the
# published member name and program bytes, independently of the staging host.
set -euo pipefail

member="${1:?member required}"
archive="${2:?archive required}"
tar --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=0755 -cf - -- "$member" | gzip -n > "$archive"
