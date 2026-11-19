#!/bin/bash
# some usefull packages when it comes to dealing with a debien server
#
set -euo pipefail

if [ "$(whoami)" != "root" ]; then
    SUDO=sudo
else
    SUDO=""
fi

# Set the timezone (run 'timedatectl list-timezones' to see available values).
DEFAULT_TIMEZONE="Europe/Paris"
while true; do
    read -rp "Timezone [${DEFAULT_TIMEZONE}] (see 'timedatectl list-timezones'): " TIMEZONE_INPUT
    TIMEZONE="${TIMEZONE_INPUT:-$DEFAULT_TIMEZONE}"

    if timedatectl list-timezones | grep -Fx -- "$TIMEZONE" >/dev/null; then
        break
    fi

    echo "Unknown timezone. Please enter a valid timezone name." >&2
done

${SUDO} timedatectl set-timezone "$TIMEZONE"

# some might already be installed, depending on your distribution
${SUDO} apt-get update
${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get -y install apticron btop bat ccze cowsay curl dnsutils fail2ban fastfetch fortunes iptables iptables-persistent netcat-openbsd net-tools parted python3-pygments rkhunter rsync screen sudo tmux unzip whois zip zsh

# glpi-agent
read -rp "Do you want to install glpi-agent? [yes/no] " install_glpi
if [[ "$install_glpi" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    read -rp "GLPI server URL (e.g. http://glpi.example.tld/front/inventory.php): " glpi_server
    while [ -z "${glpi_server}" ]; do
        read -rp "Server URL is required. GLPI server URL: " glpi_server
    done
    cd
    wget https://github.com/glpi-project/glpi-agent/releases/download/1.21/glpi-agent-1.21-linux-installer.pl
    chmod +x glpi-agent-1.21-linux-installer.pl
    ${SUDO} perl glpi-agent-1.21-linux-installer.pl -s "${glpi_server}" --runnow --install
else
    echo "Skipping glpi-agent installation."
fi
