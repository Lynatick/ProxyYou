#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${1:?Specify the patched Hiddify Core v4.1.0 source directory}"
stability_patch="$root/native-patches/connection-stability.patch"
if patch -d "$source_dir" -p1 --forward --batch --dry-run < "$stability_patch" >/dev/null 2>&1; then
  patch -d "$source_dir" -p1 --forward --batch < "$stability_patch"
elif patch -d "$source_dir" -p1 --reverse --batch --dry-run < "$stability_patch" >/dev/null 2>&1; then
  echo "ProxyYou connection stability patch already applied"
else
  echo "Core source differs from the expected base; refusing a partial stability patch" >&2
  exit 1
fi
