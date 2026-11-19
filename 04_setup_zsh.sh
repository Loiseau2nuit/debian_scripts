#!/bin/bash
# Configure Zsh and Oh My Zsh for the user running this script.
set -euo pipefail

if [ "${EUID}" -eq 0 ]; then
    echo "Run this script as the user whose shell you want to configure, without sudo." >&2
    exit 1
fi

if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh is not installed. Run 01_install_starter.sh first." >&2
    exit 1
fi
ZSH_PATH="$(command -v zsh)"

# Set Zsh as the default shell for the current user.
chsh -s "${ZSH_PATH}"

# Install Oh My Zsh for the current user.
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Add personal aliases and startup commands to ~/.zshrc.
ZSHRC="${HOME}/.zshrc"
cat >> "${ZSHRC}" <<'EOF'

# some new adds of mine
alias ls='ls -ailsh --color'
alias grep='grep --color'
alias top='btop'
alias cat='batcat'
alias less='batcat'
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

cd ~
clear
fastfetch
echo "========================================================="
echo "Checking for upgrades ..."
apt list --upgradable 2>/dev/null | cat
echo "run 'sudo apt update && sudo apt full-upgrade -y' if any."
echo "========================================================="

chuck_cow
echo "========================================================="
EOF
