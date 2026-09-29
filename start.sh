#!/usr/bin/env bash
# One command to run the planner:   ./start.sh
#
# First run: creates .venv (Python 3.12+), installs Jac, installs the web
# client's packages. Every run: starts the server + web/mobile app and prints
# the link to open. Keep this terminal open while you use the app.
set -e
cd "$(dirname "$0")"
PORT="${PORT:-8000}"

# 1. Python 3.12+ virtual env with Jac installed
if [ ! -x .venv/bin/jac ]; then
  PY=""
  for c in python3.13 python3.12 python3; do
    if command -v "$c" >/dev/null 2>&1 &&
       "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
      PY="$c"; break
    fi
  done
  if [ -z "$PY" ]; then
    echo "Jac needs Python 3.12 or newer. On a Mac:  brew install python@3.12"
    exit 1
  fi
  echo "Setting up .venv with $("$PY" --version)..."
  "$PY" -m venv .venv
  .venv/bin/pip install --quiet --upgrade pip
  .venv/bin/pip install jaseci
fi
source .venv/bin/activate

# 2. Web client packages (React, Vite, ...) - only the first time
if [ ! -d .jac/client/node_modules ]; then
  if ! command -v bun >/dev/null 2>&1 && ! command -v npm >/dev/null 2>&1 && [ ! -x "$HOME/.bun/bin/bun" ]; then
    echo "The web app needs Bun or Node.js to build. Install one, then re-run ./start.sh:"
    echo "  curl -fsSL https://bun.sh/install | bash      (or: brew install node)"
    exit 1
  fi
  echo "Installing web client packages..."
  jac install
fi

# 3. Make sure nothing else is using the port
if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use (maybe the planner is already running?)."
  echo "Stop that process, or pick another port:  PORT=8080 ./start.sh"
  exit 1
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "  Planner is starting. When you see 'Server ready', open:"
echo "    Web:    http://localhost:$PORT"
[ -n "$LAN_IP" ] && echo "    Phone:  http://$LAN_IP:$PORT   (same Wi-Fi)"
echo "    CLI:    ./plan today   (in another terminal)"
echo
exec jac start main.jac --port "$PORT"
