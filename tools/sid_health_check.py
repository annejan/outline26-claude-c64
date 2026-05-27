#!/usr/bin/env python3
"""sid_health_check.py — VICE-MCP SID register polling harness.

Polls $D417 (voice routing + resonance) and $D418 (filter mode + volume)
every ~100 ms via VICE-MCP. Logs warnings when:
  1. LP filter mode is on ($D418 & 0x10) but no voices are routed
     through it ($D417 & 0x07 == 0) — the "silent filter sweep" bug.
  2. Volume stays at 0 beyond the initial boot window (30 s).

Usage:
  python3 tools/sid_health_check.py          # poll until Ctrl+C
  python3 tools/sid_health_check.py --once   # single snapshot

Requires: VICE-MCP running at http://127.0.0.1:6510/mcp
"""

import json
import sys
import time
import urllib.request

MCP_URL = "http://127.0.0.1:6510/mcp"
SID_D417 = 54295  # $D417 — voice routing + resonance
SID_D418 = 54296  # $D418 — filter mode + volume


def mcp_read(address, size):
    """Read memory via VICE-MCP, return list of hex byte strings."""
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "vice.memory.read",
            "arguments": {"address": address, "size": size},
        },
    }
    req = urllib.request.Request(
        MCP_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        resp = urllib.request.urlopen(req, timeout=2)
        body = json.loads(resp.read())
        # The data is a nested JSON string inside content[0].text
        inner = json.loads(body["result"]["content"][0]["text"])
        return inner["data"]  # list of hex strings, e.g. ["00", "0f"]
    except Exception as exc:
        return None


def format_routed(bits):
    """Format voice routing bits 0-2 into a human string."""
    parts = []
    for v in range(3):
        if bits & (1 << v):
            parts.append(f"V{v+1}")
    return " ".join(parts) if parts else "(none)"


def check(once=False):
    last_key = None
    boot_vol_zero_start = None

    print("[SID] Health check running — Ctrl+C to stop")
    print()

    while True:
        data = mcp_read(SID_D417, 2)
        if data is None:
            if last_key != "DOWN":
                print("[SID] ⚠ MCP connection lost (is VICE running?)")
                last_key = "DOWN"
            time.sleep(1)
            continue

        d417 = int(data[0], 16)
        d418 = int(data[1], 16)

        vol = d418 & 0x0F
        lp_mode = (d418 >> 4) & 1
        voices_routed = d417 & 0x07
        resonance = (d417 >> 4) & 0x07

        state_key = f"{d417:02x}{d418:02x}"
        if state_key == last_key:
            time.sleep(0.1)
            continue
        last_key = state_key

        parts = [f"vol={vol}"]
        parts.append("LP=ON" if lp_mode else "LP=off")
        if resonance:
            parts.append(f"res={resonance}")
        parts.append(f"→ {format_routed(voices_routed)}")

        print(f"[SID] {d417:02x} {d418:02x}  —  {'  '.join(parts)}")

        # Warning: LP active but no voices routed
        if lp_mode and voices_routed == 0:
            print(
                "  ⚠  LP filter ON but NO voices routed through it!"
            )
            print(
                "     Set $D417 bits 0-2, e.g. $04 = V2 only"
            )

        # Warning: volume stuck at 0
        if vol == 0:
            if boot_vol_zero_start is None:
                boot_vol_zero_start = time.monotonic()
            elif time.monotonic() - boot_vol_zero_start > 30.0:
                print(
                    "  ⚠  SID volume stuck at 0 for >30 s —"
                    " music may be muted"
                )
        else:
            boot_vol_zero_start = None

        if once:
            return


if __name__ == "__main__":
    once = "--once" in sys.argv
    check(once=once)
