# Local secrets

Create these files locally before running Compose. They are intentionally not included in the ZIP or Git:

- `authorized_keys`: one or more **public** SSH keys, one per line. Never put a private key here.
- `kali_password`: a strong password for the non-root `kali` desktop account (XRDP).
- `postgres_password`: a strong PostgreSQL application password.

Restrict local permissions, for example with `chmod 600 secrets/kali_password secrets/postgres_password` and `chmod 644 secrets/authorized_keys`. Docker Compose file-backed secrets are mounted read-only in the containers. Keep backups of secrets separately and securely.
