#!/usr/bin/env bash
# Alpha deploy script for JawSlayer SongOfTheDay
# Modes:
#   - PM2 (default): keeps the process alive and restarts on boot
#   - systemd (--systemd): installs a unit at /etc/systemd/system/jawslayer-songofday.service
# Refs:
#   PM2 quick start + startup: https://pm2.keymetrics.io/docs/usage/quick-start/  https://pm2.keymetrics.io/docs/usage/startup/
#   systemd unit basics: https://www.freedesktop.org/software/systemd/man/systemd.service.html

set -euo pipefail

APP_NAME="songofday"
SERVICE_NAME="jawslayer-songofday"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"

MODE="pm2"
if [[ "${1:-}" == "--systemd" ]]; then
  MODE="systemd"
fi

echo "==> Deploying JawSlayer SongOfTheDay with mode: ${MODE}"
echo "    Working dir: ${WORKDIR}"

# 0) sanity checks
if [[ ! -f "${WORKDIR}/server/index.js" ]]; then
  echo "ERROR: Run this from the repo root (server/index.js not found)." >&2
  exit 1
fi
if [[ ! -f "${WORKDIR}/.env" ]]; then
  echo "ERROR: .env missing. Copy .env.example to .env and fill values." >&2
  exit 1
fi

# 1) Node & deps
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js not installed. Install Node 20+ and re-run." >&2
  exit 1
fi
NODE_VER="$(node -v | sed 's/^v//')"
echo "Node version: v${NODE_VER}"
echo "==> Installing prod dependencies"
npm ci --omit=dev

# 2) Register slash commands (guild-scoped)
echo "==> Registering Discord commands"
node client/register-commands.js || {
  echo "WARNING: command registration failed (check .env values). Continuing…"
}

if [[ "${MODE}" == "pm2" ]]; then
  # PM2 path
  if ! command -v pm2 >/dev/null 2>&1; then
    echo "==> Installing PM2 globally"
    npm i -g pm2
  fi

  echo "==> Starting app with PM2"
  # Start or restart by name
  if pm2 list | grep -q "${APP_NAME}"; then
    pm2 restart "${APP_NAME}" --update-env --time --interpreter node -- server/index.js
  else
    pm2 start server/index.js --name "${APP_NAME}" --time
  fi

  echo "==> Saving PM2 process list and enabling startup on boot"
  pm2 save
  # Generate OS-specific startup and enable (follow instructions if any)
  pm2 startup -u "$USER" --hp "$HOME"

  echo "✅ Deployed with PM2. Logs: pm2 logs ${APP_NAME}"
  exit 0
fi

# 3) systemd path
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: systemd install requires sudo/root. Re-run: sudo $0 --systemd" >&2
  exit 1
fi

# Create service file
cat >/etc/systemd/system/${SERVICE_NAME}.service <<UNIT
[Unit]
Description=JawSlayer SongOfTheDay Discord bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${WORKDIR}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server/index.js
Restart=on-failure
RestartSec=5
# Hardening (optional):
# NoNewPrivileges=true
# PrivateTmp=true
# ProtectSystem=strict
# ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Reloading systemd and starting service"
systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}
sleep 1
systemctl --no-pager --full status ${SERVICE_NAME} || true

echo "✅ Deployed with systemd. Tail logs with: journalctl -u ${SERVICE_NAME} -f"
