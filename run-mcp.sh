#!/bin/bash
# Start VICE with MCP server, autostart rasterbars.prg via prg-injection mode.
# MCP API at http://127.0.0.1:6510/mcp
# Notes: requires VICE_DATA dir at ~/.local/share/vice/ with C64/ and GLSL/ symlinks.
set -e
cd "$(dirname "$0")"
pkill -9 -f x64sc 2>/dev/null || true
sleep 1
/home/annejan/Projects/vice-mcp/vice/build-test-with-mcp/src/x64sc \
    -mcpserver -autostartprgmode 1 \
    rasterbars.prg > /tmp/vice.log 2>&1 &
disown
sleep 4
ss -tln | grep -q 6510 && echo "VICE+MCP ready at http://127.0.0.1:6510/mcp"
