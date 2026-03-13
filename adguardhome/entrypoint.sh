#!/bin/sh
set -e

CONF="/opt/adguardhome/conf/AdGuardHome.yaml"
TEMPLATE="/opt/adguardhome/conf/AdGuardHome.yaml.template"

if [ ! -f "$CONF" ]; then
  if [ -n "$AGH_USER" ] && [ -n "$AGH_PASSWORD" ]; then
    echo "[entrypoint] Generating config from template..."
    HASH=$(htpasswd -nbBC 10 "" "$AGH_PASSWORD" | cut -d: -f2)

    # awk handles $ in bcrypt hash safely (sed does not)
    awk -v user="$AGH_USER" -v hash="$HASH" '{
      gsub(/__AGH_USER__/, user)
      gsub(/__AGH_PASSWORD_HASH__/, hash)
      print
    }' "$TEMPLATE" > "$CONF"

    if [ ! -s "$CONF" ]; then
      echo "[entrypoint] ERROR: failed to generate config" >&2
      exit 1
    fi

    echo "[entrypoint] Config created with user '${AGH_USER}'"
  else
    echo "[entrypoint] No AGH_USER/AGH_PASSWORD set — starting setup wizard on :3000"
  fi
fi

exec /opt/adguardhome/AdGuardHome --no-check-update -c "$CONF" -w /opt/adguardhome/work
