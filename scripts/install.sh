#!/usr/bin/env sh
set -eu

REPO_URL="${REPO_URL:-https://github.com/eeviriyi/NodeGet-Docker-Compose.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/nodeget-compose}"

# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  else
    echo "sudo"
  fi
}

run_as_root() {
  sudo_cmd="$(need_sudo)"
  if [ -n "$sudo_cmd" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

pause() {
  printf '\n按 Enter 继续...'
  # shellcheck disable=SC2034
  read -r _
}

prompt() {
  label="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  read -r value
  if [ -z "$value" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    date +%s | sha256sum | awk '{print $1}'
  fi
}

base64_one_line() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

# ─────────────────────────────────────────────
# NodeGet 镜像自动探测
#
# 探测顺序（优先级由高到低）：
#   1. GHCR ghcr.io/genshinminecraft/nodeget  ← 当前 CI/CD 实际推送位置
#   2. GHCR ghcr.io/nodeseekdev/nodeget       ← 备用（主仓库）
#   3. Docker Hub genshinmc/nodeget           ← 旧地址，可能停留在旧版本
#
# 对每个源尝试通过 Registry API 解析形如 vX.Y.Z 或 X.Y.Z-<commit> 的版本 tag，
# 取版本号最大的一条作为结果；若解析失败则跳过该源，最终回退到 latest。
# ─────────────────────────────────────────────

# 从 GHCR 获取最新版本 tag（不需要认证的公开镜像）
# 用法: _ghcr_latest_tag <owner> <repo>  → 输出 tag 字符串，失败输出空
_ghcr_latest_tag() {
  owner="$1"
  repo="$2"
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi
  # GHCR 公开镜像需要匿名 token
  token="$(curl -fsSL --max-time 10 \
    "https://ghcr.io/token?scope=repository:${owner}/${repo}:pull" \
    2>/dev/null | sed 's/.*"token":"\([^"]*\)".*/\1/')" || return 0
  [ -z "$token" ] && return 0

  tags_json="$(curl -fsSL --max-time 10 \
    -H "Authorization: Bearer ${token}" \
    "https://ghcr.io/v2/${owner}/${repo}/tags/list" \
    2>/dev/null)" || return 0
  [ -z "$tags_json" ] && return 0

  # 匹配 vX.Y.Z 或 X.Y.Z-<hexcommit> 形式，取版本最大值
  printf '%s' "$tags_json" \
    | tr ',' '\n' \
    | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-f]{6,})?' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
}

# 从 Docker Hub 获取最新版本 tag
# 用法: _dockerhub_latest_tag <namespace> <repo>  → 输出 tag 字符串，失败输出空
_dockerhub_latest_tag() {
  ns="$1"
  repo="$2"
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi
  token="$(curl -fsSL --max-time 10 \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${ns}/${repo}:pull" \
    2>/dev/null | sed 's/.*"token":"\([^"]*\)".*/\1/')" || return 0
  [ -z "$token" ] && return 0

  tags_json="$(curl -fsSL --max-time 10 \
    -H "Authorization: Bearer ${token}" \
    "https://registry-1.docker.io/v2/${ns}/${repo}/tags/list" \
    2>/dev/null)" || return 0
  [ -z "$tags_json" ] && return 0

  printf '%s' "$tags_json" \
    | tr ',' '\n' \
    | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-f]{6,})?' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
}

# 主探测函数：返回完整镜像引用，如 ghcr.io/genshinminecraft/nodeget:v0.3.7
fetch_latest_nodeget_image() {
  echo "  → 尝试 GHCR ghcr.io/genshinminecraft/nodeget ..." >&2
  tag="$(_ghcr_latest_tag genshinminecraft nodeget 2>/dev/null || true)"
  if [ -n "$tag" ]; then
    echo "  ✓ 找到版本：${tag}" >&2
    printf '%s' "ghcr.io/genshinminecraft/nodeget:v${tag}"
    return 0
  fi

  echo "  → 尝试 GHCR ghcr.io/nodeseekdev/nodeget ..." >&2
  tag="$(_ghcr_latest_tag nodeseekdev nodeget 2>/dev/null || true)"
  if [ -n "$tag" ]; then
    echo "  ✓ 找到版本：${tag}" >&2
    printf '%s' "ghcr.io/nodeseekdev/nodeget:v${tag}"
    return 0
  fi

  echo "  → 尝试 Docker Hub genshinmc/nodeget ..." >&2
  tag="$(_dockerhub_latest_tag genshinmc nodeget 2>/dev/null || true)"
  if [ -n "$tag" ]; then
    echo "  ✓ 找到版本：${tag}" >&2
    printf '%s' "genshinmc/nodeget:${tag}"
    return 0
  fi

  echo "  ✗ 所有源均未解析到具体版本 tag，回退到 ghcr.io/genshinminecraft/nodeget:latest" >&2
  printf '%s' "ghcr.io/genshinminecraft/nodeget:latest"
}

# ─────────────────────────────────────────────
# Docker 安装与检测
# ─────────────────────────────────────────────

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "未检测到 Docker Compose。" >&2
    exit 1
  fi
}

compose_up() {
  if [ "${NODEGET_BUILD_FRONTENDS:-0}" = "1" ]; then
    compose_cmd -f docker-compose.yml -f docker-compose.build.yml up -d --build
  else
    compose_cmd up -d
  fi
}

check_command() {
  name="$1"
  hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "未检测到 ${name}。"
    echo "$hint"
    exit 1
  fi
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

install_docker_plugins() {
  if ! command -v apt-get >/dev/null 2>&1; then
    return 0
  fi

  run_as_root apt-get update

  if dpkg -s docker-buildx >/dev/null 2>&1 && ! dpkg -s docker-buildx-plugin >/dev/null 2>&1; then
    echo "检测到 Debian 自带 docker-buildx 旧包，正在移除以安装 Docker 官方 Buildx 插件。"
    run_as_root apt-get remove -y docker-buildx
  fi

  if ! run_as_root apt-get install -y docker-compose-plugin docker-buildx-plugin; then
    echo "Docker 插件安装失败，尝试移除冲突的 docker-buildx 后重试。"
    run_as_root apt-get remove -y docker-buildx || true
    run_as_root apt-get install -y docker-compose-plugin docker-buildx-plugin
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1 &&
    docker compose version >/dev/null 2>&1 &&
    buildx_ok; then
    echo "Docker、Docker Compose 和 Buildx 已安装。"
    return
  fi

  echo "将使用 Docker 官方安装脚本安装/修复 Docker Engine、Compose 插件和 Buildx。"
  echo "官方脚本地址：https://get.docker.com"
  printf '是否继续？输入 y 继续: '
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "已取消 Docker 安装。"
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      run_as_root apt-get update
      run_as_root apt-get install -y ca-certificates curl
    else
      echo "未检测到 curl，请先安装 curl 后重试。"
      return 1
    fi
  fi

  run_as_root sh -c 'curl -fsSL https://get.docker.com | sh'

  install_docker_plugins

  if [ "$(id -u)" -ne 0 ]; then
    run_as_root usermod -aG docker "$(id -un)" || true
    echo "已尝试把当前用户加入 docker 用户组。可能需要重新登录 SSH 后才生效。"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl enable --now docker || true
  fi

  docker --version || true
  docker compose version || true
  docker buildx version || true
}

check_git() {
  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      echo "未检测到 git，正在使用 apt 安装。"
      run_as_root apt-get update
      run_as_root apt-get install -y git ca-certificates curl
    else
      check_command git "请先安装 git，例如：apt install -y git"
    fi
  fi
}

check_docker() {
  check_git

  if ! command -v docker >/dev/null 2>&1; then
    echo "未检测到 Docker。"
    install_docker || {
      echo "请先安装 Docker：https://docs.docker.com/engine/install/"
      exit 1
    }
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker 已安装，但当前用户无法使用。"
    if [ "$(id -u)" -ne 0 ]; then
      echo "请尝试用 sudo 运行本脚本，或重新登录 SSH 后再试。"
      exit 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
      run_as_root systemctl enable --now docker || true
    fi
    if ! docker info >/dev/null 2>&1; then
      echo "Docker 服务仍不可用，请检查：systemctl status docker"
      exit 1
    fi
  fi

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "未检测到 Docker Compose。"
    install_docker || {
      echo "请先安装 Docker Compose 插件。"
      exit 1
    }
  fi

  if ! buildx_ok; then
    echo "未检测到可用的 Docker Buildx 0.17+。"
    install_docker || {
      echo "请先安装 Docker Buildx 0.17+ 插件。"
      exit 1
    }
  fi
}

check_ports() {
  for port in 80 443; do
    if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | grep -q ":$port"; then
      echo "警告：端口 $port 似乎已被占用。Caddy 默认需要 80 和 443。"
    fi
  done
}

check_domain_hint() {
  domain="$1"
  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "$domain" | awk '{print $1}' | sort -u | tr '\n' ' ')"
    if [ -n "$resolved" ]; then
      echo "域名解析结果：${resolved}"
      case "$resolved" in
        *104.16.*|*104.17.*|*104.18.*|*104.19.*|*104.20.*|*104.21.*|*104.22.*|*104.23.*|*104.24.*|*104.25.*|*104.26.*|*104.27.*|*104.28.*|*104.29.*|*104.30.*|*104.31.*|*172.64.*|*172.65.*|*172.66.*|*172.67.*|*172.68.*|*172.69.*|*172.70.*|*172.71.*|*188.114.*|*2606:4700:*)
          echo "警告：域名当前解析到 Cloudflare 代理 IP。"
          echo "首次部署建议在 Cloudflare DNS 中把该记录改为"仅 DNS / 灰云"，并指向本 VPS 公网 IP。"
          echo "否则 Caddy 可能无法申请证书，访问也可能被旧规则跳转到其它站点。"
          ;;
      esac
    else
      echo "警告：当前服务器暂时解析不到 ${domain}。"
      echo "如果 DNS 还没生效，Caddy 可能暂时无法签发 HTTPS 证书。"
    fi
  fi
}

# ─────────────────────────────────────────────
# 仓库与配置管理
# ─────────────────────────────────────────────

ensure_repo() {
  parent="$(dirname "$INSTALL_DIR")"
  run_as_root mkdir -p "$parent"

  if [ -d "$INSTALL_DIR/.git" ]; then
    run_as_root git -C "$INSTALL_DIR" pull --ff-only
  elif [ -e "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR 已存在，但不是 Git 仓库。"
    exit 1
  else
    run_as_root git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  run_as_root chown -R "$(id -u):$(id -g)" "$INSTALL_DIR" 2>/dev/null || true
}

write_env() {
  domain="$1"
  site_name="$2"
  email="$3"
  postgres_password="$4"
  nodeget_image="${5:-ghcr.io/genshinminecraft/nodeget:latest}"

  cat >"$INSTALL_DIR/.env" <<EOF
DOMAIN=${domain}
ACME_EMAIL=${email}

NODEGET_IMAGE=${nodeget_image}
NODEGET_PORT=2211
NODEGET_LOG_FILTER=info
NODEGET_SERVER_UUID=

POSTGRES_DB=nodeget
POSTGRES_USER=nodeget
POSTGRES_PASSWORD=${postgres_password}

BOARD_REPO=https://github.com/NodeSeekDev/NodeGet-board.git
BOARD_REF=main
STATUSSHOW_REPO=https://github.com/NodeSeekDev/NodeGet-StatusShow.git
STATUSSHOW_REF=main
BOARD_IMAGE=ghcr.io/eeviriyi/nodeget-board:main
STATUSSHOW_IMAGE=ghcr.io/eeviriyi/nodeget-statusshow:main
NODEGET_BUILD_FRONTENDS=0

STATUS_SITE_NAME="${site_name}"
STATUS_SITE_LOGO=
STATUS_SITE_FOOTER="Powered by NodeGet"
STATUS_BACKEND_NAME=main
STATUS_BACKEND_URL=wss://${domain}/ws
STATUS_TOKEN=
EOF
}

load_env_value() {
  key="$1"
  file="$INSTALL_DIR/.env"
  if [ ! -f "$file" ]; then
    return 0
  fi
  sed -n "s/^${key}=//p" "$file" | tail -1 | sed 's/^"//;s/"$//'
}

set_env_value() {
  key="$1"
  value="$2"
  file="$INSTALL_DIR/.env"
  tmp="${file}.tmp"
  if grep -q "^${key}=" "$file"; then
    awk -v key="$key" -v value="$value" \
      'BEGIN{done=0} $0 ~ "^" key "=" {print key "=" value; done=1; next} {print} END{if(!done) print key "=" value}' \
      "$file" >"$tmp"
  else
    cp "$file" "$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# ─────────────────────────────────────────────
# Token 管理
# ─────────────────────────────────────────────

get_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    return 0
  fi
  cd "$INSTALL_DIR"
  compose_cmd logs nodeget-server 2>/dev/null | grep 'Super Token:' | tail -1 | sed 's/.*Super Token: //' || true
}

fix_token_sequence() {
  cd "$INSTALL_DIR"
  compose_cmd exec -T postgres psql \
    -U "${POSTGRES_USER:-nodeget}" \
    -d "${POSTGRES_DB:-nodeget}" \
    -c "SELECT setval(pg_get_serial_sequence('token', 'id'), COALESCE((SELECT MAX(id) FROM token), 1));" \
    >/dev/null 2>&1 || true
}

create_probe_token() {
  super_token="$1"
  if [ -z "$super_token" ]; then
    echo "未找到 SuperToken，无法自动创建探针页访问 Token。"
    return 1
  fi

  echo "正在自动创建探针页专用只读 Token..."
  fix_token_sequence

  created_token="$(
    docker run --rm -i \
      --network nodeget-stack_default \
      -e FATHER_TOKEN="$super_token" \
      node:22-alpine node <<'NODE'
const fatherToken = process.env.FATHER_TOKEN
const permissions = [
  { static_monitoring: { read: 'cpu' } },
  { static_monitoring: { read: 'system' } },
  { static_monitoring: { read: 'gpu' } },
  { dynamic_monitoring_summary: 'read' },
  { node_get: 'list_all_agent_uuid' },
  { kv: { read: 'metadata_*' } },
  { task: { read: 'ping' } },
  { task: { read: 'tcp_ping' } },
]

const request = {
  jsonrpc: '2.0',
  id: 'create-probe-token',
  method: 'token_create',
  params: {
    father_token: fatherToken,
    token_creation: {
      username: `nodeget-probe-page-${Date.now()}`,
      password: crypto.randomUUID(),
      version: 1,
      token_limit: [
        {
          scopes: [{ global: null }],
          permissions,
        },
      ],
    },
  },
}

const ws = new WebSocket('ws://nodeget-server:2211/')
const timeout = setTimeout(() => {
  console.error('连接 NodeGet Server 超时')
  process.exit(1)
}, 15000)

ws.addEventListener('open', () => ws.send(JSON.stringify(request)))
ws.addEventListener('message', event => {
  clearTimeout(timeout)
  const response = JSON.parse(String(event.data))
  if (response.error) {
    console.error(response.error.message || JSON.stringify(response.error))
    process.exit(1)
  }
  if (!response.result?.key || !response.result?.secret) {
    console.error('token_create 没有返回 key/secret')
    process.exit(1)
  }
  console.log(`${response.result.key}:${response.result.secret}`)
  ws.close()
})
ws.addEventListener('error', () => {
  clearTimeout(timeout)
  console.error('连接 NodeGet Server 失败')
  process.exit(1)
})
NODE
  )"

  if [ -z "$created_token" ]; then
    echo "探针页访问 Token 创建失败。"
    return 1
  fi

  set_env_value STATUS_TOKEN "$created_token"
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd restart nodeget-statusshow
  echo "探针页专用只读 Token 已自动创建并写入配置。"
}

configure_status_token() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。请先运行安装。"
    return
  fi

  token="$(get_super_token)"
  if [ -z "$token" ]; then
    echo "未能从 nodeget-server 日志中读取 SuperToken，无法自动生成。"
    echo "请确认服务已启动，或用菜单 9 查看 nodeget-server 日志。"
    return
  fi

  create_probe_token "$token"
}

# ─────────────────────────────────────────────
# 启动后提示
# ─────────────────────────────────────────────

show_next_steps() {
  domain="$1"
  echo
  echo "NodeGet Docker Compose 已开始启动。"
  echo
  echo "访问地址："
  echo "  探针页：    https://${domain}/"
  echo "  控制台：    https://${domain}/board/"
  echo "  WebSocket： wss://${domain}/ws"
  echo
  echo "DNS 要求："
  echo "  请确认 ${domain} 已解析到本服务器，并且 80/443 端口已开放。"
  echo
  echo "SuperToken:"
  token="$(get_super_token)"
  if [ -n "$token" ]; then
    echo "  ${token}"
    fill_json="{\"name\":\"${domain}\",\"url\":\"wss://${domain}/ws\",\"token\":\"${token}\"}"
    fill="$(printf '%s' "$fill_json" | base64_one_line)"
    echo
    echo "快速添加控制台后端："
    echo "  https://${domain}/board/#/dashboard/node-manage?tab=servers&fill=${fill}"
  else
    echo "  暂时还没出现在日志里。等 nodeget-server 启动完成后，可运行菜单 8 查看。"
  fi
  echo
  echo "脚本会自动创建探针页专用只读 Token 并写入探针页配置。"
  echo "如果探针页暂时不能读取数据，可稍后再次运行本脚本，选择菜单 3 重新生成。"
}

# ─────────────────────────────────────────────
# 安装 / 更新 / 管理
# ─────────────────────────────────────────────

install_stack() {
  check_docker
  check_ports

  existing_env=0
  if [ -f "$INSTALL_DIR/.env" ]; then
    existing_env=1
    echo "检测到已有部署配置：$INSTALL_DIR/.env"
    echo "默认会复用现有配置，避免覆盖 Postgres 密码和探针页 Token。"
    printf '如需重写配置请输入 REWRITE，直接按 Enter 继续复用: '
    read -r rewrite_confirm
    if [ "$rewrite_confirm" = "REWRITE" ]; then
      existing_env=0
    fi
  fi

  default_domain="${DOMAIN:-nodeget.example.com}"
  if [ "$existing_env" -eq 1 ]; then
    existing_domain="$(load_env_value DOMAIN)"
    default_domain="${existing_domain:-$default_domain}"
  fi
  domain="$(prompt '请输入域名' "$default_domain")"

  if [ "$existing_env" -eq 1 ]; then
    existing_site_name="$(load_env_value STATUS_SITE_NAME)"
    existing_email="$(load_env_value ACME_EMAIL)"
    site_name="$(prompt '请输入探针页名称' "${existing_site_name:-NodeGet Status}")"
    email="$(prompt '请输入 ACME 邮箱' "${existing_email:-admin@${domain}}")"
    set_env_value DOMAIN "$domain"
    set_env_value ACME_EMAIL "$email"
    set_env_value STATUS_SITE_NAME "\"$site_name\""
    set_env_value STATUS_BACKEND_URL "wss://${domain}/ws"
    check_domain_hint "$domain"
    ensure_repo
  else
    site_name="$(prompt '请输入探针页名称' 'NodeGet Status')"
    email="$(prompt '请输入 ACME 邮箱' "admin@${domain}")"
    default_password="$(generate_password)"
    postgres_password="$(prompt '请输入 Postgres 密码' "$default_password")"

    check_domain_hint "$domain"
    ensure_repo

    echo
    echo "正在查询 NodeGet Server 最新版本镜像..."
    nodeget_image="$(fetch_latest_nodeget_image)"
    echo "将使用镜像：${nodeget_image}"
    echo

    write_env "$domain" "$site_name" "$email" "$postgres_password" "$nodeget_image"
  fi

  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_up

  echo "正在等待 nodeget-server 输出日志..."
  i=0
  while [ "$i" -lt 30 ]; do
    if compose_cmd logs nodeget-server 2>/dev/null | grep -q 'Super Token:'; then
      break
    fi
    i=$((i + 1))
    sleep 2
  done

  status_token="$(load_env_value STATUS_TOKEN)"
  if [ -z "$status_token" ]; then
    token="$(get_super_token)"
    if [ -n "$token" ]; then
      create_probe_token "$token" || true
    fi
  else
    echo "检测到已有探针页 Token，跳过自动生成。如需更新请选择菜单 3。"
  fi

  show_next_steps "$domain"
}

update_stack() {
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。请先运行安装。"
    return
  fi
  cd "$INSTALL_DIR"
  git pull --ff-only

  echo
  echo "正在查询 NodeGet Server 最新版本镜像..."
  nodeget_image="$(fetch_latest_nodeget_image)"
  current_image="$(load_env_value NODEGET_IMAGE)"

  if [ -n "$nodeget_image" ] && [ "$nodeget_image" != "$(echo "$nodeget_image" | grep 'latest$')" ]; then
    if [ "$current_image" != "$nodeget_image" ]; then
      echo "发现新版本镜像：${nodeget_image}"
      echo "当前配置镜像：${current_image}"
      set_env_value NODEGET_IMAGE "$nodeget_image"
      echo "已更新 .env 中的 NODEGET_IMAGE。"
    else
      echo "当前已是最新镜像：${nodeget_image}"
    fi
  else
    echo "警告：未能解析到具体版本 tag，保持现有镜像配置：${current_image}"
  fi
  echo

  ./scripts/render-status-config.sh
  compose_cmd pull
  compose_up
}

restart_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_up
}

show_status() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  compose_cmd ps
}

doctor_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  ./scripts/doctor.sh
}

show_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  token="$(get_super_token)"
  if [ -n "$token" ]; then
    echo "Super Token: ${token}"
  fi
}

show_logs() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  echo "1. nodeget-server"
  echo "2. caddy"
  echo "3. postgres"
  echo "4. nodeget-statusshow"
  echo "5. nodeget-board"
  printf '请选择服务: '
  read -r choice
  case "$choice" in
    1) service=nodeget-server ;;
    2) service=caddy ;;
    3) service=postgres ;;
    4) service=nodeget-statusshow ;;
    5) service=nodeget-board ;;
    *) echo "无效选择"; return ;;
  esac
  cd "$INSTALL_DIR"
  compose_cmd logs -f "$service"
}

uninstall_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  echo "此操作会停止并删除 NodeGet 容器。"
  printf '是否同时删除数据卷？输入 DELETE 删除数据，直接按 Enter 则保留数据: '
  read -r confirm
  cd "$INSTALL_DIR"
  if [ "$confirm" = "DELETE" ]; then
    compose_cmd down -v
    echo "容器和数据卷已删除。"
  else
    compose_cmd down
    echo "容器已删除，数据卷已保留。"
  fi
}

# ─────────────────────────────────────────────
# 菜单
# ─────────────────────────────────────────────

menu() {
  while true; do
    echo
    echo "NodeGet Docker Compose 管理菜单"
    echo
    echo "1. 安装 / 首次部署"
    echo "2. 安装 / 修复 Docker"
    echo "3. 自动生成/更新探针页访问 Token"
    echo "4. 更新部署（自动拉取最新镜像）"
    echo "5. 重新生成配置并重启"
    echo "6. 查看状态"
    echo "7. 部署自检"
    echo "8. 查看 SuperToken"
    echo "9. 查看日志"
    echo "10. 卸载"
    echo "0. 退出"
    echo
    printf '请选择: '
    read -r choice
    case "$choice" in
      1) install_stack; pause ;;
      2) install_docker; pause ;;
      3) configure_status_token; pause ;;
      4) update_stack; pause ;;
      5) restart_stack; pause ;;
      6) show_status; pause ;;
      7) doctor_stack; pause ;;
      8) show_super_token; pause ;;
      9) show_logs ;;
      10) uninstall_stack; pause ;;
      0) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

menu
