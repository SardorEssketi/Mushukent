"""Verify the isolated Flutter web bundle keeps required launch assets."""

from __future__ import annotations

import json
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: python website/tool/check_flutter_bundle.py <web-bundle-directory>")

bundle = Path(sys.argv[1]).resolve()
shell = (bundle / "index.html").read_text(encoding="utf-8")
bootstrap = (bundle / "flutter_bootstrap.js").read_text(encoding="utf-8")
manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
required = ["main.dart.js", "canvaskit", "assets", "flutter_bootstrap.js"]
for name in required:
    assert (bundle / name).exists(), f"Missing Flutter artifact: {name}"
assert '<base href="/">' in shell, "Flutter base href changed"
assert 'name="robots" content="noindex,follow"' in shell
assert manifest["start_url"] == "/feed" and manifest["scope"] == "/"
assert '"useLocalCanvasKit":true' in bootstrap
assert "retireLegacyFlutterServiceWorker" in bootstrap
assert "flutter-first-frame" in bootstrap
assert not (bundle / "landing-assets").exists(), "Landing assets collided with Flutter"
print(f"Flutter bundle compatibility verified: {bundle}")
