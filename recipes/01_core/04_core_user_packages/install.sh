#!/bin/bash
set -euo pipefail

source "config.sh"


arch-chroot /mnt <<EOF
pacman -S --noconfirm \
   plasma-desktop \
\
   kscreen \
   powerdevil \
   plasma-nm \
   plasma-pa \
\
   polkit-kde-agent \
   kio-extras \
   kde-gtk-config \
   breeze-gtk \
   xdg-desktop-portal-kde \
   qt5-wayland \
   qt6-wayland \
\
\
   alacritty \
\
\
   dolphin \
\
   ffmpegthumbs \
\
\
   ark \
\
   arj \
   unrar \
   lrzip \
   lzop \
   zstd \
   7zip \
\
\
   kate \
\
   firefox \
\
   vlc \
   vlc-plugins-all
EOF