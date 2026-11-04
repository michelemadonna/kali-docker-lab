#!/bin/sh
set -eu
: "${POSTGRES_HOST:=postgres}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_DB:=lab}"
: "${POSTGRES_USER:=lab}"
exec pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -U "$POSTGRES_USER"
