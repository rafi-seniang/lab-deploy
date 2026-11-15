#!/usr/bin/env bash
# Brings the host to the versions in refs.env: fetch the sources, build, migrate, start, check.
# Run on the server from this directory: ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "No .env here. Copy .env.example and fill it in." >&2; exit 1; }
# shellcheck disable=SC1091
. ./refs.env

fetch() { # repository, ref
  local directory="src/$1"
  [ -d "$directory/.git" ] || git clone --quiet "https://github.com/rafi-seniang/$1.git" "$directory"
  git -C "$directory" fetch --quiet origin
  git -C "$directory" checkout --quiet --detach "$2"
  echo "$1 at $(git -C "$directory" log --oneline -1)"
}

echo "== sources"
mkdir -p src
fetch tiketa-app "$TIKETA_APP_REF"
fetch tiketa-booking-agent "$TIKETA_AGENT_REF"
fetch ai-engineering-lab "$LAB_WEB_REF"
fetch dispatch-system1-router "$DISPATCH_REF"
fetch lens-multimodal-search "$LENS_REF"

[ -f data/lens/index.json ] && [ -f data/lens/vectors.npy ] || {
  echo "Missing ./data/lens (index.json and vectors.npy). Sync assets/lens to ./data/lens first." >&2
  exit 1
}

echo "== build"
docker compose build --quiet

echo "== databases"
docker compose up -d --wait postgres redis
docker compose run --rm --no-deps tiketa-api alembic upgrade head
# Safe to run again: adds only the showtimes of this week that are missing
docker compose run --rm --no-deps tiketa-api python scripts/publish_week.py

echo "== services"
docker compose up -d --wait tiketa-api
docker compose run --rm --no-deps tiketa-agent alembic upgrade head
docker compose up -d --wait --remove-orphans

echo "== checks, through the edge as a visitor's request arrives"
check() { # path, text the answer must contain
  docker compose exec -T edge wget -q -O - "http://127.0.0.1$1" | grep -q "$2" || { echo "FAILED $1" >&2; exit 1; }
  echo "ok $1"
}
check /healthz ok
check /dispatch/api/health ok
check /lens/api/health ok
check /lens/api/v1/collection 'gemini-embedding-2'
check /tiketa/healthz ok
check /tiketa/api/health ok
check /tiketa/api/meta '"mcp_path":"/mcp"'
check /tiketa/agent/health ok

docker image prune -f >/dev/null
echo "== done"
