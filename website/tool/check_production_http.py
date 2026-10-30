"""Read-only HTTPS smoke checks against a release's complete local artifacts.

No authentication, writes, credentials, or TLS bypasses are used. Redirects are
bounded by urllib's default handler. Run after switching the release directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--website', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--origin', default='https://mushukistan.uz')
    args = parser.parse_args()
    origin = args.origin.rstrip('/')
    report = {'origin': origin, 'passed': False, 'checks': []}
    config = Path(__file__).resolve().parents[2] / 'infrastructure/nginx/default.conf'
    expected_csp = re.findall(r'add_header Content-Security-Policy "([^"]+)" always;', config.read_text())[0]

    def fetch(url: str) -> tuple[int, dict, bytes, str]:
        request = Request(url, headers={'User-Agent': 'Mushukistan-release-verification/1.0'})
        try:
            response = urlopen(request, timeout=45)
        except HTTPError as error:
            response = error
        with response:
            return (response.status, {k.lower(): v for k, v in response.headers.items()},
                    response.read(), response.url)

    def check_file(path: str, file: Path, cache: str | None = None) -> None:
        status, headers, data, final = fetch(origin + path)
        assert status == 200, (path, status)
        assert final == origin + path, (path, final)
        assert data == file.read_bytes(), f'Artifact differs at {path}'
        assert headers.get('content-security-policy') == expected_csp, path
        assert headers.get('x-content-type-options') == 'nosniff', path
        assert headers.get('x-frame-options') == 'DENY', path
        assert headers.get('referrer-policy') == 'strict-origin-when-cross-origin', path
        assert 'max-age=31536000' in headers.get('strict-transport-security', ''), path
        if cache:
            assert cache in headers.get('cache-control', ''), (path, headers)
        report['checks'].append({'path': path, 'status': status,
                                 'sha256': hashlib.sha256(data).hexdigest(),
                                 'cache_control': headers.get('cache-control'),
                                 'edge_cache': headers.get('cf-cache-status')})

    try:
        for path, relative in [('/', 'index.html'), ('/en/', 'en/index.html'), ('/uz/', 'uz/index.html')]:
            check_file(path, args.website / relative, 'no-store')
        for path in ['/feed', '/map', '/posts/release-probe', '/lost-pets/release-probe',
                     '/adoption-posts/release-probe', '/users/release-probe', '/login', '/register',
                     '/verify-email', '/notifications', '/notifications/settings', '/profile/settings',
                     '/legal/terms', '/unknown-release-probe']:
            check_file(path, args.flutter / 'index.html', 'no-store')
        for path in ['privacy', 'child-safety', 'delete-account']:
            check_file('/' + path, args.flutter / path / 'index.html')
        for path in ['flutter_bootstrap.js', 'version.json', 'delete-account/delete-account.js']:
            check_file('/' + path, args.flutter / path, 'no-store')
        for path in ['main.dart.js', 'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm', 'manifest.json']:
            check_file('/' + path, args.flutter / path, 'no-cache')
        manifest = json.loads(fetch(origin + '/manifest.json')[2])
        assert manifest['start_url'] == '/feed' and manifest['scope'] == '/'
        for path in ['robots.txt', 'sitemap.xml']:
            check_file('/' + path, args.website / path, 'no-store')
        for file in sorted((args.website / 'landing-assets').iterdir()):
            check_file('/landing-assets/' + file.name, file, 'immutable')
        for path in ['/landing-assets/missing-release-probe.js', '/missing-release-probe.js']:
            status, headers, data, _ = fetch(origin + path)
            assert status == 404 and b'flutter-startup' not in data, path
            if path.startswith('/landing-assets/'):
                assert 'no-store' in headers.get('cache-control', ''), path
            report['checks'].append({'path': path, 'status': status})
        for path in ['/en', '/uz']:
            status, _, _, final = fetch(origin + path)
            assert status == 200 and final == origin + path + '/', (path, status, final)
            report['checks'].append({'path': path, 'status': status, 'final': final})
        for path in ['/ru', '/ru/']:  # legacy Russian URLs now redirect to the root
            status, _, _, final = fetch(origin + path)
            assert status == 200 and final == origin + '/', (path, status, final)
            report['checks'].append({'path': path, 'status': status, 'final': final})
        for url in [origin + '/health', origin + '/api/v1/health', 'https://api.mushukistan.uz/api/v1/health']:
            status, _, data, _ = fetch(url)
            value = json.loads(data)
            assert status == 200 and value['success'] and value['data']['status'] == 'ok', url
            report['checks'].append({'url': url, 'status': status})
        status, _, data, _ = fetch('https://api.mushukistan.uz/api/v1/notifications')
        assert status in (401, 403) and b'<html' not in data.lower(), status
        report['checks'].append({'path': 'unauthenticated notification API', 'status': status})
        report['passed'] = True
        print(f"Passed {len(report['checks'])} public HTTPS checks; artifact hashes match the validated release.")
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
