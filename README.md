# Kali Docker Lab

A Docker lab based on the official `kalilinux/kali-rolling` image. The `kali.sh` launcher builds and runs the container with Docker CLI commands. Profile builds install a common base plus selected tool groups; `--minimal` builds an image with no APT-installed packages. GUI selection remains independent for profile builds.

> Use these tools only against systems you own or are explicitly authorized to assess. Host networking shares Kali's network namespace with the host. SSH listens on all interfaces at port `50022`; XRDP listens on all interfaces at port `53389` when a desktop is selected. Tools you launch may bind directly to host interfaces. The Kali MCP API has no independent authentication and is available only at host loopback port 5000.

## Included services and tools

- **Profiles:** profile builds install common utilities, SSH, MCP, and Python tooling. Optional profiles are `network`, `web`, `ad`, `exploitation`, `osint`, and `wireless`. `DESKTOP=no|openbox|xfce-kali` in `.env` or `--gui` selects the GUI; profile builds default to Openbox. `--minimal` omits the common base and tools; if no desktop is selected it installs no packages and stays available for `docker exec`. With a desktop selected, it installs only GUI and supervisor packages and provides XRDP without SSH or MCP.
- **Desktop:** Openbox or XFCE is exposed by XRDP when selected. Firefox ESR and Wireshark are installed with either desktop option.
- **SSH:** profile builds allow root login with public key only. The authorized public key file is mounted at runtime. No private key is included or needed in this project.
- **Supervisor:** in profile builds it runs `sshd` and Kali's MCP API; it runs PostgreSQL only when `exploitation` is selected and XRDP only when a desktop is selected.
- **MCP:** profile builds use Kali's official `mcp-kali-server` package, which supplies `kali-server-mcp` (API) and `mcp-server` (stdio bridge). The API binds to host loopback at `127.0.0.1:5000`. An MCP client starts the stdio bridge with `docker exec`; the bridge is not a network daemon.
- **Metasploit database:** `exploitation` installs Metasploit and PostgreSQL. Supervisor starts PostgreSQL inside Kali, initializes the `msf` database, and keeps its data in `kali-lab_metasploit_data`. Metasploit connects over a Unix socket; PostgreSQL does not listen on TCP.
- **Network capture:** `network` installs `tcpdump`, `tshark`, and Wireshark. Selecting either desktop also installs Wireshark, regardless of tool profile.
- **Container capabilities:** host networking always uses Docker's `--privileged` mode. In bridge mode, `--privileged` remains the default; `--no-privileged` instead adds `NET_RAW`, `NET_ADMIN`, and `NET_BIND_SERVICE` for raw scans, packet capture/promiscuous mode, and ping. The `network` profile includes hping3. The host still controls device access.
- **Maltego:** installed only as part of `osint`; it may require account activation, licensing, and additional setup. Kali rolling package availability can change.

## Requirements

- Docker Engine, Docker Desktop, or OrbStack with the `docker` CLI.
- A machine with enough memory and disk for a Kali desktop and the selected tooling. XFCE and the full tool set make the image large.
- A public SSH key. Generate a key locally if needed; keep the private half outside this project.

## Quick start

1. Create `.env` from `.env.example` and set `PROFILES`, or choose a build selection on the command line. A profile selection is required unless building with `--minimal`.
2. Create the secret files described in [`secrets/README.md`](secrets/README.md). Add one or more SSH **public** keys to `secrets/authorized_keys`.
3. Build and start the lab. `--name NAME` is required and must be unique among local containers:

   ```sh
   ./kali.sh --name kali-lab --build --profile network,osint
   ```

   Add `--full` for all six profiles. `--gui xfce` maps to `DESKTOP=xfce-kali`. Bridge mode creates the selected Docker bridge network if it does not exist and publishes SSH and XRDP on host ports `50022` and `53389`. `--minimal` without a desktop builds a package-free container for `docker exec`; set `DESKTOP` in `.env` or add `--gui` during the build to install only desktop support.
4. Check status and logs:

   ```sh
   docker ps --filter name=kali-lab
   docker logs -f kali-lab
   ```

5. Connect over SSH from the host or LAN (replace the address and key path as needed):

   ```sh
   ssh -i ~/.ssh/YOUR_PRIVATE_KEY -p 50022 root@HOST_LAN_IP
   ```

   Password and keyboard-interactive SSH authentication are disabled. Root is allowed only through public-key authentication. The private key stays on the host.
6. When `DESKTOP` is `openbox` or `xfce-kali`, connect an RDP client to the host's LAN address on port `53389`, user `kali`, using the locally supplied desktop password. XRDP listens on all interfaces in both network modes. No XRDP listener is installed when `DESKTOP=no`.

### Launcher options

`kali.sh` accepts the required container name, an optional profile selector (required for a new container), and the existing GUI and networking options:

```sh
./kali.sh --name kali-lab --build --profile osint,wireless --gui xfce
./kali.sh --name kali-lab --full --gui no --network bridge=lab-net --build
```

Profiles can be set in `.env` as `PROFILES=network,osint`, or passed with `--profile LIST` / `--profile=LIST`; the CLI list replaces `.env`. `--profile`, `--full`, `--minimal`, and `--gui` can only be passed with `--build`. The profile selectors `--profile`, `--full`, and `--minimal` are mutually exclusive. `DESKTOP` in `.env` is used when `--gui` is omitted; profile builds default to Openbox, while `--minimal` stays bare unless a desktop is explicitly configured. `--minimal` omits base and tool packages; when a desktop is selected it installs only GUI dependencies. `--full` installs every optional profile and the common base. A profile selection in `.env` is required when creating a profile image without a CLI selector. An existing container can be started with `--name` alone. Unknown or empty profile entries are errors. Duplicate profile names are ignored.

`--build` builds `local/kali-offsec-lab:rolling` with the selected tools and GUI. For a new container without `--build`, the image must already exist and its profile and desktop labels must match the requested selection. If the named container already exists and `--build` is omitted, `kali.sh` reuses it: only `--name` is required, and it starts the container if stopped. Any profile selection provided in CLI or `.env` must match that container's image. Existing containers keep their GUI, timezone, locale, and other creation-time settings.

For a new container, `.env` values for `TZ`, `LANG`, and `KALI_DOCKER_NETWORK` are passed at creation. `--network bridge` uses the network named by `KALI_DOCKER_NETWORK` (default `kali-lab-bridge`); `--network bridge=NAME` selects a specific network. If the selected network does not exist, `kali.sh` creates it as a Docker bridge network. If a network with that name exists but uses another driver, the launcher stops with an error. `--network host` selects host networking. When reusing a container, omitting `--network` preserves its current network. An explicit bridge request switches a single existing network by connecting the requested network before disconnecting the old one; containers attached to multiple networks require manual adjustment. Switching between host and bridge modes requires removing and recreating the container. `./kali.sh --help` lists all options.

`--build` refuses to overwrite a container with the requested name. To recreate it, remove it explicitly, then rerun `kali.sh`; include `--build` if the profiles or GUI changed. Docker cannot change privilege mode on an existing container, so recreate it to apply or remove `--no-privileged`. That option is only available with bridge networking; host mode always uses `--privileged`:

```sh
docker rm -f kali-lab
```

Removing a container retains the named volumes. To intentionally delete the Metasploit database and SSH host identity as well, remove volumes `kali-lab_metasploit_data` and `kali-lab_ssh_host_keys` explicitly.

### Build profiles manually

Use the launcher to validate and normalize profile names. The Docker build argument is `PROFILES`, a comma-separated list of supported IDs; with `MINIMAL=false`, an empty value installs the common base. `MINIMAL=true` requires an empty profile list and omits the common base; `DESKTOP=no` installs no packages, while a desktop value installs only its GUI dependencies.

```sh
docker build \
  --build-arg PROFILES=network,osint \
  --build-arg DESKTOP=openbox \
  --label local.kali.profiles=network,osint \
  --tag local/kali-offsec-lab:rolling .
```

Then start it with `./kali.sh --name kali-lab` or the desired profile/network flags.

### Configure timezone and locale

Set `TZ` to an IANA timezone and `LANG` to a UTF-8 locale in `.env`; for example:

```dotenv
TZ=Europe/Rome
LANG=it_IT.UTF-8
```

Each newly launched container receives these values.

## MCP client connection

The included [`MCP_CLIENT_CONFIG.example.json`](MCP_CLIENT_CONFIG.example.json) shows the stdio connection command. Adapt its `mcpServers` entry to your MCP client's configuration format. The important command is:

```sh
docker exec -i kali-lab mcp-server --server http://127.0.0.1:5000
```

Replace `kali-lab` with the name passed to `--name`. The Kali API listens only on host loopback at `127.0.0.1:5000`. Do not change it to `0.0.0.0`; the API has no separate authentication and exposes command execution. Confirm your MCP client supports local stdio servers and that its process can invoke Docker. The sample is generic JSON, not a client-specific import file.

## PostgreSQL

With `exploitation` selected, PostgreSQL is installed with Metasploit; Supervisor starts it because this container does not run systemd. On first start, the container initializes `msf` and `msf_test`, applies the Metasploit schema, and creates the database connection file. `msfdb init` is not needed. The database uses the `postgres_password` file and a private Unix socket; it is not exposed on a TCP port. Without `exploitation`, PostgreSQL and Metasploit are not installed.

Check PostgreSQL and Metasploit from inside Kali:

```sh
docker exec -it kali-lab supervisorctl status postgresql
docker exec -it kali-lab psql -W -h /var/run/postgresql -U msf -d msf
docker exec -it kali-lab msfconsole -qx 'db_status; exit'
```

The `kali-lab_metasploit_data` volume stores the PostgreSQL data. The SSH host keys persist in `kali-lab_ssh_host_keys`.

## Secrets and SSH host keys

The ZIP contains no passwords, private SSH keys, generated host keys, or populated secret files. Create the local secret files described in [`secrets/README.md`](secrets/README.md). `kali.sh` mounts them read-only at `/run/secrets/`; do not put passwords in `.env` or commit them. The container creates SSH host keys on first start in the persistent `kali-lab_ssh_host_keys` volume, so server identity survives container removal and recreation.

If the client reports a changed SSH host key after you intentionally remove that volume, remove only the old `kali-lab` host entry from your host's `known_hosts` after verifying the change.

## Networking notes

- Kali uses `--network host` by default; port mappings are not used in that mode. SSH listens on `0.0.0.0:50022`; XRDP listens on `0.0.0.0:53389` when a desktop is selected.
- Bridge mode creates the selected Docker bridge network if needed and publishes SSH and XRDP on all host interfaces at `50022` and `53389`. Set `KALI_DOCKER_NETWORK` in `.env` or pass `--network bridge=NAME`.
- The Kali MCP API binds to host loopback port `5000`. PostgreSQL uses a Unix socket and has no TCP listener.
- OrbStack supports host networking. Docker Desktop requires host networking to be enabled in Settings (Docker Desktop 4.34 or later; see [Docker host networking](https://docs.docker.com/engine/network/drivers/host/)). Native Linux Docker supports it directly.
- Host networking does not pass physical Wi-Fi devices into Docker Desktop or OrbStack; monitor mode and injection still require suitable host hardware and deliberate device access.

For example, `./kali.sh --name kali-lab --network bridge=lab-net --build` creates `lab-net` automatically if needed.

## Useful commands

Replace `kali-lab` with the chosen container name:

```sh
docker exec -it kali-lab bash
docker exec -it kali-lab psql -W -h /var/run/postgresql -U msf -d msf
docker exec -it kali-lab supervisorctl status
docker stop kali-lab
docker start kali-lab
docker rm -f kali-lab
```

Stopping or removing the container retains named volumes. Removing `kali-lab_metasploit_data` deletes the Metasploit database; removing `kali-lab_ssh_host_keys` replaces the SSH server identity on next start.

## Validation status

Current profile builds were checked for the base, `network`, and `exploitation` selections. APT dependency resolution was also simulated across the union of the six profile package lists. GUI startup and host/bridge networking had been verified with the previous launcher; Kali rolling package availability can change over time.

## Project layout

```text
Dockerfile
kali.sh
.env.example
.dockerignore
.gitignore
MCP_CLIENT_CONFIG.example.json
README.md
config/
scripts/
secrets/
workspace/
```

## References

- [Kali Linux MCP Server package](https://www.kali.org/tools/mcp-kali-server/) — documents `kali-server-mcp` and `mcp-server`.
- [Kali Linux Metasploit Framework package](https://www.kali.org/tools/metasploit-framework/).
- [Metasploit database support](https://docs.metasploit.com/docs/using-metasploit/intermediate/metasploit-database-support.html).
- [Kali Linux metapackages](https://www.kali.org/docs/general-use/metapackages/).
