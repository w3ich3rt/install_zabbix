#!/bin/bash

set -e

# Farben
GREEN="\e[32m"
RESET="\e[0m"
YELLOW="\e[33m"
RED="\e[31m"

step() {
  echo -e "${GREEN}Starte mit Schritt $1...${RESET}"
}

done_step() {
  echo -e "${GREEN}Schritt $1 ausgeführt.${RESET}"
}

# Grundlegende Infos
IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo -e "${YELLOW}IP-Adresse: $IP${RESET}"
echo -e "${YELLOW}Hostname: $HOSTNAME${RESET}"

# Temporäre Tools installieren
step "1 (temporäre Tools)"
if [ -f /etc/debian_version ]; then
  apt-get update -qq >/dev/null
  apt-get install -y -qq wget gnupg lsb-release >/dev/null
elif [ -f /etc/rocky-release ]; then
  dnf install -y -q wget gnupg redhat-lsb-core epel-release >/dev/null
fi
done_step "1"

# System erkennen
if [ -f /etc/debian_version ]; then
  OS="debian"
elif [ -f /etc/rocky-release ]; then
  OS="rocky"
  ROCKY_VERSION=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2 | cut -d '.' -f1)
  echo -e "${YELLOW}Rocky-Version erkannt: $ROCKY_VERSION${RESET}"
else
  echo -e "${RED}Nicht unterstütztes Betriebssystem.${RESET}"
  exit 1
fi

# Schritt 1b: epel.repo bei Rocky anpassen
if [ "$OS" = "rocky" ]; then
  step "1b (epel.repo anpassen)"
  sed -i '/^\[epel\]/,/^\[/{/^\[epel\]/b;/^excludepkgs=/d}' /etc/yum.repos.d/epel.repo
  sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo
  done_step "1b"
fi

# Schritt 2: Zabbix-Repository hinzufügen
step "2 (Zabbix-Repository hinzufügen)"
if [ "$OS" = "debian" ]; then
  wget -q https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb
  dpkg -i zabbix-release_latest_7.0+debian12_all.deb >/dev/null
  apt-get update -qq >/dev/null
elif [ "$OS" = "rocky" ]; then
  if [ "$ROCKY_VERSION" = "8" ]; then
    wget -q https://repo.zabbix.com/zabbix/7.0/rhel/8/x86_64/zabbix-release-7.0-1.el8.noarch.rpm
    dnf install -y -q zabbix-release-7.0-1.el8.noarch.rpm >/dev/null
  elif [ "$ROCKY_VERSION" = "9" ]; then
    wget -q https://repo.zabbix.com/zabbix/7.0/rocky/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
    dnf install -y -q zabbix-release-latest-7.0.el9.noarch.rpm >/dev/null
  else
    echo -e "${RED}Nicht unterstützte Rocky-Version: $ROCKY_VERSION${RESET}"
    exit 1
  fi
  dnf clean all >/dev/null
fi
done_step "2"

# Schritt 3: Systemupdate
step "3 (Systemupdate)"
if [ "$OS" = "debian" ]; then
  apt-get -y -qq upgrade >/dev/null
elif [ "$OS" = "rocky" ]; then
  dnf -y -q upgrade --refresh >/dev/null
fi
done_step "3"

# Schritt 4: Zabbix-Agent installieren
step "4 (Zabbix-Agent und Plugins installieren)"
if [ "$OS" = "debian" ]; then
  apt-get install -y -qq zabbix-agent2 zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql >/dev/null
elif [ "$OS" = "rocky" ]; then
  dnf install -y -q zabbix-agent2 zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql >/dev/null
fi
done_step "4"

# Schritt 5: Agent konfigurieren
step "5 (Zabbix-Agent konfigurieren)"
ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"

# Zabbix-Server abfragen
read -p "Zabbix Server IP oder DNS: " ZABBIX_SERVER

# Config anpassen
sed -i 's/^Hostname=/## Hostname=/' "$ZBX_CONF"
sed -i 's|^# HostnameItem=.*|HostnameItem=system.hostname|' "$ZBX_CONF"
sed -i "s|^Server=.*|Server=$ZABBIX_SERVER|" "$ZBX_CONF"
sed -i "s|^ServerActive=.*|ServerActive=$ZABBIX_SERVER|" "$ZBX_CONF"
done_step "5"

# Schritt 6: Autostart aktivieren
step "6 (Autostart aktivieren)"
systemctl enable zabbix-agent2 >/dev/null
systemctl restart zabbix-agent2 >/dev/null
done_step "6"

# Schritt 7: temporäre Tools entfernen
step "7 (Aufräumen)"
if [ "$OS" = "debian" ]; then
  apt-get remove -y -qq wget >/dev/null
  apt-get autoremove -y -qq >/dev/null
elif [ "$OS" = "rocky" ]; then
  dnf remove -y -q wget  >/dev/null
fi
done_step "7"

# Schritt 8: Reboot
step "8 (Neustart)"
echo -e "${YELLOW}System wird in 10 Sekunden neu gestartet... Abbrechen mit [CTRL+C]${RESET}"
sleep 10
reboot
