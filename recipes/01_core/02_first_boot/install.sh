#!/bin/bash
set -euo pipefail


source "config.sh"

cat > /mnt/usr/local/bin/first-boot.sh << EOF
#!/bin/bash
user="${SUDO_USER}"
user_home="/home/\$user"
gh_keys_user="${GITHUB_USERNAME_KEYS}"
dotfiles_repo="${DOTFILES_REPO}"

loginctl enable-linger "\$user"

mkdir -p "\$user_home/.zsh"
mkdir -p "\$user_home/.config"
mkdir -p "\$user_home/.cache"
mkdir -p "\$user_home/.local"
mkdir -p "\$user_home/Documents"
mkdir -p "\$user_home/Downloads"
mkdir -p "\$user_home/Desktop"

chown -R "\$user:\$user" "\$user_home"

chmod -R 1777 "\$user_home/.config"
chmod -R 1777 "\$user_home/.cache"
chmod -R 1777 "\$user_home/.local"

echo "\$user:100000:65536" > /etc/subuid
echo "\$user:100000:65536" > /etc/subgid

if [[ -n "\$gh_keys_user" ]]; then
   echo "fetching ssh keys for github user: \$gh_keys_user"
   mkdir -p "\$user_home/.ssh"

   if curl -s "https://github.com/\${gh_keys_user}.keys" -o "\$user_home/.ssh/authorized_keys"; then
      chmod 700 "\$user_home/.ssh"
      chmod 600 "\$user_home/.ssh/authorized_keys"
      chown -R "\$user:\$user" "\$user_home/.ssh"

      echo "ssh keys installed successfully."
   else
      echo "warning: failed to fetch keys for \$gh_keys_user"
   fi
fi

if [[ -n "\$dotfiles_repo" ]]; then
   echo "cloning dotfiles from: \$dotfiles_repo"

   if git clone "\$dotfiles_repo" "\$user_home/dotfiles_temp"; then
      rsync -av "\$user_home/dotfiles_temp/" "\$user_home/"
      rm -rf "\$user_home/dotfiles_temp"
      chown -R "\$user:\$user" "\$user_home"

      echo "custom dotfiles applied"
   else
      echo "fatal: failed to clone dotfiles repo"
   fi
else
   echo 'eval "\$(atuin init zsh)"' >> "\$user_home/.zshrc"
fi


systemctl disable first-boot.service
systemctl enable --now ly@tty7.service


rm /etc/systemd/system/first-boot.service
rm /usr/local/bin/first-boot.sh


reboot
EOF

cat > /mnt/etc/systemd/system/first-boot.service << 'EOF'
[Unit]
Description=one-time post-installation setup
After=network-online.target user@.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF


arch-chroot /mnt <<EOF
chmod +x /usr/local/bin/first-boot.sh

systemctl enable first-boot
EOF