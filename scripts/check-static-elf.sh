#!/usr/bin/env bash
set -euo pipefail

binary="${1:?executable required}"
headers="$(readelf -lW "$binary")"
if grep -Eq '^[[:space:]]*INTERP[[:space:]]' <<< "$headers"; then
  echo "::error::$binary has a PT_INTERP program header"
  exit 1
fi
echo "$binary has no PT_INTERP program header"
