# DNS Filter — AdGuard Home on Hetzner VPS

## Архітектура

```
Mi Router ──plain DNS:53──▶ VPS (AdGuard Home) ──DoH──▶ 1.1.1.1
                            🔒 Hetzner FW: тільки домашня IP

Телефони/ноути (опціонально):
  ──DoH:443──▶ VPS (Caddy → AdGuard Home)
```

---

## Фаза 1: Базове налаштування (plain DNS)

### 1.1 Hetzner Firewall

В Hetzner Cloud Console → Firewalls → Create Firewall:

| Direction | Protocol | Port  | Source IP         | Опис           |
|-----------|----------|-------|-------------------|----------------|
| Inbound   | TCP      | 22    | твоя домашня IP/32| SSH            |
| Inbound   | TCP+UDP  | 53    | твоя домашня IP/32| DNS            |
| Inbound   | TCP      | 3000  | твоя домашня IP/32| AGH setup UI   |
| Inbound   | TCP      | 8080  | твоя домашня IP/32| AGH web UI     |

> Hetzner firewall працює ДО сервера — трафік навіть не дійде до VPS.
> Домашню IP дізнатись: `curl ifconfig.me`

Прикріпи firewall до свого сервера.

### 1.2 Розгортання на VPS

```bash
# Клонуй або скопіюй файли на VPS
scp -r dns_filter/ root@YOUR_VPS_IP:/opt/dns_filter

# На VPS
ssh root@YOUR_VPS_IP
cd /opt/dns_filter

# Звільни порт 53 якщо зайнятий systemd-resolved
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

# Запуск
docker compose up -d
```

### 1.3 Початкове налаштування AdGuard Home

1. Відкрий `http://YOUR_VPS_IP:3000`
2. Пройди wizard:
   - Web interface: `0.0.0.0:80`
   - DNS server: `0.0.0.0:53`
   - Створи логін/пароль
3. Після wizard UI доступний на `http://YOUR_VPS_IP:8080`

### 1.4 Налаштування AdGuard Home

Settings → DNS settings:
- **Upstream DNS**: `https://1.1.1.1/dns-query`
- **Bootstrap DNS**: `1.1.1.1`
- Увімкни **Parallel requests** для швидкості

Filters → DNS blocklists → Add blocklist:
- ✅ AdGuard DNS filter (вже є)
- ✅ AdAway Default Blocklist
- ✅ OISD (Big) — `https://big.oisd.nl`
- ✅ Steven Black's hosts — `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
- ✅ 1Hosts (Lite) — `https://o0.pages.dev/Lite/adblock.txt`

### 1.5 Налаштування роутера Mi Router AC1200

1. Зайди в `192.168.31.1` (або `miwifi.com`)
2. Settings → Network settings → DNS
3. Встанови **Primary DNS**: `YOUR_VPS_IP`
4. **Secondary DNS**: залиш порожнім (або `YOUR_VPS_IP` ще раз)
   > НЕ ставити публічний DNS як secondary — інакше частина запитів піде повз фільтр
5. Збережи, перезавантаж роутер

### 1.6 Перевірка

```bash
# З домашнього ПК
nslookup ads.google.com YOUR_VPS_IP
# Має повернути 0.0.0.0 — реклама заблокована

nslookup google.com YOUR_VPS_IP
# Має повернути реальну IP — сайт працює
```

---

## Фаза 2: DoH для мобільних пристроїв (опціонально)

Потрібен домен для валідного TLS-сертифіката.

### 2.1 DuckDNS (безкоштовний домен)

1. Зайди на https://www.duckdns.org — увійди через GitHub/Google
2. Створи субдомен (напр. `myfilter`) → `myfilter.duckdns.org`
3. Встав IP свого VPS
4. Скопіюй **token** зі сторінки

### 2.2 Налаштування .env

```bash
cd /opt/dns_filter
cp .env.example .env
nano .env
```

```
DUCKDNS_TOKEN=abc123-your-actual-token
DUCKDNS_DOMAIN=myfilter.duckdns.org
```

### 2.3 Додаткові правила Hetzner Firewall

| Direction | Protocol | Port | Source IP         | Опис              |
|-----------|----------|------|-------------------|--------------------|
| Inbound   | TCP+UDP  | 443  | твоя домашня IP/32| DoH + Web UI HTTPS |

> Якщо хочеш DoH для мобільних пристроїв поза домом —
> додай 0.0.0.0/0 для порту 443 (Caddy + AdGuard мають авторизацію).

### 2.4 Запуск з DoH

```bash
docker compose --profile doh up -d --build
```

Перший запуск збілдить Caddy з DuckDNS-плагіном (~2 хв).

### 2.5 Налаштування пристроїв

**Android (9+):**
Settings → Network → Private DNS → `myfilter.duckdns.org`

> ⚠️ Android Private DNS використовує DoT (порт 853), а не DoH.
> Для DoT потрібно додатково налаштувати сертифікат в AdGuard Home.
> Простіше: встановити додаток (Intra, AdGuard) і вказати DoH URL.

**iOS (14+):**
Встанови профіль для DoH — створи через https://dns.notjakob.com/tool.html:
- DNS over HTTPS
- Server URL: `https://myfilter.duckdns.org/dns-query`

**Браузер (Chrome/Firefox/Edge):**
Settings → Security → DNS → Custom → `https://myfilter.duckdns.org/dns-query`

---

## Фаза 3: DoT для Android Private DNS (опціонально)

Android Private DNS потребує DoT (порт 853). AdGuard Home підтримує DoT,
але потрібен TLS-сертифікат.

### 3.1 Отримання сертифіката з Caddy

Caddy зберігає сертифікати автоматично. Скопіюй їх в AdGuard Home:

```bash
# Знайди сертифікати Caddy
docker exec caddy ls /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/

# Створи скрипт для копіювання
cat > /opt/dns_filter/sync-certs.sh << 'SCRIPT'
#!/bin/bash
DOMAIN="${DUCKDNS_DOMAIN}"
CERT_DIR="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}"

docker cp caddy:${CERT_DIR}/${DOMAIN}.crt ./adguardhome/conf/cert.pem
docker cp caddy:${CERT_DIR}/${DOMAIN}.key ./adguardhome/conf/key.pem
docker restart adguard
SCRIPT
chmod +x /opt/dns_filter/sync-certs.sh
```

### 3.2 Налаштування AdGuard Home

Settings → Encryption settings:
- ✅ Enable encryption
- Server name: `myfilter.duckdns.org`
- Certificate path: `/opt/adguardhome/conf/cert.pem`
- Private key path: `/opt/adguardhome/conf/key.pem`
- HTTPS port: `0` (Caddy обробляє HTTPS)
- DNS-over-TLS port: `853`

### 3.3 Hetzner Firewall для DoT

| Direction | Protocol | Port | Source IP | Опис |
|-----------|----------|------|-----------|------|
| Inbound   | TCP      | 853  | 0.0.0.0/0 | DoT  |

### 3.4 Android

Settings → Network → Private DNS → `myfilter.duckdns.org`

---

## Оновлення

```bash
cd /opt/dns_filter
docker compose pull
docker compose --profile doh up -d   # або без --profile якщо без DoH
```

## Моніторинг

```bash
# Логи AdGuard Home
docker logs -f adguard

# Логи Caddy
docker logs -f caddy

# Статус
docker compose ps
```

## Якщо домашня IP змінилась

1. Дізнайся нову IP: `curl ifconfig.me`
2. Онови правила Hetzner Firewall
3. Якщо DuckDNS — він оновлюється автоматично через cron або вручну на сайті
