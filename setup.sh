#!/usr/bin/env bash
# setup.sh — Telegram Web A on Synology NAS
# Builds telegram-tt on the HOST (not inside Docker), then packages into nginx image.
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; WHT='\033[1;37m'; NC='\033[0m'

ok()   { echo -e "${GRN}[OK]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
inf()  { echo -e "${CYN}[i]${NC} $*"; }
hdr()  { echo -e "\n${BLU}=== $* ===${NC}"; }

echo -e "${WHT}=== Telegram Web A - Synology NAS ===${NC}\n"

# ── 1. Docker ─────────────────────────────────────────────────────────────────
hdr "Docker"
command -v docker >/dev/null 2>&1 || err "Docker не найден. Установите Container Manager в DSM."
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    err "docker compose не найден."
fi
ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 2. Node.js ────────────────────────────────────────────────────────────────
hdr "Node.js"

load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    return 0
}

# Check node version >= 22 (Synology Package Center ships v20 which is too old)
node_version_ok() {
    command -v node >/dev/null 2>&1 || return 1
    local major; major=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
    [ "$major" -ge 22 ] 2>/dev/null
}

# Always load nvm first — it may override the system node
load_nvm

if node_version_ok; then
    ok "Node: $(node --version)"
else
    if command -v node >/dev/null 2>&1; then
        warn "Node $(node --version) слишком старый (нужен >=22)"
    else
        inf "Node.js не найден"
    fi

    # Install nvm-sh if not present.
    # Synology ships its own 'nvm' tool that cannot install new versions — we need nvm-sh.
    if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
        inf "Устанавливаем nvm-sh..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        load_nvm
    fi

    # After load_nvm, the nvm shell function overrides Synology's nvm binary
    nvm install 22
    nvm use 22
    ok "Node: $(node --version)"
fi

command -v npm >/dev/null 2>&1 || err "npm не найден после установки Node."
ok "npm: $(npm --version)"

# ── 3. Директория ────────────────────────────────────────────────────────────
hdr "Директория"
DEFAULT_DIR=""
for vol in /volume1 /volume2 /volume3; do
    [ -d "$vol" ] && DEFAULT_DIR="$vol/docker/telegram-web" && break
done
DEFAULT_DIR="${DEFAULT_DIR:-$HOME/telegram-web}"

echo -n "  Путь установки [${DEFAULT_DIR}]: "
read -r INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"
mkdir -p "$INSTALL_DIR"
ok "Директория: $INSTALL_DIR"

# ── 4. API credentials ────────────────────────────────────────────────────────
hdr "Telegram API Credentials"
inf "Получите на: https://my.telegram.org/apps"
echo

EXISTING_API_ID=""; EXISTING_HASH=""
if [ -f "$INSTALL_DIR/.env" ]; then
    EXISTING_API_ID=$(grep -E '^API_ID='   "$INSTALL_DIR/.env" | cut -d= -f2 || true)
    EXISTING_HASH=$(  grep -E '^API_HASH=' "$INSTALL_DIR/.env" | cut -d= -f2 || true)
fi

while true; do
    PROMPT="API_ID"; [ -n "$EXISTING_API_ID" ] && PROMPT="API_ID [${EXISTING_API_ID}]"
    echo -n "  $PROMPT: "; read -r v; API_ID="${v:-$EXISTING_API_ID}"
    [[ "$API_ID" =~ ^[0-9]+$ ]] && break; warn "API_ID должен быть числом"
done
while true; do
    PROMPT="API_HASH"; [ -n "$EXISTING_HASH" ] && PROMPT="API_HASH [${EXISTING_HASH:0:8}...]"
    echo -n "  $PROMPT: "; read -r v; API_HASH="${v:-$EXISTING_HASH}"
    [ "${#API_HASH}" -ge 16 ] && break; warn "API_HASH слишком короткий"
done

# ── 5. Порт ──────────────────────────────────────────────────────────────────
hdr "Порт"
EXISTING_PORT=""
if [ -f "$INSTALL_DIR/.env" ]; then
    EXISTING_PORT=$(grep -E '^HOST_PORT=' "$INSTALL_DIR/.env" | cut -d= -f2 || true)
fi
DEFAULT_PORT="${EXISTING_PORT:-4430}"
echo -n "  Порт на Synology [${DEFAULT_PORT}]: "; read -r v; HOST_PORT="${v:-$DEFAULT_PORT}"
ok "http://<synology-ip>:${HOST_PORT}"

# ── 6. Сохранить конфиг ──────────────────────────────────────────────────────
hdr "Конфиг"
cat > "$INSTALL_DIR/.env" <<ENV
API_ID=${API_ID}
API_HASH=${API_HASH}
HOST_PORT=${HOST_PORT}
ENV
ok ".env"

cat > "$INSTALL_DIR/nginx.conf" <<'NGINX'
server {
    listen 443 ssl;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Если зашли по http:// на https-порт — редиректим на https
    error_page 497 =301 https://$host:$server_port$request_uri;

    gzip on; gzip_vary on; gzip_min_length 1024;
    gzip_types text/plain text/css text/xml application/javascript
               application/json application/xml image/svg+xml font/woff2;

    add_header X-Content-Type-Options  "nosniff"       always;
    add_header X-Frame-Options         "SAMEORIGIN"    always;
    add_header Referrer-Policy         "strict-origin" always;
    add_header Cross-Origin-Opener-Policy   "same-origin"  always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location / { try_files $uri $uri/ /index.html; }

    location ~* \.(js|css|woff2?|png|jpg|svg|ico|webp|avif)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Cross-Origin-Opener-Policy   "same-origin"  always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
    }

    location ~ /\. { deny all; }
}
NGINX
ok "nginx.conf"

cat > "$INSTALL_DIR/Dockerfile" <<'DOCKERFILE'
FROM nginx:1.27-alpine
COPY dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY ssl/ /etc/nginx/ssl/
EXPOSE 443
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- --no-check-certificate https://localhost/ || exit 1
DOCKERFILE
ok "Dockerfile"

cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
services:
  telegram-web:
    image: telegram-web-a:local
    container_name: telegram-web
    restart: unless-stopped
    ports:
      - "${HOST_PORT}:443"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "--no-check-certificate", "https://localhost/"]
      interval: 30s
      timeout: 5s
      retries: 3
COMPOSE
ok "docker-compose.yml"

# ── SSL-сертификат (самоподписанный) ─────────────────────────────────────────
# Telegram Web A требует secure context (HTTPS): по HTTP браузер отключает
# crypto.subtle и SharedArrayBuffer → приложение пишет "browser not supported".
SYNO_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SYNO_IP="${SYNO_IP:-127.0.0.1}"
mkdir -p "$INSTALL_DIR/ssl"
if [ -f "$INSTALL_DIR/ssl/cert.pem" ] && [ -f "$INSTALL_DIR/ssl/key.pem" ]; then
    ok "SSL-сертификат уже есть"
else
    inf "Генерируем самоподписанный SSL-сертификат для $SYNO_IP..."
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$INSTALL_DIR/ssl/key.pem" \
        -out    "$INSTALL_DIR/ssl/cert.pem" \
        -subj   "/CN=$SYNO_IP" \
        -addext "subjectAltName=IP:$SYNO_IP" >/dev/null 2>&1 \
      || err "Не удалось создать SSL-сертификат (нужен openssl)"
    ok "SSL-сертификат создан"
fi

# ── 7. Сборка telegram-tt на хосте ───────────────────────────────────────────
hdr "Сборка telegram-tt (на хосте, не внутри Docker)"
warn "Занимает 15-30 минут и ~2GB RAM при первом запуске"
warn "npm скачает ~900MB зависимостей с npm registry"
echo
echo -n "  Начать сборку сейчас? [Y/n]: "
read -r BUILD_NOW; BUILD_NOW="${BUILD_NOW:-Y}"

if [[ ! "$BUILD_NOW" =~ ^[Yy]$ ]]; then
    ok "Файлы созданы: $INSTALL_DIR"
    echo "  Запустите вручную: bash $INSTALL_DIR/setup.sh"
    exit 0
fi

BUILD_DIR="$INSTALL_DIR/.build"
mkdir -p "$BUILD_DIR"

# Скачать исходники через curl (git не нужен)
if [ -f "$BUILD_DIR/package.json" ]; then
    inf "Исходники уже есть — пропускаем загрузку"
else
    inf "Скачиваем telegram-tt с GitHub..."
    curl -fsSL --retry 3 \
        "https://github.com/Ajaxy/telegram-tt/archive/refs/heads/master.tar.gz" \
        | tar xz -C "$BUILD_DIR" --strip-components=1
    ok "Исходники загружены"
fi

cd "$BUILD_DIR"

# telegram-tt webpack config calls git-revision-webpack-plugin — needs a git repo.
# Sources were downloaded as a tarball (no .git), so create a throwaway repo.
if [ ! -d .git ]; then
    inf "Инициализируем git-репозиторий (нужен webpack-плагину)..."
    git init -q
    git -c user.email=build@local -c user.name=build commit -q --allow-empty -m build
fi

# telegram-tt reads API credentials from .env (vars TELEGRAM_API_ID / TELEGRAM_API_HASH)
cat > .env <<EOF
TELEGRAM_API_ID=${API_ID}
TELEGRAM_API_HASH=${API_HASH}
EOF

unset NODE_OPTIONS
inf "npm install (установка зависимостей)..."
npm install

inf "npm run build (компиляция)..."
# Find the production build script — telegram-tt versions differ in naming
BUILD_SCRIPT=$(node -e "
  const s = require('./package.json').scripts || {};
  const candidates = ['build', 'build:production', 'build:prod', 'build:staging'];
  const found = candidates.find(k => k in s);
  if (!found) { console.error('Available scripts: ' + Object.keys(s).join(', ')); process.exit(1); }
  process.stdout.write(found);
") || err "Скрипт сборки не найден в package.json"
inf "Используем скрипт: $BUILD_SCRIPT"
TELEGRAM_API_ID="$API_ID" \
TELEGRAM_API_HASH="$API_HASH" \
APP_ENV=production \
    npm run "$BUILD_SCRIPT"

ok "Сборка завершена"

# Скопировать dist в директорию установки
inf "Копируем dist/ в $INSTALL_DIR/..."
rm -rf "$INSTALL_DIR/dist"
cp -r "$BUILD_DIR/dist" "$INSTALL_DIR/dist"
ok "dist/ скопирован"

# ── 8. Docker-образ ──────────────────────────────────────────────────────────
hdr "Docker-образ"
inf "Собираем nginx-образ (только копирование файлов, интернет не нужен)..."
docker build -t telegram-web-a:local "$INSTALL_DIR"
ok "Образ собран: telegram-web-a:local"

# ── 9. Запуск ────────────────────────────────────────────────────────────────
hdr "Запуск"
cd "$INSTALL_DIR"
$COMPOSE up -d
ok "Контейнер запущен"

echo
echo -e "${GRN}===========================================${NC}"
echo -e "${WHT}  Telegram Web A готов!${NC}"
echo -e "  Браузер: ${CYN}https://${SYNO_IP}:${HOST_PORT}${NC}"
echo -e "${YLW}  ВАЖНО: открывайте именно https:// (не http://)${NC}"
echo -e "${YLW}  Браузер покажет предупреждение о сертификате — нажмите${NC}"
echo -e "${YLW}  'Дополнительно' -> 'Перейти на сайт'. Это самоподписанный${NC}"
echo -e "${YLW}  сертификат, для локальной сети это нормально.${NC}"
echo -e "${GRN}===========================================${NC}"
echo
echo "  Остановить:  cd $INSTALL_DIR && $COMPOSE down"
echo "  Логи:        cd $INSTALL_DIR && $COMPOSE logs -f"
echo "  Обновить:    rm -rf $BUILD_DIR && bash $INSTALL_DIR/setup.sh"
