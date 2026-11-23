#!/bin/bash
# Upgrade Debian 12 (Bookworm) to Debian 13 (Trixie).
# This script has not been tested in production. Use it at your own risk.
# IT-Connect guide: https://www.it-connect.fr/linux-mise-a-niveau-de-debian-12-bookworm-vers-debian-13-trixie/
# Debian release notes: https://www.debian.org/releases/trixie/release-notes/upgrading.html
set -euo pipefail

STATE_FILE="/var/lib/debian-dist-upgrade-12-13.state"

if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root, for example with sudo." >&2
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    echo "Cannot identify the operating system: /etc/os-release is unavailable." >&2
    exit 1
fi

. /etc/os-release
CURRENT_VERSION="${VERSION_ID:-}"
CURRENT_CODENAME="${VERSION_CODENAME:-}"

confirm() {
    local prompt="$1"
    local answer

    read -rp "${prompt} [yes/no] " answer
    if [[ ! "${answer}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
}

require_release() {
    local expected_version="$1"
    local expected_codename="$2"

    if [ "${CURRENT_VERSION}" != "${expected_version}" ] || [ "${CURRENT_CODENAME}" != "${expected_codename}" ]; then
        echo "This phase requires Debian ${expected_version} (${expected_codename}); detected ${PRETTY_NAME:-unknown}." >&2
        exit 1
    fi
}

write_phase() {
    mkdir -p "$(dirname "${STATE_FILE}")"
    printf '%s\n' "$1" > "${STATE_FILE}"
}

show_pre_upgrade_checks() {
    echo
    echo "Held packages:"
    apt-mark showhold

    echo
    echo "Installed packages that may come from third-party sources:"
    apt list '?narrow(?installed, ?not(?origin(Debian)))' 2>/dev/null || true

    echo
    echo "Configured APT source files:"
    grep -RInE '^[[:space:]]*(deb[[:space:]]|URIs:|Suites:)' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
}

create_pre_upgrade_backup() {
    local timestamp
    local packages_file
    local backup_archive

    timestamp="$(date +%F_%H-%M-%S)"
    packages_file="/root/packages-before-upgrade-${timestamp}.list"
    backup_archive="/root/backup-before-upgrade-${timestamp}.tar.gz"

    echo "Saving the package selection to ${packages_file}."
    dpkg --get-selections '*' > "${packages_file}"

    echo "Creating the backup archive at ${backup_archive}. This may require substantial free disk space."
    tar --ignore-failed-read -czf "${backup_archive}" \
        --exclude='/home/*/.cache' \
        --exclude='/home/*/.local/share/Trash' \
        --exclude='/var/cache' \
        --exclude='/var/tmp' \
        --exclude='/tmp' \
        --exclude="${backup_archive}" \
        /etc /home /root /var/spool/cron /var/lib/dpkg /var/lib/apt/extended_states

    echo "Backup created. Copy it to another machine or external storage before continuing."
    confirm "Have you verified and secured this backup outside this server?"
}

reboot_for_next_phase() {
    echo "The current phase is saved. Reboot the server, then run this script again to continue."
    read -rp "Reboot now? [yes/no] " answer
    if [[ "${answer}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        systemctl reboot
    else
        echo "Reboot the server manually, then run this script again."
    fi
}

prepare_bookworm() {
    require_release "12" "bookworm"

    cat <<'EOF'
This script performs a major distribution upgrade. Services will be interrupted.
If you are connected remotely, make sure you have console or out-of-band recovery access.
Review Debian's release notes and confirm that your third-party packages support Trixie.
EOF

    echo "Root filesystem free space:"
    df -h /
    echo "System architecture: $(dpkg --print-architecture)"
    if [ "$(dpkg --print-architecture)" = "i386" ]; then
        echo "Debian 13 has limited i386 support. Review the architecture notes before continuing." >&2
        confirm "Have you verified that this i386 system can run Debian 13?"
    fi

    show_pre_upgrade_checks
    confirm "Have you reviewed held packages, third-party packages, and the APT sources?"
    confirm "Are you ready to create a full local backup before upgrading?"
    create_pre_upgrade_backup

    echo "Updating the current Debian 12 system. Review the simulated package changes before proceeding."
    apt-get update
    apt-get -s dist-upgrade --autoremove
    confirm "Proceed with the Debian 12 package upgrade?"
    apt-get dist-upgrade --autoremove -y

    write_phase "switch-sources"
    reboot_for_next_phase
}

switch_sources_to_trixie() {
    local timestamp
    local source_backup
    local source_file
    local found_bookworm=0
    local source_files=(/etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources)

    require_release "12" "bookworm"

    echo "Before continuing, ensure every third-party repository you intend to keep provides packages for Debian 13 (Trixie)."
    show_pre_upgrade_checks
    confirm "Have you rebooted after updating Debian 12 and checked third-party repository compatibility?"

    for source_file in "${source_files[@]}"; do
        if [ -f "${source_file}" ] && grep -q 'bookworm' "${source_file}"; then
            found_bookworm=1
        fi
    done

    if [ "${found_bookworm}" -ne 1 ]; then
        echo "No explicit Bookworm entries were found in the APT source files." >&2
        echo "Review and configure the Debian 13 sources manually, then inspect the files before continuing." >&2
        exit 1
    fi

    timestamp="$(date +%F_%H-%M-%S)"
    source_backup="/root/apt-sources-before-trixie-${timestamp}"
    mkdir -p "${source_backup}"
    if [ -f /etc/apt/sources.list ]; then
        cp -a /etc/apt/sources.list "${source_backup}/"
    fi
    if [ -d /etc/apt/sources.list.d ]; then
        cp -a /etc/apt/sources.list.d "${source_backup}/"
    fi
    echo "APT sources backed up to ${source_backup}."

    for source_file in "${source_files[@]}"; do
        if [ -f "${source_file}" ] && grep -q 'bookworm' "${source_file}"; then
            sed -i 's/bookworm/trixie/g' "${source_file}"
        fi
    done

    echo "Updated APT source files:"
    grep -RInE '^[[:space:]]*(deb[[:space:]]|URIs:|Suites:)' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

    if grep -RIn 'bookworm' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        echo "Some APT source files still contain 'bookworm'. Review them before continuing." >&2
        exit 1
    fi

    write_phase "upgrade-trixie"
}

upgrade_to_trixie() {
    require_release "12" "bookworm"

    echo "Refreshing package lists for Debian 13 and reviewing the proposed upgrade."
    apt-get update
    apt-get -s dist-upgrade --autoremove
    confirm "Proceed with the Debian 12 to Debian 13 package upgrade?"
    apt-get dist-upgrade --autoremove -y

    write_phase "verify-trixie"
    reboot_for_next_phase
}

cleanup_trixie() {
    require_release "13" "trixie"

    echo "Debian 13 is detected. Review each cleanup action before confirming it."
    apt-get autoremove --purge

    echo "Simulating removal of packages no longer available from configured repositories:"
    apt-get -s purge '~o'
    read -rp "Purge the packages listed above? [yes/no] " answer
    if [[ "${answer}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        apt-get purge '~o'
    else
        echo "Skipping removal of obsolete packages."
    fi

    apt-get autoclean

    read -rp "Run 'apt modernize-sources' to convert legacy APT source files to deb822 format? [yes/no] " answer
    if [[ "${answer}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        apt modernize-sources
    fi

    rm -f "${STATE_FILE}"
    echo "Debian 12 to Debian 13 upgrade workflow completed."
}

PHASE="prepare-bookworm"
if [ -f "${STATE_FILE}" ]; then
    PHASE="$(cat "${STATE_FILE}")"
fi

case "${PHASE}" in
    prepare-bookworm)
        prepare_bookworm
        ;;
    switch-sources)
        switch_sources_to_trixie
        upgrade_to_trixie
        ;;
    upgrade-trixie)
        upgrade_to_trixie
        ;;
    verify-trixie)
        cleanup_trixie
        ;;
    *)
        echo "Unknown upgrade phase '${PHASE}' in ${STATE_FILE}. Inspect the file and APT configuration before continuing." >&2
        exit 1
        ;;
esac
