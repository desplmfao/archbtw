#!/bin/bash

check_cpu() {
   local vendor_id

   if [[ "$1" == "amd" ]]; then
      vendor_id="AuthenticAMD"
   elif [[ "$1" == "intel" ]]; then
      vendor_id="GenuineIntel"
   else
      return 1
   fi

   grep -q "$vendor_id" /proc/cpuinfo
}

check_gpu() {
   local vendor_pattern

   case "$1" in
      amd)
         vendor_pattern='VGA.*\(AMD\|ATI\)'
         ;;
      intel)
         vendor_pattern='VGA.*Intel'
         ;;
      nvidia)
         vendor_pattern='VGA.*NVIDIA'
         ;;
      *)
         return 1
         ;;
   esac

   lspci | grep -qiE "$vendor_pattern"
}


export MAIN_DISK_ID="/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-sata0"
export MAIN_DISK_EFI_PART_ID="${MAIN_DISK_ID}-part1"
export MAIN_DISK_ZFS_PART_ID="${MAIN_DISK_ID}-part2"

export SWAP_STRATEGY="main" 
export SWAP_DISK_ID=""

export BE_NAME="arch"

export HOSTNAME="archlinux"
export LOCALE="en_US.UTF-8"
export TIMEZONE="America/New_York"

export KERNEL="linux-cachyos"

export SUDO_USER="user"
export SUDO_USER_PASSWORD="root"

export RESTRICTED_USER="cuck"
export RESTRICTED_USER_PASSWORD="cuck"

export ROOT_PASSWORD="root"

export ZFS_BE_NAME="arch"
export ZFS_POOL_NAME="rpool"
export ZFS_BOOT_PASSPHRASE="password"
export ZFS_COMPRESSION="lz4"
export ZFS_ARC_MAX="0"
export ZFS_SYNC_DISABLED="false"
export ZFS_SNAPSHOT_POLICY="production" # production, daily, none
export ZFS_SCRUB_ENABLED="true"

export ZFS_KEYS_DIRECTORY="/etc/zfs/keys"

export SYS_THP_POLICY="madvise" # always, madvise, never
export SYS_IO_SCHEDULER="none"  # none, kyber, bfq, mq-deadline
export SYS_AGGRESSIVE_SHUTDOWN="false"
export SYS_SWAPPINESS="10"
export SYS_VFS_CACHE_PRESSURE="100"
export SYS_DISABLE_IPV6="false"

export DOTFILES_REPO=""
export GITHUB_USERNAME_KEYS=""

KERNEL_OPTS="rw console=tty0 earlyprintk=vga zfs_force=1"
KERNEL_OPTS="$KERNEL_OPTS apparmor=1 security=apparmor"

KERNEL_OPTS="$KERNEL_OPTS transparent_hugepage=${SYS_THP_POLICY}"

if [[ "${SYS_DISABLE_IPV6}" == "true" ]]; then
   KERNEL_OPTS="$KERNEL_OPTS ipv6.disable=1"
fi

if check_cpu "amd"; then
   KERNEL_OPTS="$KERNEL_OPTS amd_iommu=on iommu=pt"
elif check_cpu "intel"; then
   KERNEL_OPTS="$KERNEL_OPTS intel_iommu=on iommu=pt"
fi

export KERNEL_OPTS