# Debian Starter Kit

A collection of personal Bash scripts for setting up and maintaining Debian servers. The scripts are independent utilities, not a complete unattended provisioning system. Review each script and adjust its configuration for your server before running it.

Some scripts install packages or change system configuration. Run only the scripts you need, and make sure you have a current backup before performing maintenance or distribution upgrades.

## Scripts

| Script | Purpose | Notes |
| --- | --- | --- |
| `01_install_starter.sh` | Prompts for a timezone (default: `Europe/Paris`) and installs common administration tools. | Run as root or with `sudo`. Prompts whether to install GLPI Agent and asks for the GLPI server URL. Set its version in `GLPI_AGENT_VERSION` near the top of the script. |
| `02_install_web_server.sh` | Installs Nginx, PHP 8.5 from the Sury repository, MariaDB, and Certbot. | Run as root or with `sudo`. Review the repository and package choices for your Debian release. The script includes interactive configuration steps. |
| `03_node_install_and_update.sh` | Checks for a Node.js update and can switch the `/opt/node` symlink to a downloaded release after SHA256 verification. | Review the paths and `MAIL_TO` setting at the top of the script. It expects Node.js to be installed under `/opt` and uses email notifications. |
| `04_setup_zsh.sh` | Sets Zsh as the default shell and configures Oh My Zsh and aliases for the current user. | Optional. Run after `01_install_starter.sh`, as the target user, without `sudo`. |
| `debian-dist-upgrade-11-12.sh` | Automates a Debian 11 (Bullseye) to Debian 12 (Bookworm) upgrade and reboots the server. | Legacy, release-specific script. Run only on Debian 11 after reviewing its commands and preparing a recovery plan. |
| `debian-dist-upgrade-12-13.sh` | Guides a Debian 12 (Bookworm) to Debian 13 (Trixie) upgrade through backup, package review, APT source migration, reboots, and cleanup. | Not tested in production; use at your own risk. Run as root. It saves its phase under `/var/lib` and must be run again after each reboot. Review third-party repository support and Debian's release notes before starting. |
| `20_easy_websites_maintenance.sh` | Intended to back up websites and create test clones with a database and Nginx configuration. | Marked **untested** in the script. Do not use on production systems. It assumes an Nginx layout with `sites-available` and `sites-enabled`. |

The Debian 12 to 13 upgrade workflow follows the [IT-Connect guide](https://www.it-connect.fr/linux-mise-a-niveau-de-debian-12-bookworm-vers-debian-13-trixie/) and the [official Debian release notes](https://www.debian.org/releases/trixie/release-notes/upgrading.html).

## Suggested workflow

1. Clone the repository and review the scripts you plan to use.
2. Run `01_install_starter.sh` first if you want the common system packages.
3. Optionally run `04_setup_zsh.sh` as the user whose shell you want to configure. Do not run it with `sudo`.
4. Run `02_install_web_server.sh` or `03_node_install_and_update.sh` only if you need those components, after reviewing their configuration and prompts.
5. For a distribution upgrade, use only the script matching the current Debian release: `debian-dist-upgrade-11-12.sh` for Debian 11, or `debian-dist-upgrade-12-13.sh` for Debian 12. The latter pauses for reboots and must be run again after each reboot. Treat `20_easy_websites_maintenance.sh` as experimental and inspect it carefully before use.

## Running a script

Make the chosen script executable:

```bash
chmod +x 01_install_starter.sh
```

Run system-level scripts with root privileges, for example:

```bash
sudo ./01_install_starter.sh
```

Run the Zsh setup script as the target user, without `sudo`:

```bash
chmod +x 04_setup_zsh.sh
./04_setup_zsh.sh
```

Several scripts are interactive. Keep a terminal session open and read each prompt before answering. After installation, consult the documentation for the packages and services you choose to use; installing a package does not necessarily configure or secure it.

## Project status

These scripts are maintained for personal use and may require changes for a different Debian release or server setup. The repository currently has no automated test suite. The 11-to-12 upgrade script is release-specific, the 12-to-13 upgrade script has not been tested in production and is used at the user's own risk, and the website maintenance script is explicitly marked untested.
