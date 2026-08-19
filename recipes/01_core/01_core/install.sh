#!/bin/bash

source "config.sh"

get_total_memory_mb() {
   local mem_kib;
   mem_kib=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}');

   echo $((mem_kib / 1024))
}

get_total_memory_human() {
   free -h | grep 'Mem:' | awk '{print $2}'
}


TOTAL_RAM_MB=$(get_total_memory_mb)
TOTAL_RAM_HUMAN=$(get_total_memory_human)

SWAP_SIZE_MB="$TOTAL_RAM_MB"

MAIN_PART_EFI="${MAIN_DISK_ID}-part1"
MAIN_PART_ZFS="${MAIN_DISK_ID}-part2" 
SWAP_DEVICE=""

echo "partitioning main disk: ${MAIN_DISK_ID}"
sgdisk --zap-all "${MAIN_DISK_ID}"
sgdisk -n1:1M:+4G -t1:EF00 "${MAIN_DISK_ID}"

if [[ "${SWAP_STRATEGY:-main}" == "main" ]]; then
   echo "swap strategy: main disk partition"
   sgdisk -n2:0:+${SWAP_SIZE_MB}M -t2:8200 "${MAIN_DISK_ID}"
   sgdisk -n3:0:0 -t3:BF00 "${MAIN_DISK_ID}"
   
   SWAP_DEVICE="${MAIN_DISK_ID}-part2"
   MAIN_PART_ZFS="${MAIN_DISK_ID}-part3"
else
   if [[ -z "${SWAP_DISK_ID}" ]]; then
      echo "fatal: swap strategy is 'separate' but no disk defined in config!"
      exit 1
   fi
   
   echo "swap strategy: separate disk (${SWAP_DISK_ID})"
   
   sgdisk -n2:0:0 -t2:BF00 "${MAIN_DISK_ID}"
   
   echo "partitioning swap disk: ${SWAP_DISK_ID}"
   sgdisk --zap-all "${SWAP_DISK_ID}"
   sgdisk -n1:0:+${SWAP_SIZE_MB}M -t1:8200 "${SWAP_DISK_ID}"
   
   SWAP_DEVICE="${SWAP_DISK_ID}-part1"
fi

partprobe "${MAIN_DISK_ID}"
if [[ "${SWAP_STRATEGY}" == "separate" ]]; then
   partprobe "${SWAP_DISK_ID}"
fi

udevadm settle

mkfs.vfat -F 32 -n EFI "${MAIN_PART_EFI}"
efi_part_uuid=$(blkid -s PARTUUID -o value "${MAIN_PART_EFI}")

# make the root zfs pool
zpool create -f \
   -o ashift=12 \
   -o autotrim=on \
   -O compression="${ZFS_COMPRESSION:-lz4}" \
   -O acltype=posixacl \
   -O xattr=sa \
   -O relatime=on \
   -O mountpoint=none \
   -m none \
   -R /mnt \
      rpool \
      "${MAIN_PART_ZFS}"

if [[ "${ZFS_SYNC_DISABLED}" == "true" ]]; then
   echo "warning: disabling sync writes on rpool/ROOT"

   zfs set sync=disabled rpool
fi

mkdir -p "${ZFS_KEYS_DIRECTORY}"
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_root_${BE_NAME}_root.key" bs=32 count=1 status=progress
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_root_${BE_NAME}_var.key" bs=32 count=1 status=progress
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_data.key" bs=32 count=1 status=progress
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_data_home.key" bs=32 count=1 status=progress
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_data_home_root.key" bs=32 count=1 status=progress
dd if=/dev/random of="${ZFS_KEYS_DIRECTORY}/rpool_data_home_${SUDO_USER}.key" bs=32 count=1 status=progress

chmod 400 ${ZFS_KEYS_DIRECTORY}/*

zfs create \
   -o mountpoint=none \
   -o canmount=noauto \
      "rpool/ROOT"

zfs create \
   -o mountpoint=none \
   -o canmount=noauto \
      "rpool/ROOT/${BE_NAME}"

zfs create \
   -o mountpoint=/ \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_root_${BE_NAME}_root.key" \
      "rpool/ROOT/${BE_NAME}/root"

echo -n "${ZFS_BOOT_PASSPHRASE}" | zfs create \
   -o mountpoint=/boot \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keylocation=prompt \
   -o keyformat=passphrase \
      "rpool/ROOT/${BE_NAME}/boot"

mkdir -p "/mnt/etc/zfs/keys"

host_boot_keyfile="${ZFS_KEYS_DIRECTORY}/boot.key"
echo -n "${ZFS_BOOT_PASSPHRASE}" > "${host_boot_keyfile}"
chmod 600 "${host_boot_keyfile}"

cp "${host_boot_keyfile}" "/mnt/etc/zfs/keys/boot.key"

zfs change-key -o keylocation="file:///etc/zfs/keys/boot.key" "rpool/ROOT/${BE_NAME}/boot"

zfs unmount "rpool/ROOT/${BE_NAME}/boot"
zfs unload-key "rpool/ROOT/${BE_NAME}/boot"

zfs create \
   -o mountpoint=/var \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_root_${BE_NAME}_var.key" \
   -o com.sun:auto-snapshot=false \
      "rpool/ROOT/${BE_NAME}/var"

zfs create \
   -o mountpoint=none \
   -o canmount=on \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_data.key" \
      "rpool/DATA"

zfs create \
   -o mountpoint=/home \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_data_home.key" \
      "rpool/DATA/home"

zfs create \
   -o mountpoint=/root \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_data_home_root.key" \
      "rpool/DATA/home/root"

zfs create \
   -o mountpoint="/home/${SUDO_USER}" \
   -o canmount=on \
   -o readonly=off \
   -o encryption=on \
   -o keyformat=raw \
   -o keylocation="file://${ZFS_KEYS_DIRECTORY}/rpool_data_home_${SUDO_USER}.key" \
      "rpool/DATA/home/${SUDO_USER}"



zfs unmount -a

zpool export rpool
zpool import rpool -f -R /mnt

echo -n "${ZFS_BOOT_PASSPHRASE}" | zfs load-key "rpool/ROOT/${BE_NAME}/boot"
zfs load-key -a
zfs mount -R "rpool/ROOT/${BE_NAME}"
zfs mount -R "rpool/DATA"

mount | grep zfs


mkdir -p /mnt/efi
mkdir -p /mnt/boot
mkdir -p "/mnt/${ZFS_KEYS_DIRECTORY}"
cp ${ZFS_KEYS_DIRECTORY}/* "/mnt/${ZFS_KEYS_DIRECTORY}/"

mount "${MAIN_PART_EFI}" /mnt/efi


mkdir -p /mnt/etc/zfs/
zpool set cachefile=/etc/zfs/zpool.cache rpool
cp -v /etc/zfs/zpool.cache /mnt/etc/zfs

pacstrap /mnt \
   base base-devel \
   linux-firmware \
\
   iptables-nft \
   mkinitcpio \
\
   neovim \
   git

genfstab -U -p /mnt >> /mnt/etc/fstab


cp -v /etc/resolv.conf /mnt/etc

echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd

echo \# > /mnt/etc/fstab

sed -i.bak \
   -e 's/-march=x86-64 -mtune=generic/-march=native/' \
   -e '/^CXXFLAGS=/i RUSTFLAGS="-C opt-level=2 -C target-cpu=native"\n' \
   -e "s/^#MAKEFLAGS=.*/MAKEFLAGS=\"-j$(nproc)\"/" \
   -e 's/^COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q --threads=0 -)/' \
   -e 's/^COMPRESSXZ=.*/COMPRESSXZ=(xz -c -z --threads=0 -)/' \
   /mnt/etc/makepkg.conf

sed -i.bak \
   -e 's/^#\?Color/Color\nILoveCandy/' \
   -e "s/^#\?ParallelDownloads.*/ParallelDownloads = $(nproc)/" \
   -e "/\[multilib\]/,/Include/"'s/^#//' \
   /mnt/etc/pacman.conf

sed -i.bak \
   -E 's/^#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL$)/\1/' \
   /mnt/etc/sudoers

sed -i.bak \
   -E "s/^#\s*(${LOCALE}\s+UTF-8)/\1/" \
   /mnt/etc/locale.gen


arch-chroot /mnt useradd -m $SUDO_USER
arch-chroot /mnt usermod -aG wheel $SUDO_USER
arch-chroot /mnt id $SUDO_USER
echo "$SUDO_USER:$SUDO_USER_PASSWORD" | arch-chroot /mnt chpasswd

arch-chroot /mnt useradd -m $RESTRICTED_USER
arch-chroot /mnt id $RESTRICTED_USER
echo "$RESTRICTED_USER:$RESTRICTED_USER_PASSWORD" | arch-chroot /mnt chpasswd

arch-chroot /mnt usermod -aG wheel root


arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf


ln -sf /mnt/usr/share/zoneinfo/America/New_York /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt timedatectl set-ntp true
arch-chroot /mnt timedatectl status


arch-chroot /mnt pacman -Syyu --noconfirm

arch-chroot /mnt <<'EOF'
pacman-key --init
pacman-key --populate archlinux

cd ~
curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo

yes | ./cachyos-repo.sh

if ! grep -q "\[cachyos\]" /etc/pacman.conf; then
   mkdir -p /etc/pacman.d

   echo "" >> /etc/pacman.conf
   echo "[cachyos]" >> /etc/pacman.conf
   echo "Include = /etc/pacman.d/cachyos-mirrorlist" >> /etc/pacman.conf
fi

cd ..
rm -rf cachyos-repo*
EOF


arch-chroot /mnt pacman -Syyu --noconfirm

kms_mod=""

if check_cpu "amd"; then
   arch-chroot /mnt pacman -S --noconfirm amd-ucode

   kms_mod="amdgpu"
elif check_cpu "intel"; then
   arch-chroot /mnt pacman -S --noconfirm intel-ucode

   kms_mod="i915"
fi

arch-chroot /mnt pacman -S --noconfirm \
\
   sudo \
   wget \
   yay \
   efibootmgr \
   zfs-utils \
\
   mesa \
   ttf-sourcecodepro-nerd \
\
   apparmor \
\
   iwd \
   dhcpcd \
   networkmanager \
\
   ananicy-cpp \
   bpftune \
\
   zsh \
   atuin \
   tmux \
   fzf \
\
   chwd \
   cachyos-rate-mirrors


arch-chroot /mnt usermod -s /usr/bin/zsh root
arch-chroot /mnt usermod -s /usr/bin/zsh $SUDO_USER
arch-chroot /mnt usermod -s /usr/bin/zsh $RESTRICTED_USER

files_to_add=$(find "$ZFS_KEYS_DIRECTORY" -maxdepth 1 -type f -printf '%p ')
[ -n "$files_to_add" ] && files_to_add=" $files_to_add"

sed -i.bak \
   -e "s/^[[:space:]]*MODULES=(/MODULES=(${kms_mod} /" \
   -e 's/^[[:space:]]*HOOKS=(.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block zfs filesystems)/' \
   -e "/^[[:space:]]*FILES=/ s|)| /etc/shadow /etc/zfs/zpool.cache${files_to_add})|" \
   /mnt/etc/mkinitcpio.conf

echo "KEYMAP=us" > /mnt/etc/vconsole.conf

echo "installing selected kernel: ${KERNEL}"
arch-chroot /mnt pacman -S --noconfirm \
   "$KERNEL" "${KERNEL}-headers" "${KERNEL}-zfs"

arch-chroot /mnt mkinitcpio -P

if check_gpu "nvidia"; then
   arch-chroot /mnt pacman -S --noconfirm "${KERNEL}-nvidia-open" opencl-nvidia nvidia-utils
elif check_gpu "amd"; then 
   arch-chroot /mnt pacman -S --noconfirm opencl-mesa
fi

if [[ -n "${ZFS_ARC_MAX}" ]] && [[ "${ZFS_ARC_MAX}" != "0" ]]; then
   echo "setting zfs arc max to ${ZFS_ARC_MAX} bytes"
   echo "options zfs zfs_arc_max=${ZFS_ARC_MAX}" > /mnt/etc/modprobe.d/zfs.conf
fi

if [[ "${SYS_IO_SCHEDULER}" != "none" ]] && [[ -n "${SYS_IO_SCHEDULER}" ]]; then
   echo "enforcing i/o scheduler: ${SYS_IO_SCHEDULER}"

   cat > /mnt/etc/udev/rules.d/60-iosched.rules <<EOF
ACTION=="add|change", KERNEL=="sd[a-z]*|nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="${SYS_IO_SCHEDULER}"
EOF
fi

if [[ "${SYS_AGGRESSIVE_SHUTDOWN}" == "true" ]]; then
   echo "tuning systemd for aggressive shutdown"

   sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/' /mnt/etc/systemd/system.conf
   sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/' /mnt/etc/systemd/user.conf
fi

echo "applying sysctl tuning..."
cat > /mnt/etc/sysctl.d/99-installer-tuning.conf <<EOF
vm.swappiness = ${SYS_SWAPPINESS:-10}
vm.vfs_cache_pressure = ${SYS_VFS_CACHE_PRESSURE:-100}
EOF


arch-chroot /mnt <<EOF
mkdir -p /etc/ananicy.d
rm -rf /etc/ananicy.d
git clone https://github.com/CachyOS/ananicy-rules.git /etc/ananicy.d
rm -rf /etc/ananicy.d/.git
EOF

arch-chroot /mnt <<EOF
pacman -S --noconfirm \
   ly

pacman -S --noconfirm \
   pipewire \
   pipewire-alsa \
   pipewire-pulse \
   pipewire-jack
EOF


arch-chroot /mnt <<EOF
systemctl enable zfs-import.target
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-share
systemctl enable zfs-zed
EOF


zpool set bootfs="rpool/ROOT/${BE_NAME}" rpool
zfs set org.zfsbootmenu:rootfs="rpool/ROOT/${BE_NAME}/root" "rpool/ROOT/${BE_NAME}"
zfs set org.zfsbootmenu:bootfs="rpool/ROOT/${BE_NAME}/boot" "rpool/ROOT/${BE_NAME}"
zfs set org.zfsbootmenu:kernel="vmlinuz-${KERNEL}" "rpool/ROOT/${BE_NAME}"
zfs set org.zfsbootmenu:initramfs="initramfs-${KERNEL}.img" "rpool/ROOT/${BE_NAME}"
zfs set org.zfsbootmenu:cmdopts="${KERNEL_OPTS}" "rpool/ROOT/${BE_NAME}/boot"


arch-chroot /mnt sh -c "zgenhostid -f > /etc/hostid"
echo "$HOSTNAME" > /mnt/etc/hostname
echo "127.0.0.1 localhost" >> /mnt/etc/hosts
echo "::1       localhost" >> /mnt/etc/hosts
echo "127.0.0.1 $HOSTNAME.localdomain $HOSTNAME" >> /mnt/etc/hosts


mkdir -p /mnt/efi/EFI/zbm

arch-chroot /mnt wget https://github.com/desplmfao/zquickinit/releases/download/unstable/zquickinit.efi -O /efi/EFI/zbm/zquickinit.efi

# if you have your internet being fucked over by the government with anything in checksum checks, thats your fault, not mine
ZQ_HASH=$(curl -s "https://api.github.com/repos/desplmfao/zquickinit/releases/tags/unstable" \
   | grep -o '"digest": "[^"]*"' \
   | head -n 1 \
   | cut -d'"' -f4 \
   | cut -d':' -f2)

REAL_ZQ_HASH=$(arch-chroot /mnt sha256sum /efi/EFI/zbm/zquickinit.efi | awk '{print $1}')

if [ -z "$ZQ_HASH" ]; then
   echo "warning: could not fetch zquickinit hash from github. skipping verification."
elif [ "$ZQ_HASH" != "$REAL_ZQ_HASH" ]; then
   echo "fatal: zquickinit.efi checksum mismatch!"

   echo "expected: $ZQ_HASH"
   echo "got:      $REAL_ZQ_HASH"

   exit 1
fi

mkdir -p /mnt/efi/EFI/BOOT
mkdir -p /mnt/efi/limine
arch-chroot /mnt pacman -S --noconfirm limine
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/BOOT/

arch-chroot /mnt efibootmgr --create \
   --disk "${MAIN_DISK_ID}" \
   --part 1 \
   --label "shitlinux" \
   --loader /EFI/BOOT/BOOTX64.EFI \
   --unicode \
   --verbose

cat > /mnt/efi/limine/limine.conf << 'EOF'
term_palette: 1e1e2e;f38ba8;a6e3a1;f9e2af;89b4fa;f5c2e7;94e2d5;cdd6f4
term_palette_bright: 585b70;f38ba8;a6e3a1;f9e2af;89b4fa;f5c2e7;94e2d5;cdd6f4
term_background: 1e1e2e
term_foreground: cdd6f4
term_background_bright: 585b70
term_foreground_bright: cdd6f4

timeout: 240
hash_mismatch_panic: no
remember_last_entry: yes
interface_branding_colour: 6
interface_resolution: 1920x1080
verbose: no
quiet: no
editor_enabled: yes
editor_highlighting: yes
editor_validation: yes
interface_help_hidden: no
randomise_memory: no
randomise_hhdm_base: yes

/zq
   protocol: efi
   path: boot():/EFI/zbm/zquickinit.efi
EOF


if [[ -n "$SWAP_DEVICE" ]]; then
   echo "configuring cryptswap on ${SWAP_DEVICE}..."
   swap_part_uuid=$(blkid -s PARTUUID -o value "$SWAP_DEVICE")
   
   if [[ -z "$swap_part_uuid" ]]; then
      echo "error: failed to get PARTUUID for swap device ${SWAP_DEVICE}"

      exit 1
   fi
   
   echo "cryptswap PARTUUID=${swap_part_uuid} /dev/urandom swap,plain,offset=1024,cipher=aes-xts-plain64,size=512" > /mnt/etc/crypttab
   echo "/dev/mapper/cryptswap none swap sw 0 0" >> /mnt/etc/fstab
   
   echo "cryptswap configured successfully."
fi


cat > /mnt/usr/local/bin/zfs-mount-all.sh << 'EOF'
#!/bin/bash

zfs load-key -a
zfs mount -a

EOF

cat > /mnt/etc/systemd/system/zfs-mount-all.service << 'EOF'
[Unit]
Description=ensure all zfs datasets are mounted on boot
DefaultDependencies=no
After=zfs-import.target
Before=ly@tty7.service user@.service zfs.target multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/zfs-mount-all.sh

[Install]
WantedBy=zfs.target
EOF

cat > /mnt/etc/systemd/system/efi.mount << EOF
[Unit]
Description=Mount EFI System Partition
DefaultDependencies=no
After=zfs-import.target
Before=local-fs.target

[Mount]
What=/dev/disk/by-partuuid/${efi_part_uuid}
Where=/efi
Type=vfat
Options=defaults,noatime,x-systemd.make-nofollow

[Install]
WantedBy=local-fs.target
EOF

arch-chroot /mnt <<EOF
chmod +x /usr/local/bin/zfs-mount-all.sh

systemctl enable zfs-mount-all
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable ananicy-cpp
systemctl enable bpftune
systemctl enable efi.mount

systemctl disable wpa_supplicant
EOF


# archie: ensure directory exists to prevent creation error
mkdir -p /mnt/etc/NetworkManager/conf.d
cat > /mnt/etc/NetworkManager/conf.d/wifi_backend.conf << 'EOF'
[device]
wifi.backend=iwd
EOF