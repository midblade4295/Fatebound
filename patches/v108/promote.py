#!/usr/bin/env python3
"""One-time exact import of the user-approved v108 artifact. Not a gameplay patch.
The transport delta uses an immutable, hash-verified historical blob only to
avoid transferring the unchanged embedded assets. The resulting SHA-256 must
match the approved file before any repository output is written.
"""
from pathlib import Path
import base64
import hashlib
import json
import lzma
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PARTS = ROOT / 'patches/v108'
EXPECTED_PAYLOAD = '0b697d8de377abde5a8d765df3d373fa91b1ba524b4254f9dec5bcee12f89388'
EXPECTED_TARGET = '91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8'
EXPECTED_BLOB = '50f2d0a8bfb7fda523409aa224ff2351386609ad'
EXPECTED_SIZE = 36175422
BASE_COMMIT = '8df6bc60215c8a29ba08cbb6fb95251783f41e2d'
BASE_BLOB = 'd50d7758a7934ed0f0050a0ccd5f76863c1a01d2'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    encoded = ''.join((PARTS / f'part{i}.b64').read_text().strip() for i in (1, 2, 3))
    if sha((encoded + '\n').encode()) != EXPECTED_PAYLOAD:
        raise RuntimeError('Transport checksum mismatch; refusing to change the source')
    data = json.loads(lzma.decompress(base64.b64decode(encoded, validate=True)))
    assert data['format'] == 'fatebound-line-delta-v1'
    assert data['base_commit'] == BASE_COMMIT and data['base_git_blob'] == BASE_BLOB
    assert data['target_sha256'] == EXPECTED_TARGET
    subprocess.run(['git', 'fetch', '--no-tags', 'origin', BASE_COMMIT], cwd=ROOT, check=True)
    base = subprocess.check_output(['git', 'show', BASE_COMMIT + ':fatebound.html'], cwd=ROOT)
    assert sha(base) == data['base_sha256'], 'Base source checksum mismatch'
    blob = hashlib.sha1(b'blob ' + str(len(base)).encode() + b'\0' + base).hexdigest()
    assert blob == BASE_BLOB
    lines = base.splitlines(keepends=True)
    result = []
    for op in data['ops']:
        if isinstance(op, list):
            assert len(op) == 2 and 0 <= op[0] <= op[1] <= len(lines)
            result.append(b''.join(lines[op[0]:op[1]]))
        else:
            assert isinstance(op, str)
            result.append(op.encode('utf-8'))
    source = b''.join(result)
    assert len(source) == EXPECTED_SIZE, 'Wrong output size'
    assert sha(source) == EXPECTED_TARGET, 'Wrong output SHA-256'
    blob = hashlib.sha1(b'blob ' + str(len(source)).encode() + b'\0' + source).hexdigest()
    assert blob == EXPECTED_BLOB, 'Wrong output Git blob'
    text = source.decode('utf-8')
    assert '<meta name="fatebound-build" content="108-season-pass-modal-copy-fix">' in text
    assert 'const WAR_SESSION_BUILD=106;' in text
    for marker in ('id="hubPortrait"', 'id="hubScene"', 'Raid monster', 'fatebound-save', 'data-hub="hero"'):
        assert marker in text, 'Missing full-source marker: ' + marker
    scripts = [s for s in re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>', text, flags=re.S | re.I) if s.strip()]
    assert len(scripts) == 18, 'Unexpected inline script count'
    with tempfile.TemporaryDirectory() as folder:
        for i, code in enumerate(scripts):
            path = Path(folder) / f'script-{i}.js'
            path.write_text(code, encoding='utf-8')
            subprocess.run(['node', '--check', str(path)], check=True, capture_output=True)
    # All verification above completes before writing the canonical file.
    (ROOT / 'fatebound.html').write_bytes(source)
    report_path = 'docs/fatebound-v108-season-pass-test-report.md'
    report = data['files'][report_path]
    (ROOT / 'docs').mkdir(exist_ok=True)
    (ROOT / report_path).write_text(report, encoding='utf-8')
    manifest = {
        'canonical_file': 'fatebound.html',
        'source_of_truth_branch': 'main',
        'html_version': 108,
        'build_marker': '108-season-pass-modal-copy-fix',
        'bytes': EXPECTED_SIZE,
        'sha256': EXPECTED_TARGET,
        'git_blob_sha1': EXPECTED_BLOB,
        'save_key': 'fatebound-save',
        'battle_session_compatibility': 106,
        'approved_artifact': 'fatebound-v108-season-pass-fix.html',
        'handoff': 'GROKBOT_HANDOFF.md',
        'runtime_test_report': report_path,
        'note': 'HTML v108 is not the Android versionCode. This import does not change Android packaging or publish a Play release.'
    }
    (ROOT / 'fatebound-source.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (ROOT / 'fatebound-source.sha256').write_text(EXPECTED_TARGET + '  fatebound.html\n')
    summary = {
        'source_sha256': EXPECTED_TARGET,
        'source_bytes': EXPECTED_SIZE,
        'git_blob_sha1': EXPECTED_BLOB,
        'inline_scripts_parsed': len(scripts),
        'exact_approved_artifact': True,
        'android_packaging_changed': False,
        'new_runtime_tests_run_by_import': False,
        'existing_runtime_report_preserved': report_path
    }
    print(json.dumps(summary, indent=2))
    (ROOT / 'docs/v108-import-verification.json').write_text(json.dumps(summary, indent=2) + '\n')

if __name__ == '__main__':
    main()
