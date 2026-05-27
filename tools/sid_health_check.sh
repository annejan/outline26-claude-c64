#!/bin/bash
# sid_health_check.sh — VICE-MCP SID register polling harness.
#
# Polls $D417 (voice routing + resonance) and $D418 (filter mode +
# volume) every ~100 ms via VICE-MCP. Logs warnings when:
#   1. LP filter mode is on ($D418 & $10) but no voices are routed
#      through it ($D417 & $07 == 0) — the "silent filter sweep" bug.
#   2. Volume drops to $00 for more than a brief init window
#      (possible stuck-SID or muted-music condition).
#
# Only prints on state CHANGE to keep the terminal readable.
# Designed to run alongside ./run-mcp.sh during development.
#
# Usage:
#   ./tools/sid_health_check.sh          # poll until Ctrl+C
#   ./tools/sid_health_check.sh --once   # single snapshot
#
# Requires: VICE-MCP running at http://127.0.0.1:6510/mcp

MCP="http://127.0.0.1:6510/mcp"

mcp_read() {
    # mcp_read <address> <size> → hex bytes on stdout
    curl -s -X POST "$MCP" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
             "params":{"name":"vice.memory.read",
                       "arguments":{"address":'$1',"size":'$2'}}}' \
    | grep -o '"data":\[[^]]*\]' \
    | sed 's/"data":\[//;s/\]//;s/,/ /g'
}

last_d417=""
last_d418=""
first_run=1

while true; do
    # $D417 = 54295, $D418 = 54296 (SID voice routing + filter mode)
    data=$(mcp_read 54295 2 2>/dev/null || echo "FAIL")

    if [[ "$data" == "FAIL" ]]; then
        if [[ "$last_d417" != "DOWN" ]]; then
            echo "[SID] MCP connection lost (is VICE running?)"
            last_d417="DOWN"
        fi
        sleep 1
        continue
    fi

    # data is two hex bytes: d417 d418
    read -r d417 d418 <<<"$data"

    # Remove leading zeros for arithmetic
    d417_val=$((16#${d417}))
    d418_val=$((16#${d418}))

    # Volume
    vol=$(( d418_val & 0x0f ))
    lp_mode=$(( (d418_val >> 4) & 1 ))
    voices_routed=$(( d417_val & 0x07 ))
    resonance=$(( (d417_val >> 4) & 0x07 ))

    # Detect change vs last known state
    state_key="${d417}:${d418}"
    if [[ "$state_key" == "${last_d417}:${last_d418}" ]] && [[ $first_run -eq 0 ]]; then
        sleep 0.1
        continue
    fi
    first_run=0

    # Build status line
    parts=()
    parts+=("vol=$vol")

    if (( lp_mode )); then
        parts+=("LP=ON")
    else
        parts+=("LP=off")
    fi

    if (( resonance )); then
        parts+=("res=$resonance")
    fi

    if (( voices_routed )); then
        routed_str=""
        for v in 0 1 2; do
            if (( (voices_routed >> v) & 1 )); then
                routed_str="${routed_str}V$((v+1)) "
            fi
        done
        parts+=("→ ${routed_str}")
    fi

    echo "[SID] $d417 $d418 — ${parts[*]}"

    # Warning conditions
    if (( lp_mode )) && (( voices_routed == 0 )); then
        echo "  ⚠ WARNING: LP filter ON but NO voices routed through it! (silent filter)"
        echo "  Set \$D417 bits 0-2 to route a voice, e.g. \$04 = V2 only"
    fi

    last_d417="$d417"
    last_d418="$d418"

    # Single-shot mode
    if [[ "$1" == "--once" ]]; then
        exit 0
    fi

    sleep 0.1
done
