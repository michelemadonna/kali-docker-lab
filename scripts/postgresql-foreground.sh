#!/usr/bin/env bash
set -Eeuo pipefail

pg_version="$(cat /etc/kali-postgresql-version)"
exec "/usr/lib/postgresql/$pg_version/bin/postgres" \
  -D /var/lib/postgresql/data
