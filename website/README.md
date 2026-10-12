# Public homepage

`website/` builds a static, English-default homepage for `/`, `/ru/`, and `/uz/`.
The build uses Python 3.10+ and the standard library. No package install or
production runtime is needed. The checked-in logo and social cards derive from
the real app icon in `frontend/assets/app_icon.png`; the hero is an original SVG
illustration. `website/tool/render_social.py` can regenerate the small logo and
social cards with Pillow if the brand artwork changes.

```powershell
python website/build.py
python -m unittest discover -s website -p 'test_*.py' -v
node website/test_interactions.js  # optional interaction check; not needed to build
python website/tool/check_flutter_bundle.py frontend/build/web
python website/tool/check_nginx_http.py --flutter frontend/build/web --website website/dist --report .data/nginx-http.json
python -m http.server 8765 --directory website/dist
```

Open `http://localhost:8765/`, `/ru/`, or `/uz/` for a site-only preview. This
Python server does not provide Flutter routes, API proxying, or production
headers. The generated output is `website/dist/` (ignored by Git): `index.html`,
`ru/index.html`, `uz/index.html`, `robots.txt`, `sitemap.xml`, and hashed files
under `landing-assets/`. A build recreates only that ignored directory. Do not
copy its contents into `frontend/build/web`.

The HTML includes all content and metadata before JavaScript. The small script
only toggles the menu and theme, and stores the chosen theme in local storage.
Language selection is represented by a stable URL, so bookmarks and copied
links retain the chosen language without JavaScript. The homepage does not
register a service worker and does not use the Flutter manifest. The existing
manifest launches the installed web app at `/feed`.

Nginx mounts `website/dist` at `/var/www/landing` and serves exact homepage
routes from it. `/landing-assets/` is the only landing asset prefix. Flutter
stays under `/usr/share/nginx/html`, with its existing route fallback, API and
media proxies, legal files, and CanvasKit assets. Homepage HTML is `no-store`;
successful hashed assets are immutable; missing landing assets are `no-store`.
The production CSP is inherited unchanged by
landing responses, and there are no new external origins. The JSON-LD block is
non-executable structured data.

Search Console is an operator task after release: verify
`https://mushukistan.uz/` ownership, submit
`https://mushukistan.uz/sitemap.xml`, inspect the three canonical homepage
URLs, and monitor indexing. No Search Console access or verification is part of
this implementation. The sitemap contains only the three homepage URLs. The
robots file allows existing legal pages; the Flutter shell has `noindex,follow`
to avoid indexing many deep links with identical startup HTML.

For integrated local testing, build a Flutter web bundle in this worktree and
use an isolated Nginx container with `infrastructure/nginx/local.conf`, mounting
both generated outputs read-only. Use a private port and a disposable container
name. Do not recreate the shared Compose project or mount its live release.

## Real application showcase

The four Android previews use only the reviewed derivatives under
`src/screenshots/`. See `SCREENSHOTS.md` for the owner-confirmed photograph
rights, crop/redaction recipe, private source handling, and exact reproduction
command. The static build verifies their review hashes and copies an explicit
allowlist; it does not publish the source captures or review manifest.
WebP/JPEG sources at 270px and 540px use native image ratios, lazy loading, and
reserved dimensions. The mobile gallery uses CSS scroll snapping and native
keyboard/touch scrolling, with no carousel script or autoplay.

The browser gate requires Chrome and the small development dependency in
`tool/requirements-browser.txt`:

```powershell
python -m pip install -r website/tool/requirements-assets.txt -r website/tool/requirements-browser.txt
python -m unittest discover -s website -p 'test_*.py' -v
node website/test_interactions.js
python website/tool/check_browser.py --report .data/browser-after/results.json
python website/tool/check_browser.py --origin https://mushukistan.uz --capture-only --report .data/browser-before/results.json
```

The browser gate starts an isolated static preview when `--origin` is omitted.
It checks EN/RU/UZ at desktop, tablet, and touch-sized viewports, measures hero
CTA visibility and contrast, tests native arrow-key/touch snapping and reduced
motion, checks image geometry and layout shifts, and saves light/dark screenshots.
`--capture-only` records a baseline without requiring the new showcase to exist.
Use `--chrome` if Chrome has a different local path. After deployment, run it
against the real HTTPS origin without `--capture-only`.

For this website-only refinement, preserve the complete deployed Flutter bundle
and verify all its hashes instead of rebuilding Flutter. Mount that preserved
directory in the HTTP gate. See the website-only procedure in
`docs/DEPLOYMENT.md`; unrelated application services must not be replaced.

The HTTP harness above tests the production HTTPS configuration against complete
built artifacts on random localhost ports. It requires Docker, Python
`cryptography`, and the Nginx/Python images listed in `docs/DEPLOYMENT.md`.
After an authorized release, `website/tool/check_production_http.py` accepts
the same artifact/report arguments and compares the real public HTTPS
responses to the validated release. Neither harness uses account credentials.
