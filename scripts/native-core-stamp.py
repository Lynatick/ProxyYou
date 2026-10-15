#!/usr/bin/env python3
"""Identify locally patched cores so build helpers cannot replace them silently."""
import hashlib
import json
from pathlib import Path
import sys


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


mode, name = sys.argv[1:]
binary = Path(name)
patch = Path(__file__).resolve().parent.parent / 'native-patches/connection-stability.patch'
stamp = binary.with_name(binary.name + '.proxyyou.json')
expected = {'binary_sha256': checksum(binary), 'stability_patch_sha256': checksum(patch)}
if mode == 'write':
    stamp.write_text(json.dumps(expected, indent=2) + '\n')
elif mode == 'verify':
    if not stamp.is_file() or json.loads(stamp.read_text()) != expected:
        raise SystemExit('Rebuild the patched native core before building ProxyYou')
else:
    raise SystemExit('Use write or verify followed by the native binary path')
