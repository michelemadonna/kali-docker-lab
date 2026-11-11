FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC \
    TERM=xterm-256color

ARG PROFILES=
ARG DESKTOP=openbox
ARG MINIMAL=false

RUN set -eux; \
    if [ "$MINIMAL" = true ]; then \
      [ -z "$PROFILES" ] || { echo 'MINIMAL=true cannot be combined with PROFILES' >&2; exit 1; }; \
      printf '%s\n' '' > /etc/kali-profiles; \
      touch /etc/kali-minimal; \
      case "$DESKTOP" in \
        no) ;; \
        openbox) gui="ca-certificates supervisor xrdp xorgxrdp dbus-x11 xauth openbox lxpanel lxterminal obconf thunar xinit firefox-esr wireshark" ;; \
        xfce-kali) gui="ca-certificates supervisor xrdp xorgxrdp dbus-x11 xauth kali-desktop-xfce firefox-esr wireshark" ;; \
        *) echo "Unsupported DESKTOP: $DESKTOP (expected no, openbox, or xfce-kali)" >&2; exit 1 ;; \
      esac; \
      if [ -n "${gui:-}" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends $gui; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
        touch /etc/kali-minimal-gui; \
        useradd --create-home --shell /bin/bash kali; \
        if [ "$DESKTOP" = openbox ]; then \
          mkdir -p /home/kali/.config/openbox; \
          echo 'lxpanel &' >> /home/kali/.config/openbox/autostart; \
          echo 'setxkbmap it &' >> /home/kali/.config/openbox/autostart; \
          chown -R kali:kali /home/kali/.config/openbox; \
        fi; \
        install -d -o root -g root -m 0755 /var/run/supervisor; \
      fi; \
    else \
    [ "$MINIMAL" = false ] || { echo "Unsupported MINIMAL value: $MINIMAL" >&2; exit 1; }; \
    apt-get update; \
    common="ca-certificates kali-tweaks curl wget git jq zip unzip tar vim-tiny tmux ncat sudo openssh-server supervisor libcap2-bin locales tzdata mcp-kali-server iproute2 iputils-ping net-tools iputils-tracepath traceroute mtr-tiny ethtool netcat-openbsd isc-dhcp-client-ddns isc-dhcp-client command-not-found python3 python3-pip python3-venv pipx build-essential golang-go whois"; \
    extra=""; \
    add_packages() { \
      for package do \
        case " $extra $common " in *" $package "*) ;; *) extra="${extra:+$extra }$package" ;; esac; \
      done; \
    }; \
    selected_profiles=""; \
    old_ifs=$IFS; IFS=,; set -- $PROFILES; IFS=$old_ifs; \
    for profile in "$@"; do \
      case ",$selected_profiles," in *",$profile,"*) continue ;; esac; \
      case "$profile" in \
        network) add_packages nmap masscan rustscan netdiscover dnsrecon dnsutils tcpdump tshark wireshark hping3 ;; \
        web) add_packages gobuster feroxbuster ffuf whatweb nikto nuclei sqlmap wpscan sslscan seclists dirb ;; \
        ad) add_packages netexec python3-impacket enum4linux-ng smbclient smbmap ldap-utils python3-ldapdomaindump certipy-ad bloodhound.py responder krb5-user ;; \
        exploitation) add_packages openjdk-21-jdk postgresql-client metasploit-framework exploitdb hydra john hashcat peass proxychains4 mitmproxy ;; \
        osint) add_packages openjdk-21-jdk maltego theharvester recon-ng amass dnsrecon dnsutils exiftool subfinder spiderfoot sherlock photon trufflehog gitleaks ;; \
        wireless) add_packages aircrack-ng bettercap bettercap-caplets bettercap-ui kismet hcxdumptool hcxtools reaver bully wifite hostapd iw wireless-tools bluez python3-scapy wpasupplicant ;; \
        "") echo 'Empty profile in PROFILES' >&2; exit 1 ;; \
        *) echo "Unsupported profile: $profile" >&2; exit 1 ;; \
      esac; \
      case ",$selected_profiles," in *",$profile,"*) ;; *) selected_profiles="${selected_profiles:+$selected_profiles,}$profile" ;; esac; \
    done; \
    case "$DESKTOP" in \
      no) desktop="" ;; \
      openbox) desktop="xrdp xorgxrdp dbus-x11 xauth openbox lxpanel lxterminal obconf thunar xinit firefox-esr wireshark " ;; \
      xfce-kali) desktop="xrdp xorgxrdp dbus-x11 xauth kali-desktop-xfce firefox-esr wireshark" ;; \
      *) echo "Unsupported DESKTOP: $DESKTOP (expected no, openbox, or xfce-kali)" >&2; exit 1 ;; \
    esac; \
    printf '%s\n' "$selected_profiles" > /etc/kali-profiles; \
    apt-get install -y --no-install-recommends $desktop $common $extra; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --create-home --shell /bin/bash kali; \
    usermod -aG sudo kali; \
    printf '%s\n' 'kali ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-kali; \
    chmod 0440 /etc/sudoers.d/90-kali; \
    if [ "$DESKTOP" = "openbox" ]; then \
      mkdir -p /home/kali/.config/openbox; \
      echo 'lxpanel &' >> /home/kali/.config/openbox/autostart; \
      echo 'setxkbmap it &' >> /home/kali/.config/openbox/autostart; \
      chown -R kali:kali /home/kali/.config/openbox; \
    fi; \
    install -d -o root -g root -m 0755 /run/sshd /var/run/supervisor; \
    fi

RUN if grep -Eq '(^|,)exploitation(,|$)' /etc/kali-profiles; then \
      set -eux; \
      pg_version="$(pg_lsclusters --no-header | awk 'NR == 1 { print $1 }')"; \
      [ -n "$pg_version" ] || { echo 'PostgreSQL server dependency did not install a cluster' >&2; exit 1; }; \
      pg_dropcluster --stop "$pg_version" main; \
      printf '%s\n' "$pg_version" > /etc/kali-postgresql-version; \
    fi

COPY opt/ /opt/
COPY config/sshd_config /etc/ssh/sshd_config
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY config/supervisord-minimal-gui.conf /etc/supervisor/supervisord-minimal-gui.conf
COPY config/supervisor-postgresql.conf /etc/supervisor/conf.d/postgresql.conf
COPY config/supervisor-xrdp.conf /etc/supervisor/conf.d/xrdp.conf
COPY scripts/container-entrypoint.sh /usr/local/sbin/container-entrypoint
COPY scripts/postgresql-prepare.sh /usr/local/sbin/postgresql-prepare
COPY scripts/postgresql-foreground.sh /usr/local/sbin/postgresql-foreground
RUN chmod 0755 /usr/local/sbin/container-entrypoint \
        /usr/local/sbin/postgresql-prepare /usr/local/sbin/postgresql-foreground \
    && if [ -f /etc/kali-minimal ]; then \
         if id kali >/dev/null 2>&1; then install -d -o kali -g kali /home/kali/workspace; else install -d /home/kali/workspace; fi; \
         if [ -f /etc/kali-minimal-gui ] && getent group ssl-cert >/dev/null && id xrdp >/dev/null 2>&1; then usermod -aG ssl-cert xrdp; fi; \
       else \
         install -d -o kali -g kali /home/kali/workspace \
         && setcap cap_net_raw+ep /usr/bin/ping \
         && if getent group ssl-cert >/dev/null && id xrdp >/dev/null 2>&1; then usermod -aG ssl-cert xrdp; fi; \
       fi

EXPOSE 50022
ENTRYPOINT ["/usr/local/sbin/container-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
