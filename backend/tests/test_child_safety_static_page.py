from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CHILD_SAFETY_PAGE = REPO_ROOT / "frontend" / "web" / "child-safety" / "index.html"
NGINX_CONF = REPO_ROOT / "infrastructure" / "nginx" / "default.conf"


def test_child_safety_page_static_file_is_public_submission_page():
    html = CHILD_SAFETY_PAGE.read_text(encoding="utf-8")

    assert "<title>Mushukistan Child Safety Standards</title>" in html
    assert 'href="https://mushukistan.uz/child-safety"' in html
    assert "zero tolerance for child sexual abuse and exploitation" in html
    assert "Child safety / exploitation" in html
    assert "Lost-pet and adoption posts" in html
    assert "sardor.datascience@gmail.com" in html
    assert 'id="english"' in html
    assert 'id="russian"' in html
    assert 'id="uzbek"' in html
    assert "external website or send email" in html


def test_nginx_serves_child_safety_without_auth_or_api_proxy():
    config = NGINX_CONF.read_text(encoding="utf-8")

    start = config.index("location = /child-safety")
    end = config.index("location /health", start)
    block = config[start:end]

    assert "try_files /child-safety/index.html =404;" in block
    assert "auth" not in block.lower()
    assert "proxy_pass" not in block
