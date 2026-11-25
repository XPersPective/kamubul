import plistlib
from pathlib import Path
import tempfile
import unittest
import json
import subprocess
import sys

from ads_config import TEST, configure, decode, encode, patch_plist, verify_plist


class AdsConfigTest(unittest.TestCase):
    def setUp(self):
        self.production = {
            key: 'ca-app-pub-1234567890123456' + ('~1234567890' if key == 'ADMOB_APP_ID_IOS' else f'/{i:010}')
            for i, key in enumerate(TEST)
        }

    def test_test_build_overrides_even_production_defines(self):
        for flags in [dict(release=False), dict(release=True, simulator=True)]:
            values = configure({**self.production, 'API_URL': 'https://api.test'}, **flags)
            self.assertEqual({k: values[k] for k in TEST}, TEST)
            self.assertEqual(values['API_URL'], 'https://api.test')
        for key in ['STORE_CAPTURE', 'ADMOB_TEST_MODE']:
            self.assertEqual(configure({**self.production, key: 'true'}, release=True)['ADMOB_BANNER_IOS'], TEST['ADMOB_BANNER_IOS'])

    def test_release_and_ad_free_builds(self):
        self.assertEqual(configure(self.production, release=True), self.production)
        self.assertEqual(configure({'API_URL': 'keep'}, release=True), {'API_URL': 'keep'})

    def test_reject_partial_mixed_test_and_duplicate_units(self):
        for invalid in [
            {'ADMOB_APP_ID_IOS': self.production['ADMOB_APP_ID_IOS']}, TEST,
            {**self.production, 'ADMOB_BANNER_IOS': TEST['ADMOB_BANNER_IOS']},
            {**self.production, 'ADMOB_BANNER_IOS': self.production['ADMOB_REWARDED_IOS']},
        ]:
            with self.assertRaises(ValueError):
                configure(invalid, release=True)

    def test_dart_define_roundtrip_preserves_unicode_and_equals(self):
        values = {**self.production, 'VALUE': 'Türkçe=a,b'}
        self.assertEqual(decode(encode(values)), values)
        with self.assertRaises(ValueError):
            decode(encode(values) + ',' + encode({'VALUE': 'duplicate'}))

    def test_built_plist_matches_dart_and_retains_other_keys(self):
        source = Path(__file__).resolve().parents[2] / 'ios/Runner/Info.plist'
        original = plistlib.loads(source.read_bytes())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps(original, fmt=plistlib.FMT_BINARY))
            patch_plist(path, self.production)
            actual = plistlib.loads(path.read_bytes())
            self.assertEqual(actual.pop('GADApplicationIdentifier'), self.production['ADMOB_APP_ID_IOS'])
            original.pop('GADApplicationIdentifier')
            self.assertEqual(actual, original)

    def test_ios_bundle_declares_its_supported_turkish_localization(self):
        root = Path(__file__).resolve().parents[2]
        info = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
        project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        localized_info = root / 'ios/Runner/tr.lproj/InfoPlist.strings'

        self.assertEqual(info['CFBundleDevelopmentRegion'], 'tr')
        self.assertEqual(info['CFBundleLocalizations'], ['tr'])
        self.assertRegex(project, r'developmentRegion = tr;')
        self.assertIn('tr,', project)
        self.assertIn('tr.lproj/InfoPlist.strings', project)
        self.assertIn('InfoPlist.strings in Resources', project)
        self.assertTrue(localized_info.is_file())
        localized_text = localized_info.read_text(encoding='utf-8')
        self.assertIn('"CFBundleDisplayName" = "KamuBul";', localized_text)
        self.assertIn(info['NSCalendarsUsageDescription'], localized_text)
        self.assertIn(info['NSUserTrackingUsageDescription'], localized_text)

    def test_archive_readback_rejects_wrong_bundle_or_native_id(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            data = {'CFBundleIdentifier': 'com.crazypenguin.kamubul',
                    'GADApplicationIdentifier': self.production['ADMOB_APP_ID_IOS'],
                    'NSUserTrackingUsageDescription': 'Consent',
                    'SKAdNetworkItems': [{'SKAdNetworkIdentifier': 'cstr6suwn9.skadnetwork'}]}
            path.write_bytes(plistlib.dumps(data))
            verify_plist(path, self.production)
            for key in ['GADApplicationIdentifier', 'CFBundleIdentifier']:
                path.write_bytes(plistlib.dumps({**data, key: 'wrong'}))
                with self.assertRaises(ValueError):
                    verify_plist(path, self.production)

    def test_production_pipeline_refuses_test_or_missing_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'in.json'
            output = Path(directory) / 'out.json'
            for values, succeeds in [(TEST, False), ({}, False),
                                     ({**self.production, 'STORE_CAPTURE': True}, False),
                                     (self.production, True)]:
                source.write_text(json.dumps(values), encoding='utf-8')
                result = subprocess.run([sys.executable, str(Path(__file__).with_name('ads_config.py')),
                    'prepare', '--require-production', '--input', str(source), '--output', str(output)],
                    capture_output=True)
                self.assertEqual(result.returncode == 0, succeeds)


if __name__ == '__main__':
    unittest.main()
