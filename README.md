# DNS Filter

DNS-based ad blocker for the whole home network. Runs [AdGuard Home](https://adguard.com/adguard-home/overview.html) on a VPS with optional DNS-over-HTTPS via [Caddy](https://caddyserver.com/).

## How it works

```
Home Router ──DNS:53──▶ VPS (AdGuard Home) ──DoH──▶ Cloudflare 1.1.1.1
                        ├─ blocks ads, trackers, malware
                        └─ logs & whitelist via Web UI

Mobile/Laptop (optional):
  ──DoH:443──▶ VPS (Caddy → AdGuard Home)
```

All incoming traffic is restricted to your home IP via Hetzner Cloud Firewall.

## Quick start

### Prerequisites

- Hetzner VPS with Docker and Docker Compose
- Home IP whitelisted in Hetzner Firewall (ports 22, 53, 3000, 8080)

### Deploy

```bash
ssh root@YOUR_VPS_IP

# Free port 53 from systemd-resolved
systemctl disable --now systemd-resolved
rm /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# Clone and start
cd /opt/dns_filter
docker compose up -d
```

Open `http://YOUR_VPS_IP:3000` → complete the setup wizard → set admin credentials.

### Configure your router

Set your VPS IP as the **only** DNS server on the router. Do not add a public DNS as secondary — it will bypass the filter.

### Verify

```bash
nslookup ads.google.com YOUR_VPS_IP   # should return 0.0.0.0
nslookup google.com YOUR_VPS_IP       # should return a real IP
```

## DoH for mobile devices (optional)

Requires a domain for a valid TLS certificate. [DuckDNS](https://www.duckdns.org) provides free subdomains.

```bash
cp .env.example .env
# Edit .env with your DuckDNS token and domain

# Add port 443 to Hetzner Firewall, then:
docker compose --profile doh up -d --build
```

Configure devices to use `https://yourname.duckdns.org/dns-query` as DNS-over-HTTPS.

## Recommended blocklists

Add in AdGuard Home → Filters → DNS blocklists:

| List | URL |
|------|-----|
| AdGuard DNS filter | built-in |
| OISD (Big) | `https://big.oisd.nl` |
| Steven Black | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| 1Hosts Lite | `https://o0.pages.dev/Lite/adblock.txt` |

## Updating

```bash
docker compose pull
docker compose up -d          # without DoH
docker compose --profile doh up -d  # with DoH
```

## Project structure

```
├── docker-compose.yml   # AdGuard Home + Caddy (optional)
├── .env.example         # DuckDNS credentials template
├── caddy/
│   ├── Dockerfile       # Caddy with DuckDNS plugin
│   └── Caddyfile        # Reverse proxy config
├── adguardhome/
│   └── conf/            # AdGuard Home config (auto-generated)
├── SETUP.md             # Detailed setup guide (UA)
└── README.md
```

## Full setup guide

See [SETUP.md](SETUP.md) for detailed step-by-step instructions including Hetzner Firewall rules, router configuration, DoT for Android Private DNS, and troubleshooting.
