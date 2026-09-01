#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR
REPO_REF="${REPO_REF:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/Lumitorus/LOCAL_COBALT_DOWNLOADER/${REPO_REF}}"
TEMP_BUNDLE=""

CTID="${CTID:-}"
LXC_HOSTNAME="${LXC_HOSTNAME:-cobalt}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
ROOTFS_STORAGE="${ROOTFS_STORAGE:-local-lvm}"
DISK_GB="${DISK_GB:-12}"
MEMORY_MB="${MEMORY_MB:-2048}"
SWAP_MB="${SWAP_MB:-512}"
CORES="${CORES:-2}"
BRIDGE="${BRIDGE:-vmbr0}"
IP_CONFIG="${IP_CONFIG:-dhcp}"
GATEWAY="${GATEWAY:-}"

log() { printf '\n[cobalt-lxc] %s\n' "$*"; }
die() { printf '\n[cobalt-lxc] ОШИБКА: %s\n' "$*" >&2; exit 1; }

cleanup() {
    [[ -z ${TEMP_BUNDLE} ]] || rm -rf -- "${TEMP_BUNDLE}"
}
trap cleanup EXIT

[[ ${EUID} -eq 0 ]] || die "запустите скрипт от root на узле Proxmox VE"
for command in pct pveam pvesh; do
    command -v "${command}" >/dev/null 2>&1 || die "${command} не найден; этот скрипт запускается только на Proxmox VE host"
done

readonly BUNDLE_FILES=(compose.yaml Dockerfile.web nginx.conf cookies.example.json .env.example scripts/install.sh)

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
    mkdir -p "${BUNDLE_DIR}/scripts"
    local file
    log "Локальный комплект не найден; загружаю файлы из ${RAW_BASE}"
    for file in "${BUNDLE_FILES[@]}"; do
        curl --proto '=https' --tlsv1.2 -fsSL "${RAW_BASE}/${file}" -o "${BUNDLE_DIR}/${file}" \
            || die "не удалось скачать ${file}. Репозиторий должен быть публичным, а REPO_REF — существовать"
    done
    chmod 0755 "${BUNDLE_DIR}/scripts/install.sh"
}

bundle_is_complete || download_bundle

if [[ -z ${CTID} ]]; then
    CTID="$(pvesh get /cluster/nextid)"
fi
pct status "${CTID}" >/dev/null 2>&1 && die "контейнер CTID ${CTID} уже существует"

log "Обновляю список LXC-шаблонов"
pveam update
template="$(pveam available --section system | awk '$2 ~ /^debian-12-standard_/ {print $2}' | sort -V | tail -n 1)"
[[ -n ${template} ]] || die "шаблон Debian 12 не найден в pveam"
template_volume="${TEMPLATE_STORAGE}:vztmpl/${template}"
if ! pveam list "${TEMPLATE_STORAGE}" | awk '{print $1}' | grep -Fxq "${template_volume}"; then
    log "Загружаю ${template}"
    pveam download "${TEMPLATE_STORAGE}" "${template}"
fi

net0="name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}"
[[ -n ${GATEWAY} ]] && net0+=",gw=${GATEWAY}"

log "Создаю unprivileged LXC ${CTID} (${LXC_HOSTNAME})"
pct create "${CTID}" "${template_volume}" \
    --hostname "${LXC_HOSTNAME}" \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --cores "${CORES}" \
    --memory "${MEMORY_MB}" \
    --swap "${SWAP_MB}" \
    --rootfs "${ROOTFS_STORAGE}:${DISK_GB}" \
    --net0 "${net0}" \
    --onboot 1 \
    --start 1

log "Жду запуска сети в контейнере"
for _ in $(seq 1 60); do
    pct exec "${CTID}" -- sh -c 'getent hosts get.docker.com >/dev/null 2>&1' && break
    sleep 2
done
pct exec "${CTID}" -- sh -c 'getent hosts get.docker.com >/dev/null 2>&1' || die "в LXC не появилась сеть/DNS"

pct exec "${CTID}" -- mkdir -p /root/cobalt-bundle/scripts
for file in compose.yaml Dockerfile.web nginx.conf cookies.example.json .env.example; do
    pct push "${CTID}" "${BUNDLE_DIR}/${file}" "/root/cobalt-bundle/${file}"
done
pct push "${CTID}" "${BUNDLE_DIR}/scripts/install.sh" "/root/cobalt-bundle/scripts/install.sh" --perms 0755

log "Устанавливаю Docker и Cobalt внутри LXC"
pct exec "${CTID}" -- env INSTALL_DIR=/opt/cobalt-local /root/cobalt-bundle/scripts/install.sh

container_ip="$(pct exec "${CTID}" -- hostname -I | awk '{print $1}')"
cat <<EOF

============================================================
LXC ${CTID} создан и Cobalt запущен.
Web-интерфейс: http://${container_ip}:8080/
API:           http://${container_ip}:9000/
Консоль LXC:   pct enter ${CTID}
Статус:        pct exec ${CTID} -- sh -lc 'cd /opt/cobalt-local && docker compose ps'
============================================================
EOF
