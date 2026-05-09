#!/bin/bash
set -e

# Start virtual framebuffer (Wine needs a display)
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
XVFB_PID=$!
export DISPLAY=:99
trap "kill $XVFB_PID 2>/dev/null || true" EXIT
sleep 1

exec "$@"
