#!/usr/bin/env python3
"""One-time v109 feature-branch import, never a live deployment or rollback tool."""
from pathlib import Path, PurePosixPath
import base64
import hashlib
import json
import lzma
import re
import subprocess
import tempfile

BASE_COMMIT = 'a0f5eb059f4ca4b2c3bede2880783c64cbaad230'
BASE_SHA = '91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8'
BASE_BLOB = '50f2d0a8bfb7fda523409aa224ff2351386609ad'
PAYLOAD_SHA = 'f307dbe0859776ce553f8ef52c5d097cb609c3fbf5fa323733f60a6bb0f00628'
TARGET_SHA = '49178287e6e7d05d317b6f497807cee6193f1867a090e187b99d710e8622c6db'
TARGET_BLOB = '3b853b01c2e5d33c1cb92545d6b118893079f482'
TARGET_SIZE = 36236165
EXPECTED_FILES = {
    'fatebound-source.json', 'fatebound-source.sha256', 'README.md', 'AGENTS.md',
    'GROKBOT_HANDOFF.md', 'multiplayer/src/arena-engine.js',
    'multiplayer/src/arena-server.js', 'multiplayer/src/arena-client.js',
    'multiplayer/src/adventure.css', 'multiplayer/src/metrics.js',
    'multiplayer/tools/sync-inline.py', 'multiplayer/tests/server.test.js',
    'multiplayer/tests/browser_tests.py', 'multiplayer/tests/harness-server.js',
    'multiplayer/deploy/fatebound-arena.service',
    'multiplayer/deploy/fatebound-arena.env.example',
    'multiplayer/deploy/caddy-route.fragment', 'multiplayer/docs/FEATURES.md',
    'multiplayer/docs/DEPLOYMENT.md', 'multiplayer/docs/TEST_REPORT.md',
    'multiplayer/docs/browser-tests.json', 'multiplayer/docs/server-tests.txt',
    'multiplayer/docs/integrity.json'
}

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git_blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def reconstruct(base, parts):
    require(sha(base) == BASE_SHA and git_blob(base) == BASE_BLOB, 'Incorrect immutable v108 base')
    encoded = ''.join((parts / f'part{i}.b64').read_text().strip() for i in range(1, 6))
    require(len(encoded) == 61804 and sha(encoded.encode()) == PAYLOAD_SHA, 'Transport checksum mismatch')
    data = json.loads(lzma.decompress(base64.b64decode(encoded, validate=True)))
    require(data['format'] == 'fatebound-v109-line-delta-v1', 'Wrong payload format')
    require(data['base_commit'] == BASE_COMMIT and data['base_sha256'] == BASE_SHA and data['base_git_blob'] == BASE_BLOB, 'Wrong base metadata')
    require(data['target_sha256'] == TARGET_SHA and data['target_bytes'] == TARGET_SIZE and data['target_git_blob'] == TARGET_BLOB, 'Wrong target metadata')
    lines = base.decode('utf-8').splitlines(keepends=True)
    result = []
    for op in data['ops']:
        if isinstance(op, list):
            require(len(op) == 2 and all(type(n) is int for n in op) and 0 <= op[0] <= op[1] <= len(lines), 'Bad copy range')
            result.append(''.join(lines[op[0]:op[1]]))
        else:
            require(isinstance(op, str), 'Bad insertion')
            result.append(op)
    text = ''.join(result)
    source = text.encode('utf-8')
    require(len(source) == TARGET_SIZE and sha(source) == TARGET_SHA and git_blob(source) == TARGET_BLOB, 'Reconstructed source mismatch')
    assets = lambda value: re.findall(rb'[A-Za-z0-9+/=]{2000,}', value)
    require(len(assets(source)) == 103 and assets(base) == assets(source), 'Embedded artwork changed')
    require('<meta name="fatebound-build" content="109-adventure-matchmaking-preview">' in text, 'Wrong HTML marker')
    require('const WAR_SESSION_BUILD=106;' in text and 'fatebound-save' in text, 'Save compatibility changed')
    require(set(data['files']) == EXPECTED_FILES, 'Unexpected or missing output files')
    for name, value in data['files'].items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts and isinstance(value, str), 'Unsafe output path/content')
    manifest = json.loads(data['files']['fatebound-source.json'])
    require(manifest['sha256'] == TARGET_SHA and manifest['bytes'] == TARGET_SIZE and manifest['live_activation'] == 'pending-remote-connection', 'Manifest mismatch')
    browser = json.loads(data['files']['multiplayer/docs/browser-tests.json'])
    require(browser['sourceSha256'] == TARGET_SHA and len(browser['checks']) == 23, 'Report is not for this source')
    require(all(c['status'] == 'PASS' for c in browser['checks']) and not browser['pageErrors'] and not browser['consoleErrors'], 'Prior browser tests did not pass')
    scripts = [code for code in re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>', text, re.S | re.I) if code.strip()]
    require(len(scripts) == 20, 'Wrong inline script count')
    with tempfile.TemporaryDirectory() as folder:
        for i, code in enumerate(scripts):
            path = Path(folder) / f'inline-{i}.js'
            path.write_text(code, encoding='utf-8')
            subprocess.run(['node', '--check', str(path)], check=True, capture_output=True)
    return source, data['files']

def main():
    root = Path(__file__).resolve().parents[2]
    current = (root / 'fatebound.html').read_bytes()
    require(sha(current) in (BASE_SHA, TARGET_SHA), 'Branch source moved; reconcile instead of overwriting')
    base = subprocess.check_output(['git', 'show', BASE_COMMIT + ':fatebound.html'], cwd=root)
    source, files = reconstruct(base, root / 'patches/v109')
    # No repository writes occur until all exact-source checks above pass.
    (root / 'fatebound.html').write_bytes(source)
    for name, value in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf-8')
    subprocess.run(['python3', 'multiplayer/tools/sync-inline.py', '--root', '.'], cwd=root, check=True)
    test = subprocess.run(['node', '--test', 'multiplayer/tests/server.test.js'], cwd=root, check=True, capture_output=True, text=True)
    require('# pass 16' in test.stdout and '# fail 0' in test.stdout, 'Server test count mismatch')
    print(test.stdout)
    summary = {
        'source_sha256': TARGET_SHA, 'source_bytes': TARGET_SIZE, 'git_blob_sha1': TARGET_BLOB,
        'inline_scripts_parsed_here': 20, 'server_tests_rerun_here': 16,
        'prior_local_browser_checks': 23, 'browser_tests_rerun_by_import': False,
        'embedded_assets_unchanged': 103, 'live_deployed': False,
        'target_branch': 'chatgpt/v109-adventure-matchmaking', 'main_updated': False
    }
    (root / 'multiplayer/docs/import-verification.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    main()
