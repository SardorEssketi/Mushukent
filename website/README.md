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
hashed assets are immutable. The production CSP is inherited unchanged by
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
