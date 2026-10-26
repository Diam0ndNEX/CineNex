"""Choose CI work conservatively from the complete PR diff."""
import json
import os
from pathlib import Path
import subprocess


def plan(paths, full=False, ipa=False):
    paths = list(paths)
    docs_only = bool(paths) and all(p.endswith(('.md', '.txt')) or p.startswith('Docs/') for p in paths)
    build = full or ipa or not docs_only
    native = full or any(p.startswith(('Thirdparty/', 'Scripts/', '.github/')) or p in ('project.yml', '.gitmodules') for p in paths)
    # Only presentation files with no provider, persistence or routing code are exempt.
    presentation = {'CineNex/Features/Home/AppearanceSettingsView.swift', 'CineNex/Features/Home/CachedPosterImage.swift'}
    tests = full or (build and any(p not in presentation and not '.xcassets/' in p for p in paths))
    return {'build': build, 'tests': tests, 'native_tests': native, 'ipa': ipa and build}


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    kind = os.environ['GITHUB_EVENT_NAME']
    manual = event.get('inputs', {})
    labels = {label['name'] for label in event.get('pull_request', {}).get('labels', [])}
    full = kind != 'pull_request' or 'ci:full' in labels or not event['pull_request'].get('draft', False)
    ipa = kind == 'push' or 'ci:ipa' in labels or manual.get('build_ipa') in (True, 'true')
    if kind == 'pull_request':
        pr = event['pull_request']
        result = subprocess.run(['git', 'diff', '--name-only', '-z', pr['base']['sha'] + '...' + pr['head']['sha']], check=True, capture_output=True)
        paths = result.stdout.decode().strip('\0').split('\0') if result.stdout else []
    else:
        paths = []
    result = plan(paths, full, ipa)
    print(json.dumps(result, indent=2))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for name, value in result.items():
            output.write(f'{name}={str(value).lower()}\n')


if __name__ == '__main__':
    main()
