#!/usr/bin/env bash
set -euo pipefail
install -m 644 "$(dirname "$0")/../cron/lab" /etc/cron.d/lab
