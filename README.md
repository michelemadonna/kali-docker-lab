# Kali Docker Lab

A Docker Compose lab based on the official `kalilinux/kali-rolling` image. Independent `MODE` and `DESKTOP` settings select a minimal or full toolset and no desktop, Openbox, or XFCE. All profiles include root SSH public-key authentication and Kali's official MCP API/stdio bridge; the full toolset includes Metasploit's persistent PostgreSQL database inside Kali.

> Use these tools only against systems you own or are explicitly authorized to assess. Host networking shares Kali's network namespace with the host. SSH listens on all interfaces at port `50022`; XRDP listens on all interfaces at port `53389` when a desktop is selected. Tools you launch may bind directly to host interfaces. The Kali MCP API has no independent authentication and is available only at host loopback port 5000.

## Included services and tools

- **Profiles:** `MODE=minimal|full` selects tools; `DESKTOP=no|openbox|xfce-kali` independently selects the desktop. Defaults are `full` and `openbox`.
- **Desktop:** Openbox or XFCE is exposed by XRDP only when selected. Firefox ESR and Wireshark are installed with either desktop option.
- **SSH:** root login with public key only. The authorized public key file is mounted at runtime. No private key is included or needed in this project.
- **Supervisor:** runs `sshd` and Kali's MCP API in every profile; it runs PostgreSQL only in full mode and XRDP only when a desktop is selected.
- **MCP:** Kali's official `mcp-kali-server` package supplies `kali-server-mcp` (API) and `mcp-server` (stdio bridge). The API binds to host loopback at `127.0.0.1:5000`. An MCP client starts the stdio bridge with `docker exec`; the bridge is not a network daemon.
- **Metasploit database:** full mode installs `metasploit-framework` and PostgreSQL. Supervisor starts PostgreSQL inside Kali, initializes the `msf` database, and keeps its PostgreSQL 18 data in a named volume. Metasploit connects over a Unix socket; PostgreSQL does not listen on TCP.
- **Minimal tools:** `ca-certificates`, `curl`, `wget`, `git`, `jq`, `zip`, `unzip`, `tar`, `vim-tiny`, `tmux`, `ncat`, `sudo`, `openssh-server`, `supervisor`, `libcap2-bin`, `locales`, `tzdata`, `mcp-kali-server`, `nmap`, and `tcpdump`, plus APT dependencies. SSH is retained so the minimal profile remains accessible.
- **Full capture tools:** full mode includes `tshark`; selecting either desktop also installs the Wireshark GUI.
- **Packet capture:** in the tested host-network setup, `tcpdump` captured loopback traffic without explicit Compose `cap_add`; it uses Docker's default container capabilities.
- **Tooling:** network/recon, web testing, Active Directory, exploitation, OSINT, and Bettercap/wireless command-line packages. Host networking is enabled; wireless monitor/injection still requires compatible hardware and additional device/capability access, which Compose does not grant.
- **Optional Maltego:** set `INSTALL_MALTEGO=true` at image build time. It is a GUI application and may require account activation, licensing, and additional setup. Kali rolling package availability can change.

## Requirements

- Docker Engine with the Compose plugin, or Docker Desktop / OrbStack.
- A machine with enough memory and disk for a Kali desktop and the selected tooling. XFCE and the full tool set make the image large.
- A public SSH key. Generate a key locally if needed; keep the private half outside this project.

## Quick start

From this directory:

1. Create `.env` from `.env.example`; set `MODE` to `minimal` or `full` and `DESKTOP` to `no`, `openbox`, or `xfce-kali`.
2. Supply an SSH **public** key in `secrets/authorized_keys`. Export `KALI_PASSWORD` when a desktop is selected and `POSTGRES_PASSWORD` in full mode; see [`secrets/README.md`](secrets/README.md).
3. Build and start the lab:

   ```sh
   docker compose up --build -d
   ```

4. Check service status and logs:

   ```sh
   docker compose ps
   docker compose logs -f kali
   ```

5. Connect over SSH from the host or LAN (replace the address and key path as needed):

   ```sh
   ssh -i ~/.ssh/YOUR_PRIVATE_KEY -p 50022 root@HOST_LAN_IP
   ```

   Password and keyboard-interactive SSH authentication are disabled. Root is allowed only through public-key authentication. The private key stays on the host.

6. When `DESKTOP` is `openbox` or `xfce-kali`, connect an RDP client to the host's LAN address on port `53389`, user `kali`, using the locally supplied desktop password. XRDP listens on all interfaces in both network modes. No XRDP listener is installed when `DESKTOP=no`.

### Start with the helper script

`kali.sh` starts the selected profile. It defaults to `MODE=full`, `DESKTOP=openbox`, and host networking. Use `--build` to build the image before starting; Docker reuses cached layers where possible. Rebuild when changing the tool or desktop profile.

```sh
./kali.sh --build --minimal --gui xfce
./kali.sh --full --gui no --network bridge=lab-net --build
```

`--gui xfce` maps to `DESKTOP=xfce-kali`. `--network bridge` uses the existing network named by `KALI_DOCKER_NETWORK` (default `kali-lab-bridge`); `--network bridge=NAME` selects a specific existing Docker network. `--network host` selects host networking. Run `./kali.sh --help` for all options.

### Choose a profile, XFCE, or Maltego

Set `MODE=minimal|full`, `DESKTOP=no|openbox|xfce-kali`, or `INSTALL_MALTEGO=true` in `.env`, then rebuild. Maltego is available only in full mode.

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

The Kali API listens only on host loopback at `127.0.0.1:5000`. Do not change it to `0.0.0.0`; the API has no separate authentication and exposes command execution. Confirm your MCP client supports local stdio servers and that its process can invoke Docker. The sample is generic JSON, not a client-specific import file.

## PostgreSQL

In full mode, PostgreSQL is installed by `metasploit-framework`; Supervisor starts it because this container does not run systemd. On first start, the container initializes `msf` and `msf_test`, applies the Metasploit schema, and creates the database connection file. `msfdb init` is not needed. The database uses the `postgres_password` secret and a private Unix socket; it is not exposed on a TCP port. Minimal mode has no PostgreSQL server or Metasploit packages.

Check the PostgreSQL process and Metasploit database from inside Kali:

```sh
docker compose exec kali supervisorctl status postgresql
docker compose exec kali psql -W -h /var/run/postgresql -U msf -d msf
docker compose exec kali msfconsole -qx 'db_status; exit'
```

The new PostgreSQL 18 data directory is stored in `kali-lab_metasploit_data`. The previous PostgreSQL 17 volume, `kali-lab_postgres_data`, is left untouched and is not mounted by the new container.

## Secrets and SSH host keys

The ZIP contains no passwords, private SSH keys, generated host keys, or populated secret files. Provide the `authorized_keys` file and export the password variables needed for the selected profile. Compose mounts password values as secrets. The container creates SSH host keys on first start in the persistent `ssh_host_keys` volume, so server identity survives container recreation.

If the client reports a changed SSH host key after you intentionally remove/recreate that volume, remove only the old `kali-lab` host entry from your host's `known_hosts` after verifying the change.

## Networking notes

- Kali uses `network_mode: host` by default; Docker port mappings and bridge networks are not used. SSH listens on `0.0.0.0:50022`; XRDP listens on `0.0.0.0:53389` when a desktop is selected.
- For bridge networking, use `compose.bridge.yaml` as an overlay. It publishes SSH and XRDP on all host interfaces at `50022` and `53389`, matching the container ports. Create or choose the Docker network named by `KALI_DOCKER_NETWORK` first; it must already exist.
- The Kali MCP API binds to host loopback port `5000`. PostgreSQL uses a Unix socket and has no TCP listener.
- OrbStack supports host networking. Docker Desktop requires host networking to be enabled in Settings (Docker Desktop 4.34 or later; see [Docker host networking](https://docs.docker.com/engine/network/drivers/host/)). Native Linux Docker supports it directly.
- Host networking does not pass physical Wi-Fi devices into Docker Desktop or OrbStack; monitor mode and injection still require suitable host hardware and deliberate device access.

## Useful commands

Start Kali on an existing Docker bridge network (replace `lab-net` with its name):

```sh
KALI_DOCKER_NETWORK=lab-net docker compose -f compose.yaml -f compose.bridge.yaml up --build -d
```

Create the network first if it does not exist:

```sh
docker network create lab-net
```

```sh
docker compose exec kali bash
docker compose exec kali psql -W -h /var/run/postgresql -U msf -d msf
docker compose exec kali supervisorctl status
docker compose stop
docker compose down
```

`docker compose down` retains named volumes. `docker compose down -v` deletes the Metasploit database and SSH host identity; use it only when you intentionally want to erase them.

## Validation status

Verified at runtime: `minimal/no` starts SSH and MCP with XRDP and PostgreSQL absent; `minimal/openbox` and `minimal/xfce-kali` start XRDP and use the selected desktop session; `full/no` starts PostgreSQL and Metasploit reports a connected database while XRDP stays absent. Builds for `minimal/openbox`, `minimal/xfce-kali`, and `full/no` succeeded. In the active host-networked `minimal/xfce-kali` container, SSH and XRDP listen on `0.0.0.0:50022` and `0.0.0.0:53389`; connections to both ports succeeded via the host LAN address. A temporary host-networked container captured a loopback TCP SYN with `tcpdump` while `no-new-privileges` was enabled and no explicit capabilities were added. Bridge Compose configuration validates and publishes both ports on all host interfaces. The `full/xfce-kali` build was interrupted after Docker stopped responding, so that combination and the rebuilt default `full/openbox` remain unverified with this change. Kali rolling package availability and dependency resolution can change over time.

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
  kali.sh
  container-entrypoint.sh
  postgresql-prepare.sh
  postgresql-foreground.sh
secrets/
  README.md
  .gitkeep
workspace/
  .gitkeep
```

## References

- [Kali Linux MCP Server package](https://www.kali.org/tools/mcp-kali-server/) — documents `kali-server-mcp` and `mcp-server`.
- [Kali Linux Metasploit Framework package](https://www.kali.org/tools/metasploit-framework/).
- [Metasploit database support](https://docs.metasploit.com/docs/using-metasploit/intermediate/metasploit-database-support.html).
- [Kali Linux metapackages](https://www.kali.org/docs/general-use/metapackages/).
- [Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/).
