#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example. Edit it before running again."
  exit 1
fi

./scripts/render-status-config.sh
docker compose up -d --build
