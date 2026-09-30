#!/usr/bin/env bash
# Setup + run in one step:   ./start.sh
#
# Creates .venv (Python 3.12+) and installs Jac the first time, then runs
# `jac run` (server + web/mobile app). If Jac is already installed you can
# just run `jac run` yourself. Keep this terminal open while you use the app.
set -e
cd "$(dirname "$0")"

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

# 3. Make sure nothing else is using the ports (8000 = app, 8001 = API in dev mode)
for p in 8000 8001; do
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $p is already in use (maybe the planner is already running?). Stop that process and try again."
    exit 1
  fi
done

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "  Planner is starting (jac run). When the URLs appear, open:"
echo "    Web:    http://localhost:8000"
[ -n "$LAN_IP" ] && echo "    Phone:  http://$LAN_IP:8000   (same Wi-Fi)"
echo "    CLI:    ./plan today   (in another terminal)"
echo
exec jac run
