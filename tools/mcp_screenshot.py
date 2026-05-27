#!/usr/bin/env python3
"""mcp_screenshot.py — take a VICE-MCP screenshot from the command line.

Usage:
  python3 tools/mcp_screenshot.py [path]
    If path omitted, saves to /tmp/outline_snap_<timestamp>.png
"""

import json
import sys
import time
import urllib.request

MCP_URL = "http://127.0.0.1:6510/mcp"

def mcp_call(method, params=None):
    payload = {
        "jsonrpc": "2.0", "id": 1,
        "method": "tools/call",
        "params": {"name": method, "arguments": params or {}},
    }
    try:
        req = urllib.request.Request(
            MCP_URL, data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        if "error" in data:
            print(f"MCP error: {data['error']}", file=sys.stderr)
            return None
        return data.get("result", {}).get("content", [{}])[0].get("text", "")
    except Exception as e:
        print(f"MCP error: {e}", file=sys.stderr)
        return None

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else f"/tmp/outline_snap_{int(time.time())}.png"
    result = mcp_call("vice.display.screenshot", {"path": path, "format": "png"})
    if result:
        print(f"Screenshot saved to {path}")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
