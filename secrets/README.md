# Local secrets

Create these files locally before running `kali.sh`. They are intentionally not included in the ZIP or Git:

- `authorized_keys`: one or more **public** SSH keys, one per line. Never put a private key here. Required for profile builds; the package-free `--minimal` image does not start SSH.
- `kali_password`: the password for the non-root `kali` account when `--gui openbox` or `--gui xfce` is selected.
- `postgres_password`: the Metasploit PostgreSQL password when the `exploitation` profile is selected.

The launcher bind-mounts all three files read-only at `/run/secrets/`, so all three files must exist even if a profile does not use one. Only put a non-empty password in the files required by the selected profile. Do not put passwords in `.env` or commit them. Restrict access to these files on the host.
