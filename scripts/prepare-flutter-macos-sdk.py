#!/usr/bin/env python3
"""Apply the narrowly scoped Flutter #191575 workaround to a private SDK copy.

This is a local workaround, not an upstream Flutter release or VM backport.
Use a separate SDK checkout. Do not run against a shared installed Flutter SDK.
"""

import argparse
import hashlib
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk', required=True, type=Path, help='Private Flutter 3.47.7 checkout')
args = parser.parse_args()
sdk = args.sdk.resolve()
revision = subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True).strip()
if revision != 'abaf9c523780a608bd46686fd5e53740a07077f8':
    raise SystemExit('This workaround is restricted to Flutter 3.47.7; review it for other revisions.')

source = sdk / 'packages/flutter/lib/src/widgets/_window_macos.dart'
original = subprocess.check_output(['git', '-C', str(sdk), 'show', 'HEAD:packages/flutter/lib/src/widgets/_window_macos.dart'])
patched = original
for name in ['_WindowCreationRequest', '_Size', '_Offset', '_Rect', '_Constraints']:
    declaration = f'final class {name} extends Struct {{'.encode()
    if original.count(declaration) != 1:
        raise SystemExit(f'Unexpected SDK declaration: {name}')
    patched = patched.replace(declaration, b"@pragma('vm:entry-point')\n" + declaration)
if source.read_bytes() not in (original, patched):
    raise SystemExit('SDK source has other modifications; refusing to overwrite it.')
source.write_bytes(patched)
print('Flutter 3.47.7 private SDK: retained five macOS FFI structs for AOT (#191575).')
print('Patched file SHA-256:', hashlib.sha256(patched).hexdigest())
