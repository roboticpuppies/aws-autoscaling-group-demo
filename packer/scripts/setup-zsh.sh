#!/bin/bash
set -euo pipefail

echo "=== Setting up ZSH and OhMyZSH ==="

apt-get install -y zsh git curl

# Install OhMyZSH for ubuntu user (non-interactive)
su - ubuntu -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

# Configure .zshrc for ubuntu user
ZSHRC="/home/ubuntu/.zshrc"

# Set plugins
sed -i 's/^plugins=.*/plugins=(history docker docker-compose)/' "$ZSHRC"

# Enable automatic updates (non-interactive)
sed -i '/^# zstyle.*mode auto/c\zstyle ":omz:update" mode auto' "$ZSHRC"
# If the line doesn't exist, add it before the source line
if ! grep -q 'zstyle ":omz:update" mode auto' "$ZSHRC"; then
  sed -i '/^source \$ZSH\/oh-my-zsh.sh/i zstyle ":omz:update" mode auto' "$ZSHRC"
fi

# Change default shell to zsh for ubuntu user
chsh -s "$(which zsh)" ubuntu

echo "=== ZSH and OhMyZSH setup complete ==="
