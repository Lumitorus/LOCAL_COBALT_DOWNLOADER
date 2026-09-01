# Локальный Cobalt: Docker, Linux и Proxmox LXC

> 🤖 Этот проект создан при помощи ИИ: первоначальная архитектура, Docker-конфигурация, установочные скрипты и документация подготовлены совместно с OpenAI Codex. Результат был проверен реальной сборкой, healthcheck и функциональным API-тестом. Ответственность за публикацию и дальнейшее сопровождение проекта несёт автор репозитория.

Этот комплект разворачивает собственный [Cobalt](https://github.com/imputnet/cobalt):

- локальный web-интерфейс на порту `8080`;
- официальный processing API на порту `9000`;
- установку на Debian/Ubuntu одним скриптом;
- отдельный bootstrap-скрипт, создающий Debian 12 LXC на Proxmox VE.

## Можно ли скачать «из любых мест»

Собственный инстанс снимает ограничения и перегрузку публичного `cobalt.tools`, но не превращает Cobalt в универсальный загрузчик. Cobalt работает только с [поддерживаемыми сервисами](https://github.com/imputnet/cobalt/blob/main/api/README.md#supported-services) и публично доступным контентом. На момент подготовки комплекта поддерживаются YouTube, TikTok, Instagram, X/Twitter, Reddit, Vimeo, VK, Rutube и другие перечисленные в upstream-проекте сервисы.

Останутся внешние ограничения:

- приватный, платный или удалённый контент не станет доступным;
- сервис может блокировать IP вашего сервера, регион или слишком частые запросы;
- отдельным сервисам могут понадобиться cookies собственного аккаунта;
- сайт-источник может изменить API, и загрузка временно сломается до обновления Cobalt;
- использовать следует только контент, который вы вправе скачивать.

Если проблема связана с IP/географией хоста, Cobalt поддерживает `HTTP_PROXY` и `HTTPS_PROXY`. В этом комплекте они задаются как `COBALT_HTTP_PROXY` и `COBALT_HTTPS_PROXY`, чтобы случайно не унаследовать системный proxy Docker-хоста, а внутри контейнера преобразуются в штатные переменные [официальной конфигурации API](https://github.com/imputnet/cobalt/blob/main/docs/api-env-variables.md#http_proxy-https_proxy-no_proxy). Это не средство обхода прав доступа.

## Что находится в комплекте

| Файл | Назначение |
|---|---|
| `compose.yaml` | API и локальный frontend |
| `Dockerfile.web` | воспроизводимая сборка frontend из официального GitHub |
| `nginx.conf` | раздача статического frontend с нужными COOP/COEP-заголовками |
| `.env.example` | адреса, порты, версия frontend и proxy |
| `cookies.example.json` | безопасная пустая заготовка cookies |
| `scripts/install.sh` | установка на обычный Debian/Ubuntu-хост |
| `scripts/proxmox-lxc.sh` | создание LXC и запуск установки из Proxmox host |

API запускается из официального образа `ghcr.io/imputnet/cobalt:11`. Frontend собирается из зафиксированного commit официального репозитория, чтобы повторная сборка не менялась неожиданно. Watchtower не используется: автоматическому контейнеру не выдаётся привилегированный доступ к `/var/run/docker.sock`.

## Требования

Для ручного запуска:

- Linux, macOS или Windows с Docker Engine/Docker Desktop;
- Docker Compose v2 (`docker compose`);
- примерно 2 ГБ RAM и 3–5 ГБ свободного места на первую сборку;
- исходящий HTTPS-доступ к GitHub, GHCR, npm registry и нужным медиасервисам.

Для автоматической установки нужен Debian/Ubuntu и запуск от `root`. Если Docker отсутствует, используется официальный [Docker convenience script](https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script). Для постоянно обслуживаемого production-сервера Docker рекомендует установку из apt-репозитория; convenience script здесь выбран для одноразового bootstrap.

## Что проверено

Комплект фактически проверен 1 сентября 2026 года на Docker Engine 29.6.1 / Compose 5.2.0 (Linux containers, x86_64):

- `docker compose config --quiet` проходит;
- frontend успешно собирается из зафиксированного upstream commit;
- API `ghcr.io/imputnet/cobalt:11` и frontend переходят в `healthy`;
- `GET :9000/`, `GET :8080/` и `GET :8080/healthz` возвращают HTTP 200;
- frontend отдаёт необходимые `Cross-Origin-Opener-Policy` и `Cross-Origin-Embedder-Policy`;
- функциональный `POST :9000/` для публичной ссылки из официального Streamable test fixture возвращает `status: redirect` и имя MP4.

На проверке API сообщил версию Cobalt `11.7.1` и commit `a636575b09de1fc55d9b8cd98cac88f5f2f16b42`. Shell-синтаксис обоих `.sh` проверен через `bash -n`. Само создание LXC не запускалось, поскольку для него необходим настоящий Proxmox VE host; параметры `pct` подготовлены под Debian 12 unprivileged LXC.

## Установка одной командой

### Обычный Debian/Ubuntu-сервер

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/main/scripts/install.sh \
  | sudo bash
```

После завершения команда напечатает адрес web-интерфейса, API, каталог установки и команды управления.

### Proxmox VE LXC

Команда выполняется в shell **самого Proxmox VE host** от `root`:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/main/scripts/proxmox-lxc.sh \
  | bash
```

Она загрузит комплект, создаст Debian 12 LXC, установит в него Docker и запустит Cobalt.

> Запуск `curl | bash` удобен, но выполняет актуальный код ветки `main` с правами root. Перед запуском можно [открыть Linux-скрипт](https://github.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/blob/main/scripts/install.sh) или [Proxmox-скрипт](https://github.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/blob/main/scripts/proxmox-lxc.sh) и проверить содержимое. Для воспроизводимой установки используйте URL конкретного commit вместо `main` и передайте такой же `REPO_REF`.

## Быстрый запуск через Docker Compose

1. Скопируйте файл окружения:

   ```bash
   cp .env.example .env
   ```

2. Отредактируйте `.env`. Адрес API должен быть доступен **из браузера пользователя**, а не только внутри Docker:

   ```dotenv
   API_PUBLIC_URL=http://192.168.1.50:9000/
   WEB_HOST=192.168.1.50
   WEB_PORT=8080
   API_PORT=9000
   ```

   Завершающий `/` в `API_PUBLIC_URL` обязателен для tunnel-ссылок Cobalt. Если Cobalt используется только на том же компьютере, подойдёт `http://localhost:9000/`.

3. Проверьте и запустите:

   ```bash
   docker compose config --quiet
   docker compose pull cobalt-api
   docker compose build cobalt-web
   docker compose up -d
   docker compose ps
   ```

4. Откройте `http://192.168.1.50:8080/`. API доступен на `http://192.168.1.50:9000/`; `GET /` должен вернуть сведения об инстансе.

Просмотр логов и остановка:

```bash
docker compose logs -f
docker compose down
```

## Автоустановка на Debian/Ubuntu

Если установка одной командой не нужна, клонируйте репозиторий и запустите локальный скрипт:

```bash
git clone https://github.com/Lumitorus/LOCAL_COBALT_DOWNLOADER.git
cd LOCAL_COBALT_DOWNLOADER
chmod +x scripts/install.sh
sudo ./scripts/install.sh
```

Скрипт:

1. проверит Docker и при отсутствии установит Docker Engine;
2. скопирует конфигурацию в `/opt/cobalt-local`;
3. определит основной IP и создаст `.env`;
4. проверит, не запущен ли уже проект `cobalt-local`;
5. загрузит API, соберёт frontend и запустит Compose;
6. при повторной установке удалит старые контейнеры и создаст их заново;
7. дождётся healthcheck обоих контейнеров и напечатает адреса и команды управления.

Параметры можно передать окружением:

```bash
sudo env \
  INSTALL_DIR=/srv/cobalt \
  API_PUBLIC_URL=http://10.10.20.15:9000/ \
  WEB_HOST=10.10.20.15 \
  WEB_PORT=8080 \
  API_PORT=9000 \
  ./scripts/install.sh
```

Повторный запуск выполняет чистую переустановку контейнеров. Сначала скрипт проверяет, что контейнеры `cobalt-api` и `cobalt-web` действительно принадлежат Compose-проекту `cobalt-local`, затем заранее загружает/собирает новые образы, выполняет `docker compose down --remove-orphans` и создаёт контейнеры заново с `--force-recreate`. Существующие `.env`, `cookies.json` и данные конфигурации при этом сохраняются; Docker volumes скрипт не удаляет. Если одно из занятых имён принадлежит постороннему контейнеру, установка безопасно остановится и не станет его удалять.

## Proxmox VE: автоматическое создание LXC

Скрипт запускается **на Proxmox VE host**, не внутри гостя. По умолчанию он создаёт unprivileged Debian 12 LXC с Docker-совместимыми `nesting=1,keyctl=1`, DHCP и ресурсами 2 CPU / 2 ГБ RAM / 12 ГБ disk.

```bash
chmod +x scripts/proxmox-lxc.sh
sudo ./scripts/proxmox-lxc.sh
```

Основные параметры:

```bash
sudo env \
  CTID=250 \
  LXC_HOSTNAME=cobalt \
  TEMPLATE_STORAGE=local \
  ROOTFS_STORAGE=local-lvm \
  BRIDGE=vmbr0 \
  IP_CONFIG=dhcp \
  DISK_GB=12 \
  MEMORY_MB=2048 \
  CORES=2 \
  ./scripts/proxmox-lxc.sh
```

Пример статического IPv4:

```bash
sudo env \
  CTID=250 \
  IP_CONFIG=192.168.1.50/24 \
  GATEWAY=192.168.1.1 \
  ./scripts/proxmox-lxc.sh
```

Если `CTID` не задан, берётся следующий свободный ID кластера. Если заданный `CTID` уже существует, скрипт проверит его hostname и маркер `Managed by LOCAL_COBALT_DOWNLOADER`. Для LXC, созданного старой версией скрипта без маркера, дополнительно проверяется наличие `/opt/cobalt-local/compose.yaml`. Только после успешной проверки контейнер будет остановлен, удалён вместе со своим rootfs и создан заново. Чужой LXC с совпавшим ID или hostname скрипт не удалит. После установки он выведет URL и команду `pct enter CTID`.

> В отличие от повторного запуска `scripts/install.sh` внутри обычной Linux-системы, пересоздание Proxmox LXC удаляет весь его rootfs. Если вы изменяли `.env`, `cookies.json` или хранили внутри LXC другие данные, сначала сделайте резервную копию.

> Docker в unprivileged LXC — распространённая, но вложенная схема. Для максимальной изоляции и официально наиболее предсказуемого Docker-окружения используйте VM. Не включайте `privileged` и не пробрасывайте Docker socket Proxmox host внутрь контейнера.

## Cookies для контента, требующего авторизации

Официальная документация допускает локальный `cookies.json`. Автоустановщик уже монтирует его read-only в API. При ручном запуске сначала скопируйте `cookies.example.json` в `cookies.json` и укажите `COOKIE_FILE=./cookies.json` в `.env`. Заполните файл по структуре [upstream-примера](https://github.com/imputnet/cobalt/blob/main/docs/examples/cookies.example.json), затем:

```bash
docker compose restart cobalt-api
```

Не публикуйте cookies в Git, не пересылайте их и используйте отдельный аккаунт с минимальными правами. Cookies дают контейнеру права соответствующей сессии и могут истечь или привести к защитной блокировке аккаунта.

Автоустановщик выставляет владельца `root:1000` и режим `0640`: официальный API-контейнер работает с UID/GID `1000`, поэтому файл `root:root 0600` приводит к `EACCES` и cookies не загружаются. Для уже установленного экземпляра исправление выглядит так:

```bash
cd /opt/cobalt-local
chown root:1000 cookies.json
chmod 0640 cookies.json
docker compose restart cobalt-api
```

## Reverse proxy и публикация в интернет

Текущая конфигурация рассчитана на доверенную LAN/VPN. Не выставляйте порты `8080` и `9000` напрямую в интернет. Upstream рекомендует reverse proxy и защиту публичного API с помощью Turnstile/API keys: [официальное руководство](https://github.com/imputnet/cobalt/blob/main/docs/protect-an-instance.md).

Для HTTPS понадобятся два публичных адреса, например:

- `https://cobalt.example.org` → frontend `127.0.0.1:8080`;
- `https://cobalt-api.example.org` → API `127.0.0.1:9000`.

Тогда задайте:

```dotenv
API_PUBLIC_URL=https://cobalt-api.example.org/
WEB_HOST=cobalt.example.org
```

После изменения `API_PUBLIC_URL` frontend нужно пересобрать, потому что `WEB_DEFAULT_API` — build-time переменная:

```bash
docker compose build --no-cache cobalt-web
docker compose up -d
```

Также ограничьте firewall, настройте TLS и включите API key/Turnstile до публикации. Не смешивайте HTTPS-страницу frontend с HTTP API: браузер заблокирует mixed content.

## Обновление и откат

Обновить API и пересобрать frontend из ref, указанного в `.env`:

```bash
docker compose pull cobalt-api
docker compose build --pull --no-cache cobalt-web
docker compose up -d
docker compose ps
```

Для перехода на текущий upstream измените `COBALT_WEB_REF=main`. Для воспроизводимости после успешной проверки лучше заменить `main` на конкретный commit (`git ls-remote https://github.com/imputnet/cobalt.git refs/heads/main`).

Перед обновлением сохраните рабочий `.env`, `cookies.json` и значение `COBALT_WEB_REF`. Откат frontend выполняется возвратом прежнего commit и повторной сборкой. Тег официального API `:11` плавающий; для строгого production-отката дополнительно зафиксируйте digest образа.

## Диагностика

```bash
cd /opt/cobalt-local
docker compose ps
docker compose logs --tail=200 cobalt-api
docker compose logs --tail=200 cobalt-web
curl -fsS http://127.0.0.1:9000/
curl -fsS http://127.0.0.1:8080/healthz
```

### YouTube: `file tunnel is empty` и файлы 0 байт

Локальный сервер не гарантирует загрузку каждого YouTube-видео. YouTube выборочно переводит ролики на SABR и усиливает PoToken-проверки. Cobalt может получить название и список форматов, создать tunnel, а сами media URL при этом вернут пустой поток. Разработчики Cobalt [публично отмечают](https://github.com/imputnet/cobalt/discussions/1374), что универсального способа работы с SABR у проекта пока нет; для self-hosted экземпляров остаются открытыми аналогичные issues [#1455](https://github.com/imputnet/cobalt/issues/1455) и [#1475](https://github.com/imputnet/cobalt/issues/1475).

На Cobalt 11.7.1 ссылка `https://youtu.be/Cv0xZYTgO7E` была проверена через IOS, WEB, MWEB, ANDROID, TV, TV_EMBEDDED, WEB_EMBEDDED и WEB_CREATOR, с cookies и без них, в 1080p/720p/360p, audio-only, mute и deprecated HLS. Результат — либо tunnel с `Content-Length: 0`, либо `video unavailable`; контрольный YouTube-ролик на том же сервере отдавал данные. Это исключает ошибку адреса, CORS, порта, Docker, общую блокировку YouTube и права cookies.

`yt-session-generator` не является универсальным исправлением этой ситуации. Его текущий официальный webserver-образ внутри unprivileged Proxmox LXC может возвращать `503`, а Chromium workaround из [issue #3](https://github.com/imputnet/yt-session-generator/issues/3) исправляет запуск браузера, но не заставляет современный YouTube выдавать ожидаемый PoToken. Поэтому генератор намеренно не включён в Compose: неработающий sidecar только добавлял бы ошибки каждые пять минут.

- **Frontend открыт, но запросы не идут:** проверьте, что `API_PUBLIC_URL` доступен с компьютера/телефона, где открыт браузер. `cobalt-api:9000` здесь использовать нельзя.
- **Сайт после смены адреса обращается к старому API:** пересоберите frontend с `--no-cache` и очистите данные сайта/кэш браузера.
- **Один сервис не скачивает:** изучите API logs; возможно, нужны cookies, обновление Cobalt или другой исходящий IP.
- **YouTube отвечает bot/403:** это ограничение YouTube/IP или конкретного media stream. Попробуйте другой исходящий IP и обновление Cobalt, но не рассчитывайте, что cookies или PoToken исправят каждый SABR-ролик.
- **Контейнеры не стартуют в LXC:** проверьте `pct config CTID` на `unprivileged: 1` и `features: nesting=1,keyctl=1`, свободное место и AppArmor/kernel Proxmox.

## Источники и лицензии

- [официальная инструкция self-hosting](https://github.com/imputnet/cobalt/blob/main/docs/run-an-instance.md);
- [официальный пример Docker Compose](https://github.com/imputnet/cobalt/blob/main/docs/examples/docker-compose.example.yml);
- [переменные API](https://github.com/imputnet/cobalt/blob/main/docs/api-env-variables.md);
- [документация frontend](https://github.com/imputnet/cobalt/blob/main/web/README.md).

Cobalt API распространяется под AGPL-3.0. Frontend — CC BY-NC-SA 4.0, а брендовые материалы имеют отдельные ограничения; неизменённый брендированный frontend разрешён для некоммерческого хостинга согласно его README. Этот комплект не изменяет код или брендинг Cobalt, но при коммерческом использовании обязательно самостоятельно проверьте лицензионные условия.
