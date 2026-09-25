#!/usr/bin/env python3
"""Fatebound legacy web/save host. Loopback only; explicit public routes.

Save IDs remain the existing device capability for compatibility, NOT account
login. This server must not serve its working directory, source, logs or saves.
Arena authentication/combat authority remains in the separate Node service.
"""
import argparse
import json
import os
import re
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

SAFE_ID = re.compile(r"[A-Za-z0-9._-]{3,64}")
MAX_SAVE_BYTES = 2_000_000
INJECT = ('<script>window.FATEBOUND_SERVER='
          'window.location.pathname.startsWith("/fatebound")'
          '?window.location.origin+"/fatebound":window.location.origin;'
          '</script><script src="fatebound-client.js"></script>')
PUBLIC_FILES = {
    '/fatebound-client.js': ('fatebound-client.js', 'text/javascript; charset=utf-8'),
    '/privacy.html': ('privacy.html', 'text/html; charset=utf-8'),
    '/fatebound-version.json': ('fatebound-version.json', 'application/json'),
}

class Handler(BaseHTTPRequestHandler):
    root = Path.cwd()
    saves_dir = Path('saves')
    allowed_origins = {'https://136-113-125-3.sslip.io', 'null'}
    save_lock = threading.Lock()
    html_lock = threading.Lock()
    html_cache = None

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def _allowed(self):
        origin = self.headers.get('Origin')
        return origin is None or origin in self.allowed_origins

    def _send(self, code, blob=b'', kind='application/json'):
        self.send_response(code)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(blob)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        origin = self.headers.get('Origin')
        if origin and self._allowed():
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')
        self.end_headers()
        if self.command != 'HEAD':
            try:
                self.wfile.write(blob)
            except (BrokenPipeError, ConnectionResetError):
                pass  # A client closing a download must not create an error loop.

    def _json(self, code, obj):
        self._send(code, json.dumps(obj).encode('utf-8'))

    def do_OPTIONS(self):
        if not self._allowed():
            return self._json(403, {'ok': False, 'error': 'origin not allowed'})
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', self.headers.get('Origin', 'null'))
        self.send_header('Vary', 'Origin')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET,HEAD,POST,OPTIONS')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_HEAD(self):
        # Same exact route allowlist as GET; never fall back to a filesystem handler.
        self.do_GET()

    def do_GET(self):
        if not self._allowed():
            return self._json(403, {'ok': False, 'error': 'origin not allowed'})
        parsed = urlsplit(self.path)
        route = parsed.path
        if route == '/health':
            return self._json(200, {'ok': True, 'game': 'Fatebound', 'webBuild': 110})
        if route in ('/api/save', '/api/save/'):
            pid = (parse_qs(parsed.query).get('playerId') or [''])[0]
            path = self._save_path(pid)
            if path is None:
                return self._json(400, {'ok': False, 'error': 'bad playerId'})
            try:
                with self.save_lock:
                    data = json.loads(path.read_text(encoding='utf-8'))
            except FileNotFoundError:
                return self._json(404, {'ok': False, 'error': 'no save'})
            except (OSError, ValueError):
                return self._json(503, {'ok': False, 'error': 'save temporarily unavailable'})
            return self._json(200, {'ok': True, 'save': data.get('save'), 'playerId': pid})
        if route in ('/', '/index.html', '/fatebound.html'):
            return self._game_html()
        if route in PUBLIC_FILES:
            name, kind = PUBLIC_FILES[route]
            try:
                blob = (self.root / name).read_bytes()
            except OSError:
                return self._json(404, {'ok': False, 'error': 'not found'})
            return self._send(200, blob, kind)
        # Deliberately no directory listing, path translation or percent-decoded fallback.
        return self._json(404, {'ok': False, 'error': 'not found'})

    def do_POST(self):
        if not self._allowed():
            return self._json(403, {'ok': False, 'error': 'origin not allowed'})
        if urlsplit(self.path).path not in ('/api/save', '/api/save/'):
            return self._json(404, {'ok': False, 'error': 'not found'})
        if self.headers.get('Transfer-Encoding'):
            return self._json(400, {'ok': False, 'error': 'unsupported transfer encoding'})
        try:
            length = int(self.headers.get('Content-Length', '-1'))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_SAVE_BYTES:
            return self._json(413 if length > MAX_SAVE_BYTES else 400,
                              {'ok': False, 'error': 'invalid save length'})
        try:
            body = json.loads(self.rfile.read(length).decode('utf-8'))
            if not isinstance(body, dict):
                raise ValueError('object required')
            save = body.get('save')
            decoded = json.loads(save) if isinstance(save, str) else save
            if not isinstance(decoded, dict):
                raise ValueError('save object required')
        except (ValueError, UnicodeError, TimeoutError):
            return self._json(400, {'ok': False, 'error': 'bad save JSON'})
        pid = body.get('playerId')
        path = self._save_path(pid)
        if path is None:
            return self._json(400, {'ok': False, 'error': 'bad playerId'})
        payload = {'playerId': pid, 'game': 'fatebound', 'save': save}
        tmp = None
        try:
            with self.save_lock:
                self.saves_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                # Unique temp files + a lock prevent concurrent writes sharing .tmp.
                fd, tmp = tempfile.mkstemp(prefix='.save-', dir=self.saves_dir)
                with os.fdopen(fd, 'w', encoding='utf-8') as handle:
                    json.dump(payload, handle)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(tmp, path)
            return self._json(200, {'ok': True})
        except OSError:
            return self._json(503, {'ok': False, 'error': 'save not written; retry'})
        finally:
            if tmp and os.path.exists(tmp):
                os.unlink(tmp)

    def _game_html(self):
        try:
            path = self.root / 'fatebound.html'
            stat = path.stat()
            key = (str(path), stat.st_mtime_ns, stat.st_size)
            with self.html_lock:
                cache = type(self).html_cache
                if not cache or cache[0] != key:
                    text = path.read_text(encoding='utf-8')
                    if 'fatebound-client.js' not in text:
                        text = text.replace('</head>', INJECT + '</head>', 1)
                    cache = (key, text.encode('utf-8'))
                    type(self).html_cache = cache
            return self._send(200, cache[1], 'text/html; charset=utf-8')
        except OSError:
            return self._json(503, {'ok': False, 'error': 'game temporarily unavailable'})

    def _save_path(self, pid):
        if not isinstance(pid, str) or not SAFE_ID.fullmatch(pid):
            return None
        return self.saves_dir / (pid + '.json')

    def log_message(self, fmt, *args):
        # Avoid putting save-capability query strings in access logs.
        sys.stderr.write('%s %s %s\n' % (self.command, urlsplit(self.path).path,
                                         args[1] if len(args) > 1 else ''))

class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dir', default='.')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--saves', default='saves')
    args = parser.parse_args()
    Handler.root = Path(args.dir).resolve()
    Handler.saves_dir = Path(args.saves).resolve()
    Handler.allowed_origins = set(os.environ.get('FATEBOUND_WEB_ORIGINS',
        'https://136-113-125-3.sslip.io,null').split(','))
    server = Server(('127.0.0.1', args.port), Handler)
    print(f'Fatebound web v110 on 127.0.0.1:{args.port}; public-file allowlist enabled', flush=True)
    server.serve_forever()
