FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC \
    TERM=xterm-256color

ARG MODE=full
ARG DESKTOP=openbox
ARG INSTALL_MALTEGO=false

RUN set -eux; \
    apt-get update; \
    common="ca-certificates curl wget git jq zip unzip tar vim-tiny tmux ncat sudo openssh-server supervisor libcap2-bin locales tzdata mcp-kali-server nmap tcpdump"; \
    case "$MODE" in \
      minimal) \
        [ "$INSTALL_MALTEGO" != "true" ] || { echo 'INSTALL_MALTEGO is available only in MODE=full' >&2; exit 1; } ;; \
      full) \
        common="$common openjdk-21-jdk postgresql-client tshark masscan rustscan netdiscover dnsrecon dnsutils whois gobuster ffuf feroxbuster dirb nikto sqlmap wpscan netexec impacket-scripts bloodhound.py enum4linux-ng smbclient ldap-utils krb5-user responder metasploit-framework exploitdb john hashcat theharvester recon-ng bettercap aircrack-ng iw wireless-tools hcxtools" ;; \
      *) echo "Unsupported MODE: $MODE (expected minimal or full)" >&2; exit 1 ;; \
    esac; \
    case "$DESKTOP" in \
      no) desktop="" ;; \
      openbox) desktop="xrdp xorgxrdp dbus-x11 xauth openbox lxpanel lxterminal obconf thunar xinit firefox-esr wireshark kali-tweaks" ;; \
      xfce-kali) desktop="xrdp xorgxrdp dbus-x11 xauth kali-desktop-xfce kali-tweaks firefox-esr wireshark" ;; \
      *) echo "Unsupported DESKTOP: $DESKTOP (expected no, openbox, or xfce-kali)" >&2; exit 1 ;; \
    esac; \
    if [ "$INSTALL_MALTEGO" = "true" ]; then common="$common maltego"; fi; \
    apt-get install -y --no-install-recommends $desktop $common; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --create-home --shell /bin/bash kali; \
    usermod -aG sudo kali; \
    if [ "$DESKTOP" = "openbox" ]; then \
      mkdir -p /home/kali/.config/openbox; \
      echo 'lxpanel &' >> /home/kali/.config/openbox/autostart; \
      echo 'setxkbmap it &' >> /home/kali/.config/openbox/autostart; \
      chown -R kali:kali /home/kali/.config/openbox; \
    fi; \
    install -d -o root -g root -m 0755 /run/sshd /var/run/supervisor

RUN if [ "$MODE" = "full" ]; then \
      set -eux; \
      pg_version="$(pg_lsclusters --no-header | awk 'NR == 1 { print $1 }')"; \
      [ -n "$pg_version" ] || { echo 'PostgreSQL server dependency did not install a cluster' >&2; exit 1; }; \
      pg_dropcluster --stop "$pg_version" main; \
      printf '%s\n' "$pg_version" > /etc/kali-postgresql-version; \
    fi

COPY opt/ /opt/
COPY config/sshd_config /etc/ssh/sshd_config
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY config/supervisor-postgresql.conf /etc/supervisor/conf.d/postgresql.conf
COPY config/supervisor-xrdp.conf /etc/supervisor/conf.d/xrdp.conf
COPY scripts/container-entrypoint.sh /usr/local/sbin/container-entrypoint
COPY scripts/postgresql-prepare.sh /usr/local/sbin/postgresql-prepare
COPY scripts/postgresql-foreground.sh /usr/local/sbin/postgresql-foreground
RUN chmod 0755 /usr/local/sbin/container-entrypoint \
        /usr/local/sbin/postgresql-prepare /usr/local/sbin/postgresql-foreground \
    && install -d -o kali -g kali /home/kali/workspace \
    && setcap -r /usr/lib/nmap/nmap \
    && if getent group ssl-cert >/dev/null && id xrdp >/dev/null 2>&1; then usermod -aG ssl-cert xrdp; fi

EXPOSE 50022
ENTRYPOINT ["/usr/local/sbin/container-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
