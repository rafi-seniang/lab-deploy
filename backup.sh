#!/usr/bin/env bash
# Dumps every database to backups/ and keeps the newest seven. They stay on this host: copy them off it to be safe.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
docker compose exec -T postgres pg_dumpall -U lab | gzip > "backups/$(date +%F).sql.gz"
ls -1t backups/*.sql.gz | tail -n +8 | xargs -r rm --
