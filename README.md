# Kali Docker Lab

A Docker Compose lab based on the official `kalilinux/kali-rolling` image. It combines an optional Openbox or XFCE desktop over XRDP, root SSH public-key authentication, Kali's official MCP API/stdio bridge, a focused set of assessment tools, and a separate persistent PostgreSQL service.

> Use these tools only against systems you own or are explicitly authorized to assess. Keep this lab on trusted networks. The Kali MCP API can run commands as the `kali` account and has no independent authentication layer; this project binds it to container loopback and does not publish its port.

## Included services and tools

- **Desktop:** Openbox by default, or XFCE (`DESKTOP=kali-xfce`), exposed by XRDP.
- **Browser:** Firefox ESR is installed with either desktop option.
- **SSH:** root login with public key only. The authorized public key file is mounted at runtime. No private key is included or needed in this project.
- **Supervisor:** runs `sshd`, XRDP services, and Kali's MCP API without systemd.
- **MCP:** Kali's official `mcp-kali-server` package supplies `kali-server-mcp` (API) and `mcp-server` (stdio bridge). Supervisor runs the API bound to `127.0.0.1` inside the container. An MCP client starts the stdio bridge with `docker exec`; the bridge is not a network daemon.
- **PostgreSQL:** separate official PostgreSQL container, health-checked and persisted in a named volume. `postgres/init/` scripts run only on first initialization of an empty data volume.
- **Tooling:** network/recon, web testing, Active Directory, exploitation, OSINT, and Bettercap/wireless command-line packages. Wireless monitor/injection requires compatible host hardware and host networking/capabilities; those privileges are intentionally not enabled in the default Compose file.
- **Optional Maltego:** set `INSTALL_MALTEGO=true` at image build time. It is a GUI application and may require account activation, licensing, and additional setup. Kali rolling package availability can change.

## Requirements

- Docker Engine with the Compose plugin, or Docker Desktop / OrbStack.
- A machine with enough memory and disk for a Kali desktop and the selected tooling. XFCE and the full tool set make the image large.
- A public SSH key. Generate a key locally if needed; keep the private half outside this project.

## Quick start

From this directory:

1. Create `.env` from `.env.example` and adjust ports or desktop choice.
2. Create local secret files as described in [`secrets/README.md`](secrets/README.md). At minimum, supply an SSH **public** key in `secrets/authorized_keys`, a non-empty desktop password in `secrets/kali_password`, and a PostgreSQL password in `secrets/postgres_password`.
3. Build and start the lab:

   ```sh
   docker compose up --build -d
   ```

4. Check service status and logs:

   ```sh
   docker compose ps
   docker compose logs -f kali postgres
   ```

5. Connect over SSH (replace the key path with your private key path):

   ```sh
   ssh -i ~/.ssh/YOUR_PRIVATE_KEY -p 50022 root@127.0.0.1
   ```

   Password and keyboard-interactive SSH authentication are disabled. Root is allowed only through public-key authentication. The private key stays on the host.

6. Connect an RDP client to `127.0.0.1:53389`, user `kali`, using the locally supplied desktop password. The RDP service is intended for local/trusted access.

### Choose XFCE or Maltego

Set `DESKTOP=kali-xfce` or `INSTALL_MALTEGO=true` in `.env`, then rebuild:

```sh
docker compose build --no-cache kali
docker compose up -d --force-recreate kali
```

### Configure timezone and locale

Set `TZ` to an IANA timezone and `LANG` to a UTF-8 locale in `.env`; for example:

```dotenv
TZ=Europe/Rome
LANG=it_IT.UTF-8
```

The container applies these values at startup, generates the selected locale if needed, and sets the system timezone. Recreate the Kali service after changing them:

```sh
docker compose up -d --force-recreate kali
```

## MCP client connection

The included [`MCP_CLIENT_CONFIG.example.json`](MCP_CLIENT_CONFIG.example.json) shows the stdio connection command. Adapt its `mcpServers` entry to your MCP client's configuration format. The important command is:

```sh
docker exec -i kali-lab mcp-server --server http://127.0.0.1:5000
```

The Kali API listens only on the container's loopback interface. Do not publish port 5000 or bind it to `0.0.0.0`; the API has no separate authentication and exposes command execution. Confirm your MCP client supports local stdio servers and that its process can invoke Docker. The sample is generic JSON, not a client-specific import file.

## PostgreSQL

The database is available to containers on the Compose network at `postgres:5432`. Credentials are supplied using mounted secret files, not hard-coded in the image or `.env`. The Kali container can read the PostgreSQL password from `/run/secrets/postgres_password`; use `psql -W` to enter it interactively. The initialized database uses `POSTGRES_DB` and `POSTGRES_USER`; the sample init SQL creates a small `lab.notes` table.

Initialization scripts are only applied when the `postgres_data` volume is empty. To re-run initialization, remove that volume, which permanently deletes its database contents:

```sh
docker compose down
# Destructive: removes the persistent PostgreSQL data volume.
docker volume rm kali-lab_postgres_data
```

Back up data before removing a volume. Do not use this command if you want to preserve lab data.

## Secrets and SSH host keys

The ZIP contains no passwords, private SSH keys, generated host keys, or populated secret files. Compose requires the three local secret files to exist before startup. Keep them out of Git and image builds. The container creates SSH host keys on first start in the persistent `ssh_host_keys` volume, so server identity survives container recreation.

If the client reports a changed SSH host key after you intentionally remove/recreate that volume, remove only the old `kali-lab` host entry from your host's `known_hosts` after verifying the change.

## Networking notes

- Only SSH and XRDP ports are published by default; they use localhost host ports `50022` and `53389`.
- The Kali MCP API is loopback-only within the Kali container. PostgreSQL has no published host port and is reachable only on the private Compose network.
- A normal bridge network does not provide host Wi-Fi monitor mode or raw radio access. Bettercap's wireless features need suitable hardware plus deliberate host-specific Docker privileges. Do not add `privileged: true` casually; it grants broad host-device access.
- Docker Desktop and OrbStack run Linux containers in a VM, so low-level wireless features generally require a separate Linux host or VM setup.

## Useful commands

```sh
docker compose exec kali bash
docker compose exec kali psql -W -h postgres -U lab -d lab
docker compose stop
docker compose down
```

`docker compose down` retains named volumes. `docker compose down -v` deletes PostgreSQL data and SSH host identity; use it only when you intentionally want to erase them.

## Validation status

The Firefox ESR addition and runtime timezone/locale setup have not yet been validated by rebuilding the image. Kali rolling package availability and dependency resolution can change over time.

## Project layout

```text
Dockerfile
compose.yaml
.env.example
.dockerignore
.gitignore
MCP_CLIENT_CONFIG.example.json
README.md
config/
  sshd_config
  supervisord.conf
scripts/
  container-entrypoint.sh
  postgres-wait.sh
postgres/init/
  10-lab-schema.sql
secrets/
  README.md
  .gitkeep
workspace/
  .gitkeep
```

## References

- [Kali Linux MCP Server package](https://www.kali.org/tools/mcp-kali-server/) — documents `kali-server-mcp` and `mcp-server`.
- [Kali Linux metapackages](https://www.kali.org/docs/general-use/metapackages/).
- [Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/).
- [PostgreSQL official image](https://hub.docker.com/_/postgres).
