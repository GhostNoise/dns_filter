#!/bin/sh
set -e

CONF="/opt/adguardhome/conf/AdGuardHome.yaml"

if [ ! -f "$CONF" ]; then
  if [ -n "$AGH_USER" ] && [ -n "$AGH_PASSWORD" ]; then
    echo "[entrypoint] Generating config from template..."
    HASH=$(adguardhome --hash-password "$AGH_PASSWORD" 2>/dev/null | tail -1)
    sed "s|__AGH_USER__|${AGH_USER}|g;s|__AGH_PASSWORD_HASH__|${HASH}|g" \
      /opt/adguardhome/conf/AdGuardHome.yaml.template > "$CONF"
    echo "[entrypoint] Config created with user '${AGH_USER}'"
  else
    echo "[entrypoint] No AGH_USER/AGH_PASSWORD set — starting setup wizard on :3000"
  fi
fi

exec /opt/adguardhome/AdGuardHome --no-check-update -c "$CONF" -w /opt/adguardhome/work
