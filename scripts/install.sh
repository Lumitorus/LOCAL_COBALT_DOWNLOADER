#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR
INSTALL_DIR="${INSTALL_DIR:-/opt/cobalt-local}"
REPO_REF="${REPO_REF:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/${REPO_REF}}"
TEMP_BUNDLE=""

log() { printf '\n[cobalt] %s\n' "$*"; }
die() { printf '\n[cobalt] ОШИБКА: %s\n' "$*" >&2; exit 1; }

cleanup() {
    [[ -z ${TEMP_BUNDLE} ]] || rm -rf -- "${TEMP_BUNDLE}"
}
trap cleanup EXIT

if [[ ${EUID} -ne 0 ]]; then
    die "запустите скрипт от root: sudo $0"
fi

readonly BUNDLE_FILES=(compose.yaml Dockerfile.web nginx.conf cookies.example.json .env.example)

bundle_is_complete() {
    local file
    for file in "${BUNDLE_FILES[@]}"; do
        [[ -f "${BUNDLE_DIR}/${file}" ]] || return 1
    done
}

download_bundle() {
    command -v curl >/dev/null 2>&1 || die "для загрузки комплекта нужен curl"
    TEMP_BUNDLE="$(mktemp -d)"
    BUNDLE_DIR="${TEMP_BUNDLE}"
    local file
    log "Локальный комплект не найден; загружаю файлы из ${RAW_BASE}"
    for file in "${BUNDLE_FILES[@]}"; do
        curl --proto '=https' --tlsv1.2 -fsSL "${RAW_BASE}/${file}" -o "${BUNDLE_DIR}/${file}" \
            || die "не удалось скачать ${file}. Репозиторий должен быть публичным, а REPO_REF — существовать"
    done
}

bundle_is_complete || download_bundle

install_docker() {
    command -v curl >/dev/null 2>&1 || {
        apt-get update
        apt-get install -y ca-certificates curl
    }
    local installer
    installer="$(mktemp)"
    trap 'rm -f -- "${installer:-}"' RETURN
    curl -fsSL https://get.docker.com -o "${installer}"
    sh "${installer}"
}

if ! command -v docker >/dev/null 2>&1; then
    log "Docker не найден; устанавливаю Docker Engine официальным convenience-скриптом"
    command -v apt-get >/dev/null 2>&1 || die "автоустановка поддерживает Debian/Ubuntu. Установите Docker вручную и повторите запуск"
    install_docker
fi

docker info >/dev/null 2>&1 || {
    command -v systemctl >/dev/null 2>&1 && systemctl enable --now docker
    docker info >/dev/null 2>&1 || die "Docker установлен, но daemon недоступен"
}
docker compose version >/dev/null 2>&1 || die "не найден Docker Compose plugin"

log "Копирую конфигурацию в ${INSTALL_DIR}"
install -d -m 0755 "${INSTALL_DIR}"
for file in "${BUNDLE_FILES[@]}"; do
    install -m 0644 "${BUNDLE_DIR}/${file}" "${INSTALL_DIR}/${file}"
done

if [[ ! -f "${INSTALL_DIR}/cookies.json" ]]; then
    install -m 0600 "${INSTALL_DIR}/cookies.example.json" "${INSTALL_DIR}/cookies.json"
fi

primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
primary_ip="${primary_ip:-127.0.0.1}"
api_port="${API_PORT:-9000}"
web_port="${WEB_PORT:-8080}"
api_url="${API_PUBLIC_URL:-http://${primary_ip}:${api_port}/}"
web_host="${WEB_HOST:-${primary_ip}}"

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    sed \
        -e "s|^API_PUBLIC_URL=.*|API_PUBLIC_URL=${api_url}|" \
        -e "s|^WEB_HOST=.*|WEB_HOST=${web_host}|" \
        -e "s|^WEB_PORT=.*|WEB_PORT=${web_port}|" \
        -e "s|^API_PORT=.*|API_PORT=${api_port}|" \
        -e "s|^COOKIE_FILE=.*|COOKIE_FILE=./cookies.json|" \
        "${INSTALL_DIR}/.env.example" > "${INSTALL_DIR}/.env"
    chmod 0600 "${INSTALL_DIR}/.env"
else
    log "Сохраняю существующий ${INSTALL_DIR}/.env"
    api_url="$(sed -n 's/^API_PUBLIC_URL=//p' "${INSTALL_DIR}/.env" | tail -n 1)"
    api_url="${api_url:-http://${primary_ip}:${api_port}/}"
    web_port="$(sed -n 's/^WEB_PORT=//p' "${INSTALL_DIR}/.env" | tail -n 1)"
    web_port="${web_port:-8080}"
fi

cd "${INSTALL_DIR}"
log "Проверяю Compose-конфигурацию"
docker compose config --quiet

log "Загружаю API и собираю локальный web-интерфейс (первый запуск может занять несколько минут)"
docker compose pull cobalt-api
docker compose build --pull cobalt-web
docker compose up -d

log "Ожидаю готовности сервисов"
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
    api_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' cobalt-api 2>/dev/null || true)"
    web_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' cobalt-web 2>/dev/null || true)"
    [[ ${api_health} == healthy && ${web_health} == healthy ]] && break
    sleep 3
done

if [[ ${api_health:-} != healthy || ${web_health:-} != healthy ]]; then
    docker compose ps
    docker compose logs --tail=80
    die "сервисы не стали healthy за 180 секунд"
fi

cat <<EOF

============================================================
Cobalt готов.
Web-интерфейс: http://${primary_ip}:${web_port}/
API:           ${api_url}
Каталог:       ${INSTALL_DIR}

Статус:        cd ${INSTALL_DIR} && docker compose ps
Логи:          cd ${INSTALL_DIR} && docker compose logs -f
Обновление:    cd ${INSTALL_DIR} && docker compose pull cobalt-api && docker compose build --pull --no-cache cobalt-web && docker compose up -d
Остановка:     cd ${INSTALL_DIR} && docker compose down
============================================================
EOF
