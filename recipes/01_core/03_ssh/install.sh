#!/bin/bash
set -euo pipefail

source "config.sh"


arch-chroot /mnt pacman -S --noconfirm \
   openssh

SSHD_CONFIG_PATH="/mnt/etc/ssh/sshd_config"

sed -i -E 's/^#?(PermitRootLogin).*/\1 prohibit-password/' "$SSHD_CONFIG_PATH"
sed -i -E 's/^#?(PasswordAuthentication).*/\1 yes/' "$SSHD_CONFIG_PATH"
sed -i -E 's/^#?(PubkeyAuthentication).*/\1 yes/' "$SSHD_CONFIG_PATH"
sed -i -E 's/^#?(PermitEmptyPasswords).*/\1 no/' "$SSHD_CONFIG_PATH"

arch-chroot /mnt systemctl enable sshd.service