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
│   ├── Dockerfile                     # Кастомний entrypoint
│   ├── entrypoint.sh                  # Генерація конфігу з env змінних
│   └── AdGuardHome.yaml.template      # Шаблон конфігу
└── caddy/
    ├── Dockerfile                     # Caddy з DuckDNS плагіном
    └── Caddyfile                      # Reverse proxy для DoH
```

## Два режими запуску

| Режим | Коли використовувати | Як запустити |
|-------|---------------------|-------------|
| **Автоматичний** | Знаєш логін/пароль заздалегідь | Заповни `.env` → `docker compose up -d --build` |
| **Wizard** | Хочеш налаштувати вручну через UI | Не заповнюй `AGH_USER`/`AGH_PASSWORD` → wizard на `:3000` |

---

## Фаза 1: Базове налаштування (plain DNS)

### Крок 1 — Дізнайся домашню IP

```bash
curl ifconfig.me
```

Збережи цю IP — вона потрібна для правил фаєрволу.

### Крок 2 — Налаштуй Hetzner Firewall

[Hetzner Cloud Console](https://console.hetzner.cloud) → **Firewalls** → **Create Firewall**.

Додай **Inbound** правила:

| Protocol | Port | Source            | Опис           |
|----------|------|-------------------|----------------|
| TCP      | 22   | `ДОМАШНЯ_IP/32`  | SSH            |
| TCP+UDP  | 53   | `ДОМАШНЯ_IP/32`  | DNS            |
| TCP      | 3000 | `ДОМАШНЯ_IP/32`  | AGH wizard     |
| TCP      | 8080 | `ДОМАШНЯ_IP/32`  | AGH веб-панель |

Перейди у вкладку **Servers** всередині фаєрволу і **прикріпи його до свого VPS**.

> Hetzner Firewall працює до сервера — заблокований трафік навіть не дійде до VPS.

### Крок 3 — Скопіюй файли на VPS

```bash
scp -r dns_filter/ root@YOUR_VPS_IP:/opt/dns_filter
```

### Крок 4 — Звільни порт 53 на VPS

Порт 53 зазвичай зайнятий `systemd-resolved`. Вимкни його:

```bash
ssh root@YOUR_VPS_IP

sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

Перевір що порт вільний:

```bash
sudo ss -tulnp | grep ':53'
# Має бути порожньо
```

### Крок 5 — Запуск

**Варіант A — автоматичний (без wizard):**

```bash
cd /opt/dns_filter
cp .env.example .env
nano .env   # встанови AGH_USER та AGH_PASSWORD
docker compose up -d --build
```

Веб-панель одразу доступна на `http://YOUR_VPS_IP:8080`.

**Варіант B — через wizard:**

```bash
cd /opt/dns_filter
docker compose up -d --build
```

Без `AGH_USER`/`AGH_PASSWORD` в `.env` запуститься wizard:

1. Відкрий `http://YOUR_VPS_IP:3000`
2. **Крок 1/5** — Ласкаво просимо. Натисни **Далі**
3. **Крок 2/5** — Мережеві інтерфейси:
   - Веб-інтерфейс: **Усі інтерфейси**, порт **80**
   - DNS-сервер: **Усі інтерфейси**, порт **53**
   - Натисни **Далі**
4. **Крок 3/5** — Створи **логін** та **пароль** адміна
5. **Крок 4/5** — Інформація про налаштування пристроїв. Натисни **Далі**
6. **Крок 5/5** — Готово

> Після wizard UI на порті 3000 зупиняється. Веб-панель тепер на:
> **`http://YOUR_VPS_IP:8080`**

### Крок 6 — Перевір що все працює

```bash
docker compose ps
# Колонка PORTS має показувати: 0.0.0.0:53->53, 0.0.0.0:8080->80
```

Якщо колонка PORTS порожня — контейнер не зміг зайняти порти. Виправлення:

```bash
docker compose down
docker compose up -d
```

### Крок 7 — Налаштування DNS (тільки для варіанту B)

> При автоматичному запуску (варіант A) це вже налаштовано в шаблоні.

В веб-панелі AdGuard Home (`http://YOUR_VPS_IP:8080`):

**Settings → DNS settings:**

| Параметр | Значення |
|----------|----------|
| Upstream DNS servers | `https://1.1.1.1/dns-query` |
| Bootstrap DNS servers | `1.1.1.1` |
| Parallel requests | Увімкнено |

Натисни **Test upstreams** → потім **Apply**.

### Крок 8 — Додай блоклісти (тільки для варіанту B)

> При автоматичному запуску (варіант A) блоклісти вже додані.

**Filters → DNS blocklists → Add blocklist → Add a custom list:**

| Назва | URL |
|-------|-----|
| OISD Big | `https://big.oisd.nl` |
| Steven Black | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| 1Hosts Lite | `https://o0.pages.dev/Lite/adblock.txt` |

> AdGuard DNS filter увімкнений за замовчуванням.

### Крок 9 — Налаштуй роутер

1. Відкрий панель роутера (зазвичай `192.168.31.1` або `miwifi.com`)
2. Увійди в адмінку
3. Перейди в **Settings → Network settings**
4. Знайди розділ **DNS**
5. Встанови **Primary DNS**: `YOUR_VPS_IP`
6. **Secondary DNS**: залиш порожнім (або `YOUR_VPS_IP` ще раз)
7. Збережи і **перезавантаж роутер**

> **НЕ ставити публічний DNS (типу 8.8.8.8) як secondary** — роутер буде
> відправляти частину запитів напряму туди, минаючи фільтр.

### Крок 10 — Перевірка

З будь-якого пристрою в домашній мережі:

```bash
# Має повернути 0.0.0.0 (заблоковано)
nslookup ads.google.com YOUR_VPS_IP

# Має повернути реальну IP (не заблоковано)
nslookup google.com YOUR_VPS_IP
```

Відкрий браузер → зайди на сайт з рекламою → реклама має бути заблокована.
В дашборді AdGuard Home на `http://YOUR_VPS_IP:8080` мають з'явитись логи запитів.

---

## Фаза 2: DoH для мобільних пристроїв (опціонально)

DoH (DNS-over-HTTPS) шифрує DNS-запити. Корисно для телефонів/ноутбуків, особливо поза домом. Потрібен домен для валідного TLS-сертифіката.

### Крок 1 — Отримай безкоштовний домен (DuckDNS)

1. Зайди на [duckdns.org](https://www.duckdns.org) → увійди через GitHub або Google
2. Створи субдомен (напр. `myfilter`) → отримаєш `myfilter.duckdns.org`
3. Встав IP свого **VPS**
4. Скопіюй **token** зі сторінки

### Крок 2 — Налаштуй .env

На VPS:

```bash
cd /opt/dns_filter
nano .env
```

Додай (або розкоментуй):

```
DUCKDNS_TOKEN=abc123-your-actual-token
DUCKDNS_DOMAIN=myfilter.duckdns.org
```

### Крок 3 — Онови Hetzner Firewall

Додай нове Inbound правило:

| Protocol | Port | Source            | Опис        |
|----------|------|-------------------|-------------|
| TCP+UDP  | 443  | `ДОМАШНЯ_IP/32`  | DoH + HTTPS |

> Щоб DoH працював для мобільних пристроїв **поза домом**, зміни source на
> `0.0.0.0/0` — це безпечно, бо Caddy + AdGuard Home вимагають авторизацію.

### Крок 4 — Запусти з DoH профілем

```bash
docker compose --profile doh up -d --build
```

Перший білд займає ~2 хвилини (збирає Caddy з DuckDNS плагіном).

Перевір:

```bash
docker compose --profile doh ps
# Мають бути два контейнери: "adguard" та "caddy"
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
- Server URL: `https://myfilter.duckdns.org/dns-query`
- Завантаж і встанови профіль на iPhone/iPad

**Android:**

Android Private DNS використовує DoT (порт 853), а не DoH. Два варіанти:
- Встанови [Intra](https://play.google.com/store/apps/details?id=app.intra) або [AdGuard](https://adguard.com/adguard-android/overview.html) і вкажи DoH URL
- Або налаштуй DoT (див. Фазу 3)

---

## Фаза 3: DoT для Android Private DNS (опціонально)

Android Private DNS потребує DNS-over-TLS (порт 853).

### Крок 1 — Скопіюй сертифікати з Caddy в AdGuard Home

Caddy автоматично отримує сертифікати Let's Encrypt. Скопіюй їх для AdGuard Home:

```bash
cat > /opt/dns_filter/sync-certs.sh << 'SCRIPT'
#!/bin/bash
set -e
source /opt/dns_filter/.env
CERT_DIR="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DUCKDNS_DOMAIN}"

docker cp "caddy:${CERT_DIR}/${DUCKDNS_DOMAIN}.crt" ./adguardhome/conf/cert.pem
docker cp "caddy:${CERT_DIR}/${DUCKDNS_DOMAIN}.key" ./adguardhome/conf/key.pem
docker restart adguard
echo "Сертифікати синхронізовані, AdGuard Home перезапущений."
SCRIPT
chmod +x /opt/dns_filter/sync-certs.sh

./sync-certs.sh
```

> Caddy оновлює сертифікати автоматично. Запускай `./sync-certs.sh` кожні ~60 днів,
> або додай cron: `0 3 1 */2 * /opt/dns_filter/sync-certs.sh`

### Крок 2 — Увімкни шифрування в AdGuard Home

Відкрий `http://YOUR_VPS_IP:8080` → **Settings → Encryption settings:**

| Параметр | Значення |
|----------|----------|
| Enable encryption | Так |
| Server name | `myfilter.duckdns.org` |
| Certificate path | `/opt/adguardhome/conf/cert.pem` |
| Private key path | `/opt/adguardhome/conf/key.pem` |
| HTTPS port | `0` (Caddy обробляє HTTPS) |
| DNS-over-TLS port | `853` |

Натисни **Save**.

### Крок 3 — Онови Hetzner Firewall

Додай Inbound правило:

| Protocol | Port | Source      | Опис |
|----------|------|-------------|------|
| TCP      | 853  | `0.0.0.0/0` | DoT  |

### Крок 4 — Налаштуй Android

Settings → Network & Internet → Private DNS → **Hostname постачальника приватного DNS:**

```
myfilter.duckdns.org
```

---

## Обслуговування

### Оновлення контейнерів

```bash
cd /opt/dns_filter
docker compose pull
docker compose up -d --build                       # без DoH
docker compose --profile doh up -d --build         # з DoH
```

### Перегляд логів

```bash
docker logs -f adguard    # логи AdGuard Home
docker logs -f caddy      # логи Caddy (якщо DoH увімкнений)
docker compose ps         # статус контейнерів
```

### Змінилась домашня IP

Якщо провайдер видав нову IP:

1. Дізнайся нову IP: `curl ifconfig.me`
2. Онови правила в Hetzner Firewall
3. DuckDNS: онови IP на [duckdns.org](https://www.duckdns.org) або через API:
   ```bash
   curl "https://www.duckdns.org/update?domains=myfilter&token=YOUR_TOKEN&ip="
   ```

### Вирішення проблем

| Проблема | Рішення |
|----------|---------|
| Не відкривається порт 3000 | Фаєрвол не прикріплений до сервера, або IP змінилась |
| Порт 53 зайнятий | Вимкни `systemd-resolved` (крок 4, фаза 1) |
| Контейнер запущений, але порти не прокинуті | `docker compose down && docker compose up -d` |
| ERR_CONNECTION_REFUSED після wizard | Wizard завершено — UI переїхав на порт **8080** |
| Реклама все ще показується | Очисти кеш браузера, перевір що secondary DNS на роутері порожній |
| DoH не працює | `docker logs caddy`, перевір що DuckDNS домен вказує на IP VPS |
| `/dns-query` повертає 404 | Перевір `allow_unencrypted_doh: true` в конфігу AGH |
