import hashlib
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch


script = Path(__file__).resolve().parents[2] / 'scripts/github_release.py'
spec = importlib.util.spec_from_file_location('release_gate', script)
release_gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_gate)


class ReleaseGateTest(unittest.TestCase):
    def verify(self, include_macos=None, mac_assets=False, corrupt=False):
        names = ['ProxyYou-Android-4.1.21.apk', 'ProxyYou-Windows-x64-4.1.21-Setup.exe']
        if mac_assets:
            names += ['ProxyYou-macOS-AppleSilicon-4.1.21.zip', 'ProxyYou-macOS-Intel-4.1.21.zip']
        payloads = {name: name.encode() for name in names}
        payloads['SHA256SUMS.txt'] = ''.join(
            f'{hashlib.sha256(payloads[name]).hexdigest()}  {name}\n' for name in names
        ).encode()
        if corrupt:
            payloads[names[0]] = b'corrupt download'
        release = {
            'tag_name': 'v4.1.21', 'draft': True, 'prerelease': False,
            'target_commitish': 'validated-sha',
            'assets': [{'name': name} for name in payloads],
        }
        downloads = []

        def api(path):
            if '/releases?' in path:
                return [release]
            if '/commits/' in path:
                return {'sha': 'validated-sha'}
            if '/git/matching-refs/' in path:
                return []
            raise AssertionError(path)

        def download(command, check):
            self.assertTrue(check)
            name = command[command.index('--pattern') + 1]
            destination = Path(command[command.index('--dir') + 1])
            (destination / name).write_bytes(payloads[name])
            downloads.append(name)

        env = {'ARTIFACTS_VERIFIED': 'true', 'GH_REPO': 'test/repo',
               'RELEASE_TAG': 'v4.1.21', 'GITHUB_SHA': 'validated-sha'}
        if include_macos is not None:
            env['INCLUDE_MACOS'] = include_macos
        with patch.dict(os.environ, env, clear=True), \
                patch.object(release_gate, 'version', return_value='4.1.21'), \
                patch.object(release_gate, 'api', side_effect=api), \
                patch.object(release_gate.subprocess, 'run', side_effect=download):
            release_gate.verify_draft()
        return downloads

    def test_paused_macos_verifies_android_and_windows(self):
        self.assertEqual(self.verify(include_macos='false'), [
            'SHA256SUMS.txt', 'ProxyYou-Android-4.1.21.apk', 'ProxyYou-Windows-x64-4.1.21-Setup.exe',
        ])

    def test_paused_macos_rejects_accidentally_uploaded_mac_packages(self):
        with self.assertRaisesRegex(SystemExit, 'macOS publication is paused'):
            self.verify(include_macos='false', mac_assets=True)

    def test_default_full_release_still_requires_mac_packages(self):
        with self.assertRaisesRegex(SystemExit, 'Missing platform packages'):
            self.verify()

    def test_default_full_release_verifies_both_mac_architectures(self):
        downloaded = self.verify(mac_assets=True)
        self.assertIn('ProxyYou-macOS-AppleSilicon-4.1.21.zip', downloaded)
        self.assertIn('ProxyYou-macOS-Intel-4.1.21.zip', downloaded)

    def test_partial_release_still_rejects_corrupted_package(self):
        with self.assertRaisesRegex(SystemExit, 'Checksum mismatch'):
            self.verify(include_macos='false', corrupt=True)


if __name__ == '__main__':
    unittest.main()
