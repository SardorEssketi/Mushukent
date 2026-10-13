"""Headless Chrome layout, accessibility and native gallery release gate.

python website/tool/check_browser.py --report .data/browser-after/results.json
Add --origin https://mushukistan.uz --capture-only for baseline screenshots.
Requires Chrome and websocket-client 1.9.0; no browser/runtime package is shipped.
"""

from __future__ import annotations

import argparse
import base64
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from urllib.request import urlopen
import uuid

import websocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--origin")
    parser.add_argument("--capture-only", action="store_true")
    parser.add_argument("--chrome", default=r"C:\Program Files\Google\Chrome\Application\chrome.exe")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.report.resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    profile = output / ("chrome-" + uuid.uuid4().hex[:10])
    server = None
    if args.origin:
        origin = args.origin.rstrip("/")
    else:
        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=str(root / "website/dist"), **kw)
            def log_message(self, *a):
                pass
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.handle_error = lambda *a: None  # only this disposable server
        threading.Thread(target=server.serve_forever, daemon=True).start()
        origin = f"http://127.0.0.1:{server.server_port}"
    chrome = subprocess.Popen([args.chrome, "--headless=new", "--remote-debugging-port=0",
                               "--user-data-dir=" + str(profile), "--no-first-run",
                               "--no-default-browser-check", "--disable-background-networking", "about:blank"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    report = {"origin": origin, "capture_only": args.capture_only, "passed": False,
              "checks": [], "runtime_errors": []}
    ws = None
    try:
        for _ in range(100):
            active = profile / "DevToolsActivePort"
            if active.exists():
                break
            time.sleep(.2)
        port = active.read_text().splitlines()[0]
        targets = json.load(urlopen(f"http://127.0.0.1:{port}/json", timeout=10))
        target = next(t for t in targets if t["type"] == "page")
        ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
        counter = 0

        def cdp(method, params=None):
            nonlocal counter
            counter += 1
            ws.send(json.dumps({"id": counter, "method": method, "params": params or {}}))
            while True:
                value = json.loads(ws.recv())
                if value.get("method") == "Runtime.exceptionThrown":
                    report["runtime_errors"].append(value["params"]["exceptionDetails"])
                if value.get("id") == counter:
                    assert "error" not in value, value
                    return value.get("result", {})

        def evaluate(expression):
            value = cdp("Runtime.evaluate", {"expression": expression, "returnByValue": True})
            assert "exceptionDetails" not in value, value
            return value["result"].get("value")

        def wait(expression, timeout=20):
            end = time.time() + timeout
            while time.time() < end:
                if evaluate(expression):
                    return
                time.sleep(.15)
            raise AssertionError("Browser condition timed out: " + expression)

        def navigate(path):
            cdp("Page.navigate", {"url": origin + path})
            time.sleep(.25)
            wait("location.pathname === " + json.dumps(path) + ' && document.readyState === "complete"')

        def contrast():
            wait('''(() => {const hex=getComputedStyle(document.documentElement).getPropertyValue('--button').trim();const rgb='rgb('+[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)).join(', ')+')';return getComputedStyle(document.querySelector('.hero-actions .button-primary')).backgroundColor===rgb})()''')
            values = evaluate(r'''(() => {
              const rgb=s=>s.match(/[\d.]+/g).slice(0,3).map(Number);
              const l=c=>c.map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);
              return ['.hero-intro','.showcase-intro','.showcase-screen p','.button-primary'].map(selector=>{
                const node=document.querySelector(selector);let parent=node,bg;
                while(parent){bg=getComputedStyle(parent).backgroundColor;if(bg!=='rgba(0, 0, 0, 0)'&&bg!=='transparent')break;parent=parent.parentElement;}
                const a=l(rgb(getComputedStyle(node).color)),b=l(rgb(bg));
                return {selector,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
              });
            })()''')
            assert all(v["ratio"] >= 4.5 for v in values), values
            return values

        def screenshot(name, selector=None):
            options = {"format": "png", "captureBeyondViewport": bool(selector)}
            if selector:
                evaluate('document.activeElement.blur();document.querySelector(' + json.dumps(selector) + ').scrollIntoView({block:"start",behavior:"instant"})')
                time.sleep(.15)
                options["clip"] = evaluate('(() => {const r=document.querySelector(' + json.dumps(selector) + ').getBoundingClientRect();return {x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height,scale:1}})()')
            result = cdp("Page.captureScreenshot", options)
            (output / (name + ".png")).write_bytes(base64.b64decode(result["data"]))

        cdp("Page.enable")
        cdp("Runtime.enable")
        cdp("Page.addScriptToEvaluateOnNewDocument", {"source": "window.__landingCLS=0;new PerformanceObserver(list=>{for(const e of list.getEntries()) if(!e.hadRecentInput) window.__landingCLS+=e.value}).observe({type:'layout-shift',buffered:true});"})
        viewports = [(1280, 720), (1366, 768), (1440, 900), (1024, 768), (768, 1024), (390, 844), (320, 740)]
        for lang, path in [("en", "/"), ("ru", "/ru/"), ("uz", "/uz/")]:
            for width, height in viewports:
                cdp("Emulation.setDeviceMetricsOverride", {"width": width, "height": height,
                                                          "deviceScaleFactor": 1, "mobile": width < 800})
                cdp("Emulation.setTouchEmulationEnabled", {"enabled": width < 800})
                navigate(path)
                evaluate('localStorage.setItem("mushukistan-site-theme","light");document.documentElement.dataset.theme="light"')
                time.sleep(.3)
                metric = evaluate('(() => {const b=document.querySelector(".hero-actions .button-primary").getBoundingClientRect();return {lang:document.documentElement.lang,width:innerWidth,scroll:document.documentElement.scrollWidth,hero_font:parseFloat(getComputedStyle(document.querySelector("h1")).fontSize),cta_bottom:b.bottom,cta_top:b.top,cta_href:document.querySelector(".hero-actions .button-primary").getAttribute("href")}})()')
                assert metric["lang"] == lang and metric["scroll"] <= width + 1, metric
                assert metric["cta_href"] == "/feed"
                if not args.capture_only and width >= 1000:
                    assert 0 <= metric["cta_top"] < metric["cta_bottom"] <= height - 8, metric
                if width in (1366, 390):
                    screenshot(f"{lang}-{width}-hero-light")
                if not args.capture_only:
                    metric["light_contrast"] = contrast()
                    gallery = 'document.querySelector(".showcase-gallery")'
                    evaluate(gallery + '.scrollIntoView({block:"start",behavior:"instant"})')
                    wait('Array.from(document.querySelectorAll(".phone-preview img")).every(i=>i.complete&&i.naturalWidth>0)')
                    geometry = evaluate('Array.from(document.querySelectorAll(".phone-preview img")).map(i=>({width:i.clientWidth,height:i.clientHeight,fit:getComputedStyle(i).objectFit}))')
                    assert len(geometry) == 4 and all(abs(i["width"] / i["height"] - 540 / 1106) < .003 and i["fit"] == "contain" for i in geometry), geometry
                    if width < 800:
                        evaluate(gallery + '.focus();' + gallery + '.scrollLeft=0')
                        time.sleep(.4)
                        for kind in ["keyDown", "keyUp"]:
                            cdp("Input.dispatchKeyEvent", {"type": kind, "key": "ArrowRight", "code": "ArrowRight", "windowsVirtualKeyCode": 39})
                        wait(gallery + '.scrollLeft>30')
                        assert evaluate('getComputedStyle(' + gallery + ').outlineWidth') == "3px"
                        time.sleep(.5)
                        keyboard = evaluate(gallery + '.scrollLeft')
                        evaluate(gallery + '.scrollLeft=0')
                        time.sleep(.6)
                        point = evaluate('(() => {const r=' + gallery + '.getBoundingClientRect();return {x:Math.min(innerWidth-50,r.right-30),y:Math.min(innerHeight-100,Math.max(130,r.top+150))}})()')
                        cdp("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [point]})
                        for step in range(1, 11):
                            cdp("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": point["x"] - 20 * step, "y": point["y"]}]})
                            time.sleep(.07)
                        cdp("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
                        wait(gallery + '.scrollLeft>30')
                        time.sleep(.6)
                        snapped = evaluate('(() => {const g=' + gallery + ';const second=g.children[1];return {position:g.scrollLeft,target:second.offsetLeft-g.children[0].offsetLeft}})()')
                        assert abs(snapped["position"] - snapped["target"]) <= 2, snapped
                        metric.update(keyboard_scroll=keyboard, touch_snap=snapped)
                        evaluate(gallery + '.scrollLeft=0')
                        time.sleep(.4)
                    if width in (1366, 390):
                        screenshot(f"{lang}-{width}-showcase-light", "#showcase")
                        screenshot(f"{lang}-{width}-mission-light", "#mission")
                    cdp("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-reduced-motion", "value": "reduce"}]})
                    assert evaluate('getComputedStyle(' + gallery + ').scrollBehavior') == "auto"
                    cdp("Emulation.setEmulatedMedia", {"features": []})
                    metric["layout_shift"] = evaluate("window.__landingCLS")
                    assert metric["layout_shift"] < .03, metric
                evaluate('window.scrollTo({top:0,behavior:"instant"});document.querySelector(".theme-toggle").click()')
                time.sleep(.4)
                assert evaluate('document.documentElement.dataset.theme') == "dark"
                assert evaluate('document.documentElement.scrollWidth <= innerWidth+1')
                if not args.capture_only:
                    metric["dark_contrast"] = contrast()
                if width in (1366, 390):
                    screenshot(f"{lang}-{width}-hero-dark")
                    if not args.capture_only:
                        evaluate('document.querySelector(".showcase-gallery").scrollIntoView({block:"start",behavior:"instant"})')
                        screenshot(f"{lang}-{width}-showcase-dark", "#showcase")
                report["checks"].append({"language": lang, "viewport": [width, height], "themes": ["light", "dark"], **metric})
            print(f"Checked {lang}: hero, themes and {'baseline captures' if args.capture_only else 'native gallery'}.", flush=True)
        if not args.capture_only:
            cdp("Emulation.setScriptExecutionDisabled", {"value": True})
            for lang, path in [("en", "/"), ("ru", "/ru/"), ("uz", "/uz/")]:
                navigate(path)
                assert evaluate('document.body.innerText.length>1500 && document.querySelectorAll(".phone-preview img").length===4')
                assert evaluate('document.documentElement.scrollWidth <= innerWidth+1')
                report["checks"].append({"language": lang, "javascript_disabled": True})
        assert not report["runtime_errors"], report["runtime_errors"]
        report["passed"] = True
        print(f"Passed {len(report['checks'])} browser cases; no runtime exceptions.")
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        if ws:
            ws.close()
        chrome.terminate()
        chrome.wait(timeout=15)
        if server:
            server.shutdown()
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
