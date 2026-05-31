#!/usr/bin/env sh
set -eu

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

domain="${DOMAIN:-}"

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    return 1
  fi
}

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
}

buildx_ok() {
  if ! docker buildx version >/dev/null 2>&1; then
    return 1
  fi
  version="$(docker buildx version | awk '{print $2}' | sed 's/^v//')"
  major="$(printf '%s' "$version" | cut -d. -f1)"
  minor="$(printf '%s' "$version" | cut -d. -f2)"
  case "$major:$minor" in
    ''|*[!0-9:]*|*:|'':*) return 1 ;;
  esac
  if [ "$major" -gt 0 ]; then
    return 0
  fi
  [ "$minor" -ge 17 ]
}

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "已安装 $1"
  else
    fail "未安装 $1"
  fi
}

check_command docker
if compose_cmd version >/dev/null 2>&1; then
  ok "Docker Compose 可用"
else
  fail "Docker Compose 不可用"
fi

if buildx_ok; then
  ok "Docker Buildx 可用：$(docker buildx version)"
else
  fail "Docker Buildx 不可用或版本低于 0.17，构建 board/statusshow 镜像会失败"
fi

if docker info >/dev/null 2>&1; then
  ok "当前用户可以访问 Docker"
else
  fail "当前用户无法访问 Docker，请用 sudo 运行或加入 docker 用户组"
fi

if [ -z "$domain" ]; then
  warn ".env 里没有 DOMAIN，无法检查域名"
else
  ok "DOMAIN=${domain}"
  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "$domain" | awk '{print $1}' | sort -u | tr '\n' ' ')"
    if [ -n "$resolved" ]; then
      ok "域名解析结果：${resolved}"
      case "$resolved" in
        *104.16.*|*104.17.*|*104.18.*|*104.19.*|*104.20.*|*104.21.*|*104.22.*|*104.23.*|*104.24.*|*104.25.*|*104.26.*|*104.27.*|*104.28.*|*104.29.*|*104.30.*|*104.31.*|*172.64.*|*172.65.*|*172.66.*|*172.67.*|*172.68.*|*172.69.*|*172.70.*|*172.71.*|*188.114.*|*2606:4700:*)
          warn "域名当前解析到 Cloudflare 代理 IP。首次部署建议改为"仅 DNS / 灰云"，并指向本 VPS 公网 IP。"
          warn "橙云代理或旧跳转规则会导致 Caddy ACME 证书申请失败，或访问被转到其它站点。"
          ;;
      esac
    else
      fail "域名暂时没有解析结果"
    fi
  else
    warn "系统没有 getent，跳过 DNS 检查"
  fi
fi

for port in 80 443; do
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn "( sport = :$port )" | grep -q ":$port"; then
      ok "端口 $port 正在监听"
    else
      warn "端口 $port 当前没有监听，Caddy 未启动或启动失败"
    fi
  fi
done

# 显示当前使用的 NodeGet 镜像版本
nodeget_image="${NODEGET_IMAGE:-（未设置）}"
ok "NODEGET_IMAGE=${nodeget_image}"

if [ -f docker-compose.yml ]; then
  echo
  compose_cmd ps || true
else
  warn "当前目录没有 docker-compose.yml"
fi

if [ -n "$domain" ]; then
  echo
  echo "访问地址："
  echo "  探针页： https://${domain}/"
  echo "  控制台： https://${domain}/board/"
  echo "  WS：     wss://${domain}/ws"
fi
