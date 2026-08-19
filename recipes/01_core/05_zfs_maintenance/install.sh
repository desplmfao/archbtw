#!/bin/bash
set -euo pipefail


source "config.sh"

if [[ "${ZFS_SNAPSHOT_POLICY}" == "none" ]]; then
   echo "zfs snapshot policy is 'none'. skipping sanoid installation"

   exit 0
fi

echo "enabling temporary passwordless sudo for installation..."
cat > /mnt/etc/sudoers.d/00_installer_temp <<EOF
%wheel ALL=(ALL) NOPASSWD: ALL
EOF

arch-chroot /mnt \
   runuser -u "$SUDO_USER" -- yay -S --noconfirm sanoid

mkdir -p /mnt/etc/sanoid

if [[ "${ZFS_SNAPSHOT_POLICY}" == "production" ]]; then
   cat > /mnt/etc/sanoid/sanoid.conf <<EOF
[rpool/ROOT/${BE_NAME}]
   use_template = production
   recursive = yes
   process_children_only = yes

[rpool/DATA]
   use_template = production
   recursive = yes
   process_children_only = yes

[template_production]
   frequently = 0
   hourly = 36
   daily = 30
   monthly = 3
   yearly = 0
   autosnap = yes
   autoprune = yes
EOF
elif [[ "${ZFS_SNAPSHOT_POLICY}" == "daily" ]]; then
   cat > /mnt/etc/sanoid/sanoid.conf <<EOF
[rpool/ROOT/${BE_NAME}]
   use_template = daily_only
   recursive = yes
   process_children_only = yes

[rpool/DATA]
   use_template = daily_only
   recursive = yes
   process_children_only = yes

[template_daily_only]
   frequently = 0
   hourly = 0
   daily = 30
   monthly = 3
   yearly = 0
   autosnap = yes
   autoprune = yes
EOF
fi

arch-chroot /mnt systemctl enable sanoid.timer

if [[ "${ZFS_SCRUB_ENABLED}" == "true" ]]; then
   echo "enabling monthly zfs scrub timer..."

   arch-chroot /mnt systemctl enable zfs-scrub-monthly@rpool.timer
else
   echo "zfs scrub timer disabled in config."
fi

echo "revoking temporary passwordless sudo..."
rm /mnt/etc/sudoers.d/00_installer_temp