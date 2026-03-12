# DNS Filter

Блокування реклами, трекерів та шкідливих доменів для всієї домашньої мережі через DNS-фільтрацію. Працює на [AdGuard Home](https://adguard.com/adguard-home/overview.html) на Hetzner VPS з опціональним DNS-over-HTTPS через [Caddy](https://caddyserver.com/).

## Архітектура

```
Роутер ──DNS:53──▶ Hetzner VPS (AdGuard Home) ──DoH──▶ Cloudflare 1.1.1.1
                    ├── блокує рекламу, трекери, malware
                    └── веб-панель: логи, whitelist, статистика
                    🔒 Hetzner Firewall: тільки домашня IP

Телефони/ноутбуки (опціонально):
  ──DoH:443──▶ Hetzner VPS (Caddy → AdGuard Home)
```

## Структура проєкту

```
├── docker-compose.yml                 # AdGuard Home + Caddy (опціональний DoH профіль)
├── .env.example                       # Шаблон змінних оточення
├── adguardhome/
│   ├── Dockerfile                     # Кастомний image з entrypoint
│   ├── entrypoint.sh                  # Автогенерація конфігу або запуск wizard
│   └── AdGuardHome.yaml.template      # Шаблон конфігу (upstream, блоклісти, кеш)
└── caddy/
    ├── Dockerfile                     # Caddy з DuckDNS плагіном
    └── Caddyfile                      # Reverse proxy для DoH
```

## Два режими першого запуску

| Режим | Умова | Що відбувається |
|-------|-------|-----------------|
| **Автоматичний** | `AGH_USER` + `AGH_PASSWORD` задані в `.env` | Конфіг генерується з шаблону, UI одразу на `:8080` |
| **Wizard** | Змінні не задані | Стандартний wizard AdGuard Home на `:3000` |

При повторних запусках конфіг вже існує — обидва режими просто стартують AdGuard Home.

---

## Фаза 1: Базове налаштування (plain DNS)

### Крок 1 — Дізнайся домашню IP

```bash
curl ifconfig.me
```

Збережи — потрібна для правил фаєрволу.

### Крок 2 — Налаштуй Hetzner Firewall

[Hetzner Cloud Console](https://console.hetzner.cloud) → **Firewalls** → **Create Firewall**.

Додай **Inbound** правила:

| Protocol | Port | Source           | Опис           |
|----------|------|------------------|----------------|
| TCP      | 22   | `ДОМАШНЯ_IP/32` | SSH            |
| TCP+UDP  | 53   | `ДОМАШНЯ_IP/32` | DNS            |
| TCP      | 3000 | `ДОМАШНЯ_IP/32` | AGH wizard     |
| TCP      | 8080 | `ДОМАШНЯ_IP/32` | AGH веб-панель |

Перейди у вкладку **Servers** → **прикріпи фаєрвол до VPS**.

> Hetzner Firewall працює до сервера — заблокований трафік навіть не дійде до VPS.

### Крок 3 — Скопіюй файли на VPS

```bash
scp -r dns_filter/ root@YOUR_VPS_IP:/opt/dns_filter
```

### Крок 4 — Звільни порт 53 на VPS

Порт 53 зазвичай зайнятий `systemd-resolved`:

```bash
ssh root@YOUR_VPS_IP

sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

Перевір:

```bash
sudo ss -tulnp | grep ':53'
# Має бути порожньо
```

### Крок 5 — Запуск

#### Варіант A — автоматичний (без wizard)

```bash
cd /opt/dns_filter
cp .env.example .env
nano .env   # встанови AGH_USER та AGH_PASSWORD
docker compose up -d --build
```

Entrypoint автоматично:
1. Генерує bcrypt хеш пароля через `htpasswd`
2. Створює `AdGuardHome.yaml` з шаблону (upstream Cloudflare DoH, блоклісти, кеш)
3. Запускає AdGuard Home

Веб-панель одразу на `http://YOUR_VPS_IP:8080`.

#### Варіант B — через wizard

```bash
cd /opt/dns_filter
docker compose up -d --build
```

Без `AGH_USER`/`AGH_PASSWORD` в `.env` стартує wizard:

1. Відкрий `http://YOUR_VPS_IP:3000`
2. **Крок 2/5** — Мережеві інтерфейси:
   - Веб-інтерфейс: **Усі інтерфейси**, порт **80**
   - DNS-сервер: **Усі інтерфейси**, порт **53**
3. **Крок 3/5** — Створи **логін** та **пароль** адміна
4. Решта кроків — просто **Далі**

> Після wizard UI на порті 3000 зупиняється. Веб-панель тепер на `http://YOUR_VPS_IP:8080`.

### Крок 6 — Перевір що контейнер працює

```bash
docker compose ps
# Колонка PORTS має показувати: 0.0.0.0:53->53, 0.0.0.0:8080->80
```

Якщо PORTS порожня — контейнер не зміг зайняти порти:

```bash
docker compose down
docker compose up -d
```

### Крок 7 — Налаштування DNS (тільки для варіанту B)

> Варіант A — вже налаштовано в шаблоні, пропускай цей крок.

**Settings → DNS settings:**

| Параметр | Значення |
|----------|----------|
| Upstream DNS servers | `https://1.1.1.1/dns-query` |
| Bootstrap DNS servers | `1.1.1.1` |
| Parallel requests | Увімкнено |

**Test upstreams** → **Apply**.

### Крок 8 — Додай блоклісти (тільки для варіанту B)

> Варіант A — блоклісти вже в шаблоні, пропускай цей крок.

**Filters → DNS blocklists → Add blocklist → Add a custom list:**

| Назва | URL |
|-------|-----|
| OISD Big | `https://big.oisd.nl` |
| Steven Black | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| 1Hosts Lite | `https://o0.pages.dev/Lite/adblock.txt` |

### Крок 9 — Налаштуй роутер

1. Відкрий панель роутера (`192.168.31.1` або `miwifi.com`)
2. **Settings → Network settings → DNS**
3. **Primary DNS**: `YOUR_VPS_IP`
4. **Secondary DNS**: залиш порожнім або `YOUR_VPS_IP` ще раз
5. Збережи → **перезавантаж роутер**

> **НЕ ставити публічний DNS як secondary** — роутер відправлятиме частину запитів напряму, минаючи фільтр.

### Крок 10 — Перевірка

```bash
# Має повернути 0.0.0.0 (заблоковано)
nslookup ads.google.com YOUR_VPS_IP

# Має повернути реальну IP (працює)
nslookup google.com YOUR_VPS_IP
```

В дашборді на `http://YOUR_VPS_IP:8080` мають з'явитись логи запитів.

---

## Фаза 2: DoH для мобільних пристроїв (опціонально)

DoH (DNS-over-HTTPS) шифрує DNS-запити. Потрібен домен для TLS-сертифіката.

### Крок 1 — Безкоштовний домен (DuckDNS)

1. [duckdns.org](https://www.duckdns.org) → увійди через GitHub або Google
2. Створи субдомен (напр. `myfilter`) → `myfilter.duckdns.org`
3. Встав IP свого VPS
4. Скопіюй **token**

### Крок 2 — Налаштуй .env

```bash
nano /opt/dns_filter/.env
```

Додай:

```
DUCKDNS_TOKEN=abc123-your-actual-token
DUCKDNS_DOMAIN=myfilter.duckdns.org
```

### Крок 3 — Онови Hetzner Firewall

| Protocol | Port | Source           | Опис        |
|----------|------|------------------|-------------|
| TCP+UDP  | 443  | `ДОМАШНЯ_IP/32` | DoH + HTTPS |

> Для DoH поза домом — зміни source на `0.0.0.0/0` (Caddy + AGH мають авторизацію).

### Крок 4 — Запусти з DoH

```bash
docker compose --profile doh up -d --build
```

Перший білд ~2 хвилини (Caddy з DuckDNS плагіном).

```bash
docker compose --profile doh ps
# Мають бути контейнери: "adguard" та "caddy"
```

### Крок 5 — Налаштуй пристрої

**Браузер (Chrome / Firefox / Edge):**

Налаштування → Безпека → DNS → Вказати провайдера:
```
https://myfilter.duckdns.org/dns-query
```

**iOS (14+):**

Створи DoH профіль через [dns.notjakob.com/tool.html](https://dns.notjakob.com/tool.html):
- Тип: DNS over HTTPS
- URL: `https://myfilter.duckdns.org/dns-query`

**Android:**

Private DNS використовує DoT (порт 853), не DoH. Варіанти:
- Додаток [Intra](https://play.google.com/store/apps/details?id=app.intra) або [AdGuard](https://adguard.com/adguard-android/overview.html) з DoH URL
- Або DoT — див. Фазу 3

---

## Фаза 3: DoT для Android Private DNS (опціонально)

### Крок 1 — Скопіюй сертифікати з Caddy

```bash
cat > /opt/dns_filter/sync-certs.sh << 'SCRIPT'
#!/bin/bash
set -e
source /opt/dns_filter/.env
CERT_DIR="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DUCKDNS_DOMAIN}"

docker cp "caddy:${CERT_DIR}/${DUCKDNS_DOMAIN}.crt" ./adguardhome/conf/cert.pem
docker cp "caddy:${CERT_DIR}/${DUCKDNS_DOMAIN}.key" ./adguardhome/conf/key.pem
docker restart adguard
echo "Сертифікати синхронізовані."
SCRIPT
chmod +x /opt/dns_filter/sync-certs.sh

./sync-certs.sh
```

> Caddy оновлює сертифікати автоматично. Запускай `./sync-certs.sh` кожні ~60 днів
> або через cron: `0 3 1 */2 * /opt/dns_filter/sync-certs.sh`

### Крок 2 — Увімкни шифрування в AdGuard Home

**Settings → Encryption settings:**

| Параметр | Значення |
|----------|----------|
| Enable encryption | Так |
| Server name | `myfilter.duckdns.org` |
| Certificate path | `/opt/adguardhome/conf/cert.pem` |
| Private key path | `/opt/adguardhome/conf/key.pem` |
| HTTPS port | `0` (Caddy обробляє HTTPS) |
| DNS-over-TLS port | `853` |

### Крок 3 — Hetzner Firewall

| Protocol | Port | Source      | Опис |
|----------|------|-------------|------|
| TCP      | 853  | `0.0.0.0/0` | DoT  |

### Крок 4 — Android

Settings → Network & Internet → Private DNS:

```
myfilter.duckdns.org
```

---

## Обслуговування

### Оновлення

```bash
cd /opt/dns_filter
docker compose pull
docker compose up -d --build                       # без DoH
docker compose --profile doh up -d --build         # з DoH
```

### Логи

```bash
docker logs -f adguard
docker logs -f caddy
docker compose ps
```

### Скидання конфігу (перегенерація з .env)

```bash
docker compose down
docker volume rm dns_filter_agh_conf
docker compose up -d --build
```

### Змінилась домашня IP

1. `curl ifconfig.me`
2. Онови правила в Hetzner Firewall
3. DuckDNS:
   ```bash
   curl "https://www.duckdns.org/update?domains=myfilter&token=YOUR_TOKEN&ip="
   ```

---

## Вирішення проблем

| Проблема | Рішення |
|----------|---------|
| Не відкривається порт 3000 | Фаєрвол не прикріплений до сервера, або IP змінилась |
| Порт 53 зайнятий | `sudo systemctl disable --now systemd-resolved` |
| Контейнер працює, але порти не прокинуті | `docker compose down && docker compose up -d` |
| ERR_CONNECTION_REFUSED після wizard | Wizard завершено — UI на порті **8080** |
| 403 — invalid username or password | Скинь конфіг: `docker volume rm dns_filter_agh_conf` та перезапусти |
| Реклама показується | Очисти кеш браузера, secondary DNS на роутері має бути порожній |
| DoH — `/dns-query` повертає 404 | Перевір `allow_unencrypted_doh: true` в конфігу AGH |
| DoH не працює | `docker logs caddy`, перевір що DuckDNS домен → IP VPS |
