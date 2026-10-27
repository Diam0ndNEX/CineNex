#!/usr/bin/env python3
"""Reject an IPA whose processed configuration or primary icon is missing."""
import json
from pathlib import Path
import plistlib
import sys


def verify_info(info, expected):
    for key, value in expected.items():
        actual = info.get(key, '')
        if actual != value:
            raise ValueError(f'Built app is missing or has incorrect {key}; check Info.plist expansion')
    schemes = [scheme for entry in info.get('CFBundleURLTypes', [])
               for scheme in entry.get('CFBundleURLSchemes', [])]
    if 'cinenex' not in schemes:
        raise ValueError('Built app is missing its account callback URL scheme')
    icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
    if icon.get('CFBundleIconName') != 'AppIcon' or not icon.get('CFBundleIconFiles'):
        raise ValueError('Built app is missing its primary AppIcon')


def main():
    app = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    expected = json.loads((root / 'Generated/AccountApplications.json').read_text())
    verify_info(plistlib.loads((app / 'Info.plist').read_bytes()), expected)
    print('Verified packaged account settings, callback scheme and primary icon.')


if __name__ == '__main__':
    main()
