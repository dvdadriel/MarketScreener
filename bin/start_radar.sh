#!/bin/bash
# Auto-start CryptoRadar on macOS login.
# Loads rbenv/asdf, ensures Postgres is running, builds CSS once,
# then launches the web + jobs processes (Procfile.radar).
# Note: the dev `css` (tailwindcss:watch) process is intentionally omitted —
# under launchd there is no TTY, so the watcher exits immediately and would
# tear down the whole foreman group. We build CSS once at startup instead.

set -e

APP_DIR="/Users/david/Projects/CryptoScreener"
LOG_DIR="$APP_DIR/log"
mkdir -p "$LOG_DIR"

# Load shell environment (rbenv, asdf, etc.)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -d "$HOME/.rbenv" ]; then
  export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init - bash)"
fi

cd "$APP_DIR"

# Make sure Postgres is up (skip silently if already running)
if command -v brew &> /dev/null; then
  brew services start postgresql@16 2>/dev/null || \
  brew services start postgresql@15 2>/dev/null || \
  brew services start postgresql@14 2>/dev/null || \
  brew services start postgresql 2>/dev/null || true
fi

# Wait for Postgres to be reachable (max 30s)
for i in {1..30}; do
  if pg_isready -h localhost -q 2>/dev/null; then break; fi
  sleep 1
done

# Build CSS once (no live watcher under launchd)
bin/rails tailwindcss:build >> "$LOG_DIR/radar.out.log" 2>> "$LOG_DIR/radar.err.log" || true

# Start app (web + jobs only)
export PORT="${PORT:-4242}"
export RUBY_DEBUG_OPEN="true"
export RUBY_DEBUG_LAZY="true"
exec foreman start -f Procfile.radar >> "$LOG_DIR/radar.out.log" 2>> "$LOG_DIR/radar.err.log"
