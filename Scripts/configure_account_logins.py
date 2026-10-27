#!/usr/bin/env python3
"""Prepare public OAuth build configuration without putting secrets in an IPA."""
import json
import os
import plistlib
import re
from pathlib import Path
from urllib.parse import urlsplit

CLIENT_KEYS = ('CINENEX_ANILIST_CLIENT_ID', 'CINENEX_MAL_CLIENT_ID', 'CINENEX_TRAKT_CLIENT_ID')
REDIRECT_KEY = 'CINENEX_TRAKT_REDIRECT_URI'

def build_configuration(values):
    cleaned = {}
    for key in CLIENT_KEYS:
        value = values.get(key, '').strip()
        if value and not re.fullmatch(r'[A-Za-z0-9._-]{1,256}', value):
            raise ValueError('Invalid public application ID: ' + key)
        cleaned[key] = value
    redirect = values.get(REDIRECT_KEY, '').strip()
    domains = []
    if redirect:
        parsed = urlsplit(redirect)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.hostname in ('localhost', '127.0.0.1', '::1') or parsed.username or parsed.password
            or parsed.port is not None or parsed.query or parsed.fragment
            or not re.fullmatch(r'[A-Za-z0-9./_%~:-]+', redirect)
            or not parsed.path.startswith('/')):
            raise ValueError('Trakt redirect must be a clean HTTPS callback on an owned domain')
        domains = ['applinks:' + parsed.hostname]
    cleaned[REDIRECT_KEY] = redirect
    # xcconfig treats // as a comment; the empty expansion preserves the HTTPS separator.
    lines = ['// Generated public OAuth application settings. No client secrets.']
    lines += [key + ' = ' + value.replace('://', ':/$()/') for key, value in cleaned.items()]
    return '\n'.join(lines) + '\n', ({'com.apple.developer.associated-domains': domains} if domains else {})

def main():
    root = Path(__file__).resolve().parent.parent
    values = json.loads((root / 'Config/AccountApplications.json').read_text())
    for key in (*CLIENT_KEYS, REDIRECT_KEY):
        if os.environ.get(key):
            values[key] = os.environ[key]
    config, entitlements = build_configuration(values)
    generated = root / 'Generated'
    generated.mkdir(exist_ok=True)
    (generated / 'OAuth.xcconfig').write_text(config)
    # Public expected values let CI verify the processed app, not just build inputs.
    (generated / 'AccountApplications.json').write_text(json.dumps(
        {key: values.get(key, '').strip() for key in (*CLIENT_KEYS, REDIRECT_KEY)}, indent=2))
    (generated / 'CineNex.entitlements').write_bytes(plistlib.dumps(entitlements))
    team = os.environ.get('CINENEX_APP_TEAM_ID', '').strip()
    if team:
        if not re.fullmatch(r'[A-Z0-9]{10}', team):
            raise ValueError('Invalid signing team ID')
        redirect = values.get(REDIRECT_KEY, '')
        if redirect:
            association = {'applinks': {'details': [{'appIDs': [team + '.com.diam0ndnex.cinenex'],
                             'components': [{'/': urlsplit(redirect).path}]}]}}
            (generated / 'apple-app-site-association').write_text(json.dumps(association, indent=2))
    print('Prepared public account-login build configuration; no credentials printed.')

if __name__ == '__main__':
    main()
