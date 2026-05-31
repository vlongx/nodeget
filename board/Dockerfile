FROM node:22-alpine AS build

ARG BOARD_REPO=https://github.com/NodeSeekDev/NodeGet-board.git
ARG BOARD_REF=main
ARG BOARD_SOURCE_REV=unknown
ARG BOARD_BASE=/board/
ARG PNPM_VERSION=10.33.0
ENV VITE_BASE=${BOARD_BASE}

RUN apk add --no-cache git
WORKDIR /src
RUN echo "Board source revision: ${BOARD_SOURCE_REV}" \
    && git clone --depth 1 --branch "${BOARD_REF}" "${BOARD_REPO}" . \
    && if [ "${BOARD_SOURCE_REV}" != "unknown" ]; then test "$(git rev-parse HEAD)" = "${BOARD_SOURCE_REV}"; fi

# NodeGet-board does not currently expose a base-path build option. Patch the
# build in this deployment image so it can be served from /board/.
RUN node -e "const fs=require('fs');const p='vite.config.ts';let s=fs.readFileSync(p,'utf8');s=s.replace('export default defineConfig({', 'export default defineConfig({\\n  base: process.env.VITE_BASE || ' + JSON.stringify(process.env.VITE_BASE || '/board/') + ',');fs.writeFileSync(p,s)" \
    && node -e "const fs=require('fs');const p='src/router/index.ts';let s=fs.readFileSync(p,'utf8');s=s.replace('history: createWebHashHistory(),', 'history: createWebHashHistory(import.meta.env.BASE_URL),');fs.writeFileSync(p,s)"

RUN corepack enable && corepack prepare "pnpm@${PNPM_VERSION}" --activate
RUN pnpm install --frozen-lockfile
RUN pnpm build

FROM nginx:1.27-alpine
COPY --from=build /src/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

