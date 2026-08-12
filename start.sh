#!/usr/bin/env bash
# restart：先停止已运行的 market_server，再编译构建并重新启动
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/logs"
BIN="$ROOT/market_server/market_server"
ADMIN_DIST="$ROOT/market_admin/dist"
WWW_ROOT="/var/www/datakeep"
SERVER_PID_FILE="$LOG_DIR/market_server.pid"
SERVER_PORT=8088

mkdir -p "$LOG_DIR"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

need go
need npm
need nginx

# ---------- 停止旧进程（restart 核心）----------
stop_market_server() {
  echo "==> 停止旧 market_server"

  local stopped=0

  # 1) 按 pid 文件停止
  if [[ -f "$SERVER_PID_FILE" ]]; then
    local old_pid
    old_pid="$(tr -d '[:space:]' <"$SERVER_PID_FILE" || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo "    kill pid=$old_pid (pid 文件)"
      kill "$old_pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$old_pid" 2>/dev/null || break
        sleep 0.4
      done
      if kill -0 "$old_pid" 2>/dev/null; then
        echo "    强制结束 pid=$old_pid"
        kill -9 "$old_pid" 2>/dev/null || true
      fi
      stopped=1
    fi
    rm -f "$SERVER_PID_FILE"
  fi

  # 2) 按二进制路径兜底
  if pgrep -f "$BIN" >/dev/null 2>&1; then
    echo "    pkill 残留进程: $BIN"
    pkill -f "$BIN" 2>/dev/null || true
    sleep 0.5
    pkill -9 -f "$BIN" 2>/dev/null || true
    stopped=1
  fi

  # 3) 占用 8088 的残留进程
  if command -v fuser >/dev/null 2>&1; then
    local pids
    pids="$(fuser "${SERVER_PORT}/tcp" 2>/dev/null || true)"
    if [[ -n "${pids// /}" ]]; then
      echo "    释放端口 :${SERVER_PORT} ->$pids"
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 0.5
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
      stopped=1
    fi
  elif command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -t -iTCP:"$SERVER_PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      echo "    释放端口 :${SERVER_PORT} -> $pids"
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 0.5
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
      stopped=1
    fi
  fi

  if [[ "$stopped" -eq 0 ]]; then
    echo "    无旧进程"
  else
    echo "    已停止"
  fi
}

stop_market_server

# ---------- market_server 环境 ----------
if [[ ! -f "$ROOT/market_server/.env" ]]; then
  if [[ -f "$ROOT/market_server/.env.example" ]]; then
    cp "$ROOT/market_server/.env.example" "$ROOT/market_server/.env"
    echo "已从 .env.example 生成 market_server/.env，请按需修改密码与密钥后再用。"
  else
    echo "缺少 market_server/.env" >&2
    exit 1
  fi
fi

# ---------- 编译 market_server ----------
# Lightsail 小内存机：限制并行，避免 OOM（compile: signal: killed）
echo "==> 编译 market_server"
(
  cd "$ROOT/market_server"
  GOMAXPROCS=1 go build -p 1 -o market_server .
)

# ---------- 构建 market_admin ----------
echo "==> 构建 market_admin"
(
  cd "$ROOT/market_admin"
  if [[ ! -d node_modules ]]; then
    npm install
  fi
  npm run build
)

# ---------- 启动 market_server ----------
echo "==> 启动 market_server"
(
  cd "$ROOT/market_server"
  nohup ./market_server >>"$LOG_DIR/market_server.log" 2>&1 &
  echo $! >"$SERVER_PID_FILE"
)
echo "    pid=$(cat "$SERVER_PID_FILE")  log=$LOG_DIR/market_server.log"

# 健康检查
ready=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf "http://127.0.0.1:${SERVER_PORT}/health" >/dev/null 2>&1 \
    || curl -sf "http://127.0.0.1:${SERVER_PORT}/api/apps" >/dev/null 2>&1; then
    echo "    market_server 已就绪"
    ready=1
    break
  fi
  sleep 0.5
done
if [[ "$ready" -eq 0 ]]; then
  echo "警告: market_server 健康检查未通过，请看 logs/market_server.log" >&2
fi

# ---------- 部署静态站到 /var/www（nginx 读不到 /home/ubuntu）----------
echo "==> 部署 market_admin 到 $WWW_ROOT"
sudo mkdir -p "$WWW_ROOT"
sudo rsync -a --delete "$ADMIN_DIST"/ "$WWW_ROOT"/
sudo chown -R www-data:www-data "$WWW_ROOT"

# ---------- Nginx：托管静态站 + 反代 API ----------
NGINX_CONF=/etc/nginx/sites-available/datakeep.site
if [[ -w "$NGINX_CONF" ]] || sudo -n true 2>/dev/null; then
  echo "==> 更新 Nginx 站点配置"
  sudo tee "$NGINX_CONF" >/dev/null <<EOF
# datakeep.site — market_admin 静态站 + market_server 反代
server {
    listen 80;
    listen [::]:80;
    server_name datakeep.site www.datakeep.site;
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name datakeep.site www.datakeep.site;

    ssl_certificate     /etc/nginx/ssl/datakeep/datakeep.pem;
    ssl_certificate_key /etc/nginx/ssl/datakeep/datakeep.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    root $WWW_ROOT;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:${SERVER_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /admin/ {
        proxy_pass http://127.0.0.1:${SERVER_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:${SERVER_PORT};
        proxy_set_header Host \$host;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  sudo ln -sfn "$NGINX_CONF" /etc/nginx/sites-enabled/datakeep.site
  sudo nginx -t
  sudo systemctl reload nginx
  mkdir -p "$ROOT/deploy"
  sudo cp "$NGINX_CONF" "$ROOT/deploy/nginx-datakeep.site.conf"
  sudo chown "$USER:$USER" "$ROOT/deploy/nginx-datakeep.site.conf" 2>/dev/null || true
  echo "    Nginx 已 reload，站点根目录: $WWW_ROOT"
else
  echo "跳过 Nginx 更新（无 sudo）。请手动将 root 指到 $WWW_ROOT 并反代 :${SERVER_PORT}"
fi

echo
echo "restart 完成。"
echo "  管理后台: https://datakeep.site/"
echo "  API:      https://datakeep.site/api/apps"
echo "  日志:     $LOG_DIR/market_server.log"
echo "  再次执行 ./start.sh 即会先停再启"
