#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo "postgresql-prepare: $*" >&2; exit 1; }

pg_version="$(cat /etc/kali-postgresql-version)"
[[ "$pg_version" =~ ^[0-9]+$ ]] || fail "invalid PostgreSQL version: $pg_version"

data_dir=/var/lib/postgresql/data
config_file="$data_dir/postgresql.conf"
hba_file="$data_dir/pg_hba.conf"
pg_ctl="/usr/lib/postgresql/$pg_version/bin/pg_ctl"
initdb="/usr/lib/postgresql/$pg_version/bin/initdb"
socket_dir=/var/run/postgresql

[[ -x "$pg_ctl" ]] || fail "PostgreSQL $pg_version server binary is missing"
[[ -x "$initdb" ]] || fail "PostgreSQL $pg_version initdb binary is missing"
[[ -r /run/secrets/postgres_password ]] || fail "postgres_password secret is missing or unreadable"

if [[ -s "$data_dir/PG_VERSION" ]]; then
  actual_version="$(cat "$data_dir/PG_VERSION")"
  [[ "$actual_version" == "$pg_version" ]] \
    || fail "data volume is PostgreSQL $actual_version; expected $pg_version (leaving it untouched)"
else
  install -d -o postgres -g postgres -m 0700 "$data_dir"
  runuser -u postgres -- "$initdb" -D "$data_dir" \
    --auth-local=peer --auth-host=scram-sha-256 --encoding=UTF8 --no-instructions
fi

# Package install order can change the postgres UID between desktop profiles.
# Realign the persisted cluster ownership to this image after confirming version.
chown -R postgres:postgres "$data_dir"
chmod 0700 "$data_dir"

[[ -s "$config_file" ]] || fail "PostgreSQL cluster configuration was not created"

# Keep PostgreSQL on a Unix socket so it cannot listen on the shared host network.
sed -i '/^# BEGIN kali-lab settings$/,/^# END kali-lab settings$/d' "$config_file"
cat >> "$config_file" <<'EOF'

# BEGIN kali-lab settings
listen_addresses = ''
unix_socket_directories = '/var/run/postgresql'
port = 5432
# END kali-lab settings
EOF
cat > "$hba_file" <<'EOF'
local   all     postgres                    peer
local   msf     msf                         scram-sha-256
local   all     all                         reject
EOF

install -d -o postgres -g postgres -m 2775 "$socket_dir"
db_password="$(cat /run/secrets/postgres_password)"
[[ -n "$db_password" ]] || fail "postgres_password secret is empty"

pg_port=5432

pg_started=false
stop_temporary_postgres() {
  if [[ "$pg_started" == true ]]; then
    runuser -u postgres -- "$pg_ctl" -D "$data_dir" -m fast -w stop >/dev/null
    pg_started=false
  fi
}
trap stop_temporary_postgres EXIT

runuser -u postgres -- "$pg_ctl" -D "$data_dir" \
  -l "$data_dir/prepare.log" -w start >/dev/null
pg_started=true

psql_postgres() {
  runuser -u postgres -- psql --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

if ! psql_postgres --dbname=postgres --tuples-only --no-align \
    --command="SELECT 1 FROM pg_roles WHERE rolname = 'msf'" | grep -qx 1; then
  psql_postgres --dbname=postgres --command='CREATE ROLE msf LOGIN'
fi
psql_postgres --dbname=postgres --set=msf_password="$db_password" <<'SQL'
ALTER ROLE msf WITH LOGIN PASSWORD :'msf_password';
SQL

for db_name in msf msf_test; do
  if ! psql_postgres --dbname=postgres --tuples-only --no-align \
      --command="SELECT 1 FROM pg_database WHERE datname = '$db_name'" | grep -qx 1; then
    runuser -u postgres -- createdb --template=template0 --encoding=UTF-8 \
      --owner=msf "$db_name"
  fi
done

MSF_DB_PASSWORD="$db_password" MSF_DB_PORT="$pg_port" ruby -ryaml -e '
  base = {
    "adapter" => "postgresql",
    "username" => "msf",
    "password" => ENV.fetch("MSF_DB_PASSWORD"),
    "host" => "/var/run/postgresql",
    "port" => Integer(ENV.fetch("MSF_DB_PORT")),
    "pool" => 5,
    "timeout" => 5
  }
  config = {
    "development" => base.merge("database" => "msf"),
    "production" => base.merge("database" => "msf"),
    "test" => base.merge("database" => "msf_test")
  }
  path = "/usr/share/metasploit-framework/config/database.yml"
  File.write(path, YAML.dump(config))
  File.chmod(0644, path)
'

if [[ ! -e "$data_dir/.metasploit-schema-ready" ]]; then
  (cd /usr/share/metasploit-framework && bundle exec rake db:migrate)
  install -o postgres -g postgres -m 0600 /dev/null "$data_dir/.metasploit-schema-ready"
fi

unset db_password
stop_temporary_postgres
trap - EXIT
