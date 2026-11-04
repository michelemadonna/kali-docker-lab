# Local secrets

Create these files locally before running Compose. They are intentionally not included in the ZIP or Git:

- `authorized_keys`: one or more **public** SSH keys, one per line. Never put a private key here.

`authorized_keys` is required in every mode. Provide `KALI_PASSWORD` in the host environment when `DESKTOP` is `openbox` or `xfce-kali`, and `POSTGRES_PASSWORD` when `MODE=full`. Compose mounts these values as read-only secrets; do not put them in `.env` or commit them. For example, export them in the shell that runs Compose. Restrict local permissions on `authorized_keys`, for example with `chmod 644 secrets/authorized_keys`.
