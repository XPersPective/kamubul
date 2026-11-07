"""Keep native and Dart AdMob IDs consistent, before iOS code signing.

Production values come from publisher-managed defines, never this module.
Debug/profile/simulator/capture builds always compile Google's demo units.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re

TEST = {
    'ADMOB_APP_ID_IOS': 'ca-app-pub-3940256099942544~1458002511',
    'ADMOB_BANNER_IOS': 'ca-app-pub-3940256099942544/2934735716',
    'ADMOB_INTERSTITIAL_IOS': 'ca-app-pub-3940256099942544/4411468910',
    'ADMOB_REWARDED_IOS': 'ca-app-pub-3940256099942544/1717085313',
    'ADMOB_APP_OPEN_IOS': 'ca-app-pub-3940256099942544/5575463023',
}


def decode(raw):
    values = {}
    for item in filter(None, raw.split(',')):
        key, sep, value = base64.b64decode(item, validate=True).decode().partition('=')
        if not sep or key in values:
            raise ValueError('invalid or duplicate Dart define')
        values[key] = value
    return values


def encode(values):
    return ','.join(base64.b64encode(f'{k}={v}'.encode()).decode()
                    for k, v in values.items())


def configure(values, *, release, simulator=False):
    values = dict(values)
    test = (not release or simulator or
            str(values.get('STORE_CAPTURE', '')).lower() == 'true' or
            str(values.get('ADMOB_TEST_MODE', '')).lower() == 'true')
    if test:
        values.update(TEST)
        return values
    supplied = [key for key in TEST if values.get(key)]
    # A build without ad configuration remains ad-free, with the SDK sample app ID.
    if not supplied:
        return values
    if len(supplied) != len(TEST):
        raise ValueError('release ads require the app ID and all four iOS units')
    app = values['ADMOB_APP_ID_IOS']
    if not re.fullmatch(r'ca-app-pub-\d{16}~\d{10}', app) or app == TEST['ADMOB_APP_ID_IOS']:
        raise ValueError('release requires a production iOS app ID')
    publisher = app.split('~')[0]
    units = [values[key] for key in TEST if key != 'ADMOB_APP_ID_IOS']
    if len(set(units)) != 4 or any(not re.fullmatch(re.escape(publisher) + r'/\d{10}', unit) for unit in units):
        raise ValueError('release iOS units must be distinct and match the publisher')
    return values


def patch_plist(path, values):
    data = path.read_bytes()
    plist = plistlib.loads(data)
    plist['GADApplicationIdentifier'] = values.get('ADMOB_APP_ID_IOS', TEST['ADMOB_APP_ID_IOS'])
    if not plist.get('NSUserTrackingUsageDescription') or not plist.get('SKAdNetworkItems'):
        raise ValueError('missing ATT description or SKAdNetwork configuration')
    fmt = plistlib.FMT_BINARY if data.startswith(b'bplist') else plistlib.FMT_XML
    path.write_bytes(plistlib.dumps(plist, fmt=fmt, sort_keys=False))


def verify_plist(path, values):
    plist = plistlib.loads(path.read_bytes())
    if plist.get('GADApplicationIdentifier') != values.get('ADMOB_APP_ID_IOS', TEST['ADMOB_APP_ID_IOS']):
        raise ValueError('native and Dart app IDs differ')
    if plist.get('CFBundleIdentifier') != 'com.crazypenguin.kamubul':
        raise ValueError('unexpected application bundle')
    if not plist.get('NSUserTrackingUsageDescription') or not plist.get('SKAdNetworkItems'):
        raise ValueError('missing native privacy configuration')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['xcode-defines', 'xcode-plist', 'prepare', 'verify-plist'])
    parser.add_argument('--input')
    parser.add_argument('--ads-input')
    parser.add_argument('--output')
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--plist')
    args = parser.parse_args()
    if args.action in ('prepare', 'verify-plist'):
        values = json.loads(Path(args.input).read_text(encoding='utf-8-sig'))
        if args.ads_input:
            ads = json.loads(Path(args.ads_input).read_text(encoding='utf-8-sig'))
            if set(ads) != set(TEST):
                raise ValueError('ads input must contain exactly the five iOS AdMob keys')
            values.update(ads)
        values = configure(values, release=not args.test)
        if args.action == 'verify-plist':
            verify_plist(Path(args.plist), values)
            print('Built iOS bundle: AdMob ID and privacy configuration verified.')
            return
        Path(args.output).write_text(json.dumps(values), encoding='utf-8')
        return
    values = configure(decode(os.environ.get('DART_DEFINES', '')),
                       release=os.environ.get('FLUTTER_BUILD_MODE', os.environ.get('CONFIGURATION', '').lower()) == 'release',
                       simulator=os.environ.get('PLATFORM_NAME') == 'iphonesimulator')
    if args.action == 'xcode-defines':
        print(encode(values))
    else:
        patch_plist(Path(os.environ['TARGET_BUILD_DIR']) / os.environ['INFOPLIST_PATH'], values)


if __name__ == '__main__':
    main()
