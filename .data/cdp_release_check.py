import argparse
import base64
import json
import time
import urllib.request
from urllib.parse import urlsplit

import websocket


parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=9224)
parser.add_argument("--url", default="https://mushukistan.uz/register")
parser.add_argument("--screenshot", required=True)
parser.add_argument("--wait", type=int, default=20)
parser.add_argument("--no-navigate", action="store_true")
parser.add_argument("--target-type", default="page")
parser.add_argument("--click-x", type=float)
parser.add_argument("--click-y", type=float)
args = parser.parse_args()

with urllib.request.urlopen(f"http://127.0.0.1:{args.port}/json/list") as response:
    targets = json.load(response)
target = next(item for item in targets if item["type"] == args.target_type)
socket = websocket.create_connection(
    target["webSocketDebuggerUrl"],
    origin=f"http://127.0.0.1:{args.port}",
    http_proxy_host=None,
    timeout=30,
)

next_id = 0
events = {
    "runtimeExceptions": [],
    "consoleMessages": [],
    "consoleErrors": [],
    "failedRequests": [],
    "httpErrors": [],
    "googleResponses": [],
}


def record(message):
    method = message.get("method")
    params = message.get("params", {})
    if method == "Runtime.exceptionThrown":
        events["runtimeExceptions"].append(
            params.get("exceptionDetails", {}).get("text", "unknown exception")
        )
    elif method == "Runtime.consoleAPICalled":
        values = []
        for item in params.get("args", []):
            values.append(str(item.get("value", item.get("description", ""))))
        events["consoleMessages"].append(
            f"{params.get('type', 'log')}: {' '.join(values)}"
        )
    elif method == "Log.entryAdded":
        entry = params.get("entry", {})
        if entry.get("level") == "error":
            events["consoleErrors"].append(entry.get("text", "unknown log error"))
    elif method == "Network.loadingFailed":
        events["failedRequests"].append(
            f"{params.get('errorText')} [{params.get('type')}]"
        )
    elif method == "Network.responseReceived":
        response = params.get("response", {})
        parts = urlsplit(response.get("url", ""))
        summary = f"{int(response.get('status', 0))} {parts.hostname}{parts.path}"
        if response.get("status", 0) >= 400:
            events["httpErrors"].append(summary)
        host = parts.hostname or ""
        if host.endswith((".google.com", ".googleusercontent.com", ".gstatic.com")):
            events["googleResponses"].append(summary)


def command(method, params=None, timeout=30):
    global next_id
    next_id += 1
    command_id = next_id
    socket.send(json.dumps({"id": command_id, "method": method, "params": params or {}}))
    socket.settimeout(timeout)
    while True:
        message = json.loads(socket.recv())
        record(message)
        if message.get("id") == command_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message.get("result", {})


for domain in ("Page", "Runtime", "Network", "Log", "Accessibility"):
    command(f"{domain}.enable")
command("Network.setCacheDisabled", {"cacheDisabled": True})
command("Network.setBypassServiceWorker", {"bypass": True})
if not args.no_navigate:
    command("Page.navigate", {"url": args.url})

if args.click_x is not None and args.click_y is not None:
    command(
        "Input.dispatchMouseEvent",
        {"type": "mousePressed", "x": args.click_x, "y": args.click_y, "button": "left", "clickCount": 1},
    )
    command(
        "Input.dispatchMouseEvent",
        {"type": "mouseReleased", "x": args.click_x, "y": args.click_y, "button": "left", "clickCount": 1},
    )

deadline = time.monotonic() + args.wait
socket.settimeout(1)
while time.monotonic() < deadline:
    try:
        record(json.loads(socket.recv()))
    except websocket.WebSocketTimeoutException:
        pass

expression = r"""
JSON.stringify({
  title: document.title,
  href: location.href,
  readyState: document.readyState,
  bodyText: document.body.innerText,
  iframeCount: document.querySelectorAll('iframe').length,
  iframes: Array.from(document.querySelectorAll('iframe')).map((node) => ({
    host: (() => { try { return new URL(node.src).host; } catch (_) { return ''; } })(),
    title: node.title,
    name: node.name,
    rect: (() => { const r = node.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })(),
    display: getComputedStyle(node).display,
    visibility: getComputedStyle(node).visibility,
    opacity: getComputedStyle(node).opacity,
    parent: node.parentElement ? node.parentElement.outerHTML.slice(0, 1000) : ''
  })),
  googleElementCount: document.querySelectorAll('[aria-label*="Google"], [title*="Google"], [class*="google" i], [id*="google" i]').length
})
"""
evaluation = command(
    "Runtime.evaluate", {"expression": expression, "returnByValue": True}
)
page = json.loads(evaluation["result"]["value"])
accessibility = command("Accessibility.getFullAXTree")
page["accessibleControls"] = [
    {
        "role": node.get("role", {}).get("value"),
        "name": node.get("name", {}).get("value"),
    }
    for node in accessibility.get("nodes", [])
    if node.get("role", {}).get("value") in {"button", "link", "textbox", "checkbox"}
]
if args.target_type == "page":
    screenshot = command(
        "Page.captureScreenshot", {"format": "png", "captureBeyondViewport": True}
    )
    with open(args.screenshot, "wb") as output:
        output.write(base64.b64decode(screenshot["data"]))

for key in events:
    events[key] = list(dict.fromkeys(events[key]))
page.update(events)
page["screenshot"] = args.screenshot if args.target_type == "page" else None
print(json.dumps(page, indent=2))
socket.close()
