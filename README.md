# NodeGet Docker Compose

NodeGet 单域名 Docker Compose 部署方案，目标是让个人 VPS 可以用一条脚本启动 Server、Board 和探针页。

路由：

- `/` 提供探针页
- `/board/` 提供 NodeGet-board 控制台
- `/ws` 反代 NodeGet Server WebSocket JSON-RPC

本方案使用 Caddy 自动 HTTPS、Postgres 存储、官方 NodeGet Server 镜像，以及预构建的 Board/StatusShow 镜像。

## 镜像说明

NodeGet Server 镜像由于 NodeSeekDev 组织的 GitHub Actions 权限问题，CI/CD 已迁移至
[GenshinMinecraft/NodeGet](https://github.com/GenshinMinecraft/NodeGet)，
镜像发布在 GHCR：

```
ghcr.io/genshinminecraft/nodeget:<version>
```

`install.sh` 在每次**安装**和**更新**时会自动按以下优先级探测最新版本 tag 并写入 `.env`：

1. `ghcr.io/genshinminecraft/nodeget`（优先，CI/CD 实际推送位置）
2. `ghcr.io/nodeseekdev/nodeget`（备用）
3. `genshinmc/nodeget`（Docker Hub 旧地址，回退）

无需手动指定版本号，保持始终使用最新稳定版。

## 已实测环境

- Debian GNU/Linux 13 trixie
- Docker `29.4.2`
- Docker Compose `v5.1.3`
- Docker Buildx `v0.33.0`
- 单域名 HTTPS：已验证 Caddy 自动签发 Let's Encrypt 证书
- 已验证路径：`/`、`/board/`、`/ws`
- 默认安装不在 VPS 上构建前端镜像，避免低配机器长时间卡在 `Building`
- 预构建前端镜像发布 `linux/amd64` 和 `linux/arm64`

## 环境要求

- 已安装 Docker 和 Docker Compose
- 一个已经解析到本服务器的域名
- 服务器开放入站 `80` 和 `443` 端口

## VPS 快速部署

```bash
bash <(curl -fsSL https://github.com/vlongx/nodeget/main/scripts/install.sh)
```

选择 `1. 安装 / 首次部署`，按提示输入：

- 域名
- 探针页名称
- ACME 邮箱
- Postgres 密码（可直接使用脚本生成的默认值）

安装脚本会：

1. 把本仓库克隆到 `/opt/nodeget-compose`
2. **自动探测 GHCR / Docker Hub 上的最新版本 tag** 并写入 `.env`
3. 启动 Docker Compose
4. 等待 SuperToken 出现后直接输出
5. 自动创建探针页专用只读 Token

如果 VPS 没有 Docker，安装脚本会提示是否使用 Docker 官方脚本一键安装，
也可以在菜单里选择 `2. 安装 / 修复 Docker`。

启动完成后：

1. 打开 `https://你的域名/board/`
2. 使用安装脚本输出的 SuperToken 登录
3. 在控制台里添加后端地址 `wss://你的域名/ws`
4. 打开 `https://你的域名/` 查看探针页

## 手动部署

```bash
git clone https://github.com/eeviriyi/NodeGet-Docker-Compose.git
cd NodeGet-Docker-Compose
cp .env.example .env
# 编辑 .env，至少填写 DOMAIN / ACME_EMAIL / POSTGRES_PASSWORD
# NODEGET_IMAGE 可手动指定，格式见 .env.example 注释
nano .env
./scripts/up.sh
```

## 更新部署

运行菜单选择 `4. 更新部署`，脚本会：

- 自动从 GHCR 探测最新版本 tag
- 若版本有变化，更新 `.env` 中的 `NODEGET_IMAGE`
- 执行 `docker compose pull` + `docker compose up -d`

或手动：

```bash
cd /opt/nodeget-compose
bash scripts/install.sh   # 选择 4
```

## DNS 解析

在 DNS 服务商处添加 `A` 记录：

```
nodeget.example.com → your_server_ipv4
```

IPv6 可额外添加 `AAAA` 记录。

## HTTPS

Caddy 自动申请和续期 Let's Encrypt 证书。域名必须已解析到本服务器，
公网可访问 `80` 和 `443`。

若首次 HTTPS 访问失败，优先检查：

- DNS 是否已解析到 VPS
- VPS 安全组是否放行 `80/443`
- VPS 内是否已有其他服务占用端口
- `docker compose logs -f caddy` 中的 ACME 错误

## 常用命令

```bash
# 查看容器状态
docker compose ps

# 查看各服务日志
docker compose logs -f nodeget-server
docker compose logs -f caddy

# 拉取最新镜像并重启
docker compose pull
docker compose up -d

# 自检
cd /opt/nodeget-compose
./scripts/doctor.sh
```

本地从源码构建前端镜像：

```bash
NODEGET_BUILD_FRONTENDS=1 \
  docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

## 镜像来源

| 服务 | 镜像 |
|------|------|
| NodeGet Server | `ghcr.io/genshinminecraft/nodeget:<version>`（由 install.sh 自动探测） |
| Postgres | `postgres:17-alpine` |
| Caddy | `caddy:2-alpine` |
| Board | `ghcr.io/eeviriyi/nodeget-board:main` |
| StatusShow | `ghcr.io/eeviriyi/nodeget-statusshow:main` |

Board 和 StatusShow 镜像支持 `linux/amd64` 与 `linux/arm64`，
默认从官方 `NodeSeekDev` 源仓库构建。

## 菜单功能说明

| 编号 | 功能 |
|------|------|
| 1 | 安装 / 首次部署（自动探测最新镜像） |
| 2 | 安装 / 修复 Docker |
| 3 | 自动生成/更新探针页访问 Token |
| 4 | 更新部署（自动拉取最新镜像） |
| 5 | 重新生成配置并重启 |
| 6 | 查看容器状态 |
| 7 | 部署自检 |
| 8 | 查看 SuperToken |
| 9 | 查看日志 |
| 10 | 卸载 |
