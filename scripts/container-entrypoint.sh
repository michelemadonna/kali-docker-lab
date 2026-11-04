#!/bin/bash
set -Eeuo pipefail

fail() { echo "container-entrypoint: $*" >&2; exit 1; }

configure_locale_and_timezone() {
  local timezone="${TZ:-Etc/UTC}"
  local locale_name="${LANG:-C.UTF-8}"

  case "$timezone" in
    ''|/*|*..*|*[!A-Za-z0-9_+/-]*) fail "invalid TZ value: $timezone" ;;
  esac
  [[ -f "/usr/share/zoneinfo/$timezone" ]] || fail "unknown TZ value: $timezone"
  ln -snf "/usr/share/zoneinfo/$timezone" /etc/localtime
  printf '%s\n' "$timezone" > /etc/timezone
  export TZ="$timezone"

  case "$locale_name" in
    C|POSIX|C.UTF-8|C.utf8)
      export LANG="$locale_name"
      printf 'LANG=%s\n' "$locale_name" > /etc/default/locale
      return
      ;;
  esac
  [[ "$locale_name" =~ ^[A-Za-z][A-Za-z0-9_@.-]*\.[Uu][Tt][Ff](-8|8)$ ]] \
    || fail "LANG must be a UTF-8 locale (for example it_IT.UTF-8): $locale_name"

  if ! grep -Fqx "$locale_name UTF-8" /etc/locale.gen; then
    printf '%s UTF-8\n' "$locale_name" >> /etc/locale.gen
  fi
  locale-gen --keep-existing
  LANG="$locale_name" locale charmap >/dev/null 2>&1 \
    || fail "could not activate LANG locale: $locale_name"
  export LANG="$locale_name"
  printf 'LANG=%s\n' "$locale_name" > /etc/default/locale
}

configure_locale_and_timezone

mode="${MODE:-full}"
desktop="${DESKTOP:-openbox}"
network_mode="${KALI_NETWORK_MODE:-host}"
case "$mode" in
  minimal|full) ;;
  *) fail "MODE must be minimal or full: $mode" ;;
esac
case "$desktop" in
  no|openbox|xfce-kali) ;;
  *) fail "DESKTOP must be no, openbox, or xfce-kali: $desktop" ;;
esac
case "$network_mode" in
  host|bridge) ;;
  *) fail "KALI_NETWORK_MODE must be host or bridge: $network_mode" ;;
esac

[[ -r /run/secrets/authorized_keys ]] || fail "authorized_keys secret is missing or unreadable"

if [[ "$mode" == full ]]; then
  [[ -r /run/secrets/postgres_password ]] || fail "PostgreSQL password secret is missing or unreadable"
  /usr/local/sbin/postgresql-prepare
fi

# Never bake host keys into the image. Keep them in a named volume.
install -d -o root -g root -m 0700 /etc/ssh/hostkeys
for type in ed25519 rsa; do
  key="/etc/ssh/hostkeys/ssh_host_${type}_key"
  if [[ ! -s "$key" ]]; then
    ssh-keygen -q -t "$type" -N '' -f "$key"
  fi
  chown root:root "$key" "${key}.pub"
  chmod 0600 "$key"
  chmod 0644 "${key}.pub"
done

# The mounted public-key file is checked without copying it into the image.
grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)' /run/secrets/authorized_keys \
  || fail "authorized_keys contains no supported public key"

if [[ "$desktop" != no ]]; then
  [[ -r "${KALI_PASSWORD_FILE:-}" ]] || fail "KALI_PASSWORD_FILE secret is missing or unreadable"
  # Set the non-root desktop user's password from a mounted runtime secret.
  kali_password="$(cat "$KALI_PASSWORD_FILE")"
  [[ -n "$kali_password" ]] || fail "Kali desktop password secret is empty"
  printf 'kali:%s\n' "$kali_password" | chpasswd
  unset kali_password
fi
# Keep root's account eligible for public-key SSH. The sentinel is not a valid
# password hash; sshd independently disables password and keyboard-interactive auth.
usermod --password 'NP' root

if [[ "$desktop" == xfce-kali ]]; then
  printf '%s\n' 'startxfce4' > /home/kali/.xsession
  chown kali:kali /home/kali/.xsession
  chmod 0600 /home/kali/.xsession
elif [[ "$desktop" == openbox ]]; then
  printf '%s\n' 'exec openbox-session' > /home/kali/.xsession
  chown kali:kali /home/kali/.xsession
  chmod 0600 /home/kali/.xsession
fi

if [[ "$mode" != full ]]; then
  rm -f /etc/supervisor/conf.d/postgresql.conf
fi

# SSH is intentionally reachable on the LAN in either Docker network mode.
sed -i 's/^ListenAddress 127\.0\.0\.1$/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config

if [[ "$desktop" == no ]]; then
  rm -f /etc/supervisor/conf.d/xrdp.conf
else
  if [[ "$network_mode" == host ]]; then
    # Host networking has no port translation; expose the requested XRDP port.
    sed -i '0,/^port=3389$/s//port=tcp:\/\/0.0.0.0:53389/' /etc/xrdp/xrdp.ini
  else
    # The bridge publishes the same port number on host and container.
    sed -i '0,/^port=3389$/s//port=tcp:\/\/0.0.0.0:53389/' /etc/xrdp/xrdp.ini
  fi
fi

exec "$@"
