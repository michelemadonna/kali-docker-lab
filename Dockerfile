FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC \
    TERM=xterm-256color

ARG DESKTOP=openbox
ARG INSTALL_MALTEGO=false

RUN set -eux; \
    apt-get update; \
    common="ca-certificates curl wget git jq zip unzip tar vim-tiny tmux ncat openjdk-21-jdk \
      sudo kali-tweaks openssh-server supervisor xrdp xorgxrdp dbus-x11 xauth libcap2-bin \
      firefox-esr locales tzdata \
      postgresql-client mcp-kali-server \
      nmap masscan rustscan netdiscover dnsrecon dnsutils whois \
      gobuster ffuf feroxbuster dirb nikto sqlmap wpscan \
      netexec impacket-scripts bloodhound.py enum4linux-ng smbclient ldap-utils krb5-user responder \
      metasploit-framework exploitdb john hashcat \
      theharvester recon-ng \
      bettercap aircrack-ng iw wireless-tools hcxtools"; \
    case "$DESKTOP" in \
      openbox) desktop="openbox lxpanel lxterminal obconf thunar xinit" ;; \
      kali-xfce) desktop="kali-desktop-xfce" ;; \
      *) echo "Unsupported DESKTOP: $DESKTOP" >&2; exit 1 ;; \
    esac; \
    if [ "$INSTALL_MALTEGO" = "true" ]; then common="$common maltego"; fi; \
    apt-get install -y --no-install-recommends $desktop $common; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --create-home --shell /bin/bash kali; \
    usermod -aG sudo kali; \
    mkdir -p /home/kali/.config/openbox; \
    echo 'lxpanel &' >> /home/kali/.config/openbox/autostart; \
    echo 'setxkbmap it &' >> /home/kali/.config/openbox/autostart; \
    chown -R kali:kali /home/kali/.config/openbox; \
    install -d -o root -g root -m 0755 /run/sshd /var/run/supervisor

COPY opt/ /opt/
COPY config/sshd_config /etc/ssh/sshd_config
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY scripts/container-entrypoint.sh /usr/local/sbin/container-entrypoint
COPY scripts/postgres-wait.sh /usr/local/bin/postgres-wait
RUN chmod 0755 /usr/local/sbin/container-entrypoint /usr/local/bin/postgres-wait \
    && install -d -o kali -g kali /home/kali/workspace \
    && setcap -r /usr/lib/nmap/nmap \
    && usermod -aG ssl-cert xrdp

EXPOSE 22 80 8888 8080 3389
ENTRYPOINT ["/usr/local/sbin/container-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
