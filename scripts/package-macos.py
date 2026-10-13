#!/usr/bin/env python3
"""Export one macOS CPU architecture and verify every embedded Mach-O file."""
import argparse
from pathlib import Path
import plistlib
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def package(app, architecture, output):
    if not app.is_dir() or app.suffix != '.app':
        raise SystemExit('Specify an existing .app bundle')
    files = []
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink() and 'Mach-O' in run('file', '-b', str(path)):
            arches = run('lipo', '-archs', str(path)).split()
            if architecture not in arches:
                raise SystemExit(f'{path}: missing architecture {architecture}')
            if len(arches) > 1:
                temporary = path.with_name(path.name + '.thin')
                try:
                    subprocess.run(['lipo', str(path), '-thin', architecture, '-output', str(temporary)], check=True)
                    temporary.chmod(path.stat().st_mode & 0o777)
                    temporary.replace(path)
                finally:
                    temporary.unlink(missing_ok=True)
            files.append(path)
    if not files:
        raise SystemExit('Bundle contains no Mach-O executables')
    # Thin binaries invalidate their signatures. Re-seal children before parents.
    sign = ['codesign', '--force', '--sign', '-', '--preserve-metadata=entitlements,identifier,requirements,flags']
    for path in files:
        subprocess.run(sign + [str(path)], check=True)
    bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in {'.framework', '.app'}]
    for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(sign + [str(path)], check=True)
    subprocess.run(sign + [str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for path in files:
        if run('lipo', '-archs', str(path)) != architecture:
            raise SystemExit(f'Mixed architecture in {path}')
    with (app / 'Contents/Info.plist').open('rb') as f:
        version = plistlib.load(f)['CFBundleShortVersionString']
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(output)], check=True)
    print(f'Packaged {output.name}: version {version}, {architecture}, {len(files)} Mach-O files verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('architecture', choices=['arm64', 'x86_64'])
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.app, args.architecture, args.output)
