# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DNS filtering solution for a home network using AdGuard Home on a Hetzner VPS. Blocks ads, trackers, and malware at the DNS level for all devices on the network. Optional DNS-over-HTTPS (DoH) via Caddy reverse proxy for mobile devices.

Language: Ukrainian (documentation and comments are in Ukrainian).

## Architecture

```
Router ──DNS:53──▶ Hetzner VPS (AdGuard Home) ──DoH──▶ Cloudflare 1.1.1.1
                    ├── blocks ads, trackers, malware
                    └── web panel on :8080

Mobile devices (optional):
  ──DoH:443──▶ Hetzner VPS (Caddy → AdGuard Home)
```

Two Docker services:
- **adguard** — Custom AdGuard Home image with auto-config entrypoint. Always runs.
- **caddy** — Caddy with DuckDNS plugin for TLS. Only runs with `--profile doh`.

## Key Commands

```bash
# Deploy without DoH
docker compose up -d --build

# Deploy with DoH (requires DUCKDNS_TOKEN and DUCKDNS_DOMAIN in .env)
docker compose --profile doh up -d --build

# View logs
docker logs -f adguard
docker logs -f caddy

# Reset AdGuard config (regenerates from template + .env)
docker compose down
docker volume rm dns_filter_agh_conf
docker compose up -d --build

# Update images
docker compose pull
docker compose up -d --build
```

## How the Entrypoint Works

`adguardhome/entrypoint.sh` has two modes on first run (when no config exists):
1. **Auto mode** — If `AGH_USER` + `AGH_PASSWORD` are set in `.env`, generates `AdGuardHome.yaml` from the template using `htpasswd` for bcrypt hashing and `awk` for placeholder substitution (not `sed`, because bcrypt hashes contain `$`).
2. **Wizard mode** — If env vars are not set, AdGuard Home starts its setup wizard on `:3000`.

On subsequent runs, the existing config in the `agh_conf` volume is used as-is.

## Config Template

`adguardhome/AdGuardHome.yaml.template` contains placeholders `__AGH_USER__` and `__AGH_PASSWORD_HASH__` that get replaced by the entrypoint. Pre-configured with:
- Cloudflare DoH upstreams (parallel mode)
- 4MB DNS cache with optimistic caching
- Four blocklists (AdGuard DNS filter, OISD Big, Steven Black, 1Hosts Lite)
- `allow_unencrypted_doh: true` (required for Caddy reverse proxy to forward DoH)

## Caddy (DoH Profile)

`caddy/Dockerfile` is a multi-stage build that compiles Caddy with the DuckDNS DNS challenge plugin via `xcaddy`. The `Caddyfile` reverse-proxies both `/dns-query` and the web UI to the adguard container.

## Environment Variables

See `.env.example`. Core vars:
- `AGH_USER` / `AGH_PASSWORD` — AdGuard Home admin credentials (triggers auto-config)
- `DUCKDNS_TOKEN` / `DUCKDNS_DOMAIN` — Only needed for the `doh` profile
