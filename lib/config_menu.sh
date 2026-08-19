#!/bin/bash

source "lib/disk_utils.sh"

update_config_value() {
   local key="$1"
   local new_value="$2"

   local escaped_value
   escaped_value=$(echo "$new_value" | sed 's|/|\\/|g')

   sed -i -E "s|^(export ${key}=\").*(\").*$|\1${escaped_value}\2|" config.sh

   source config.sh
}

edit_config() {
   while true; do
      clear

      gum style --border double --margin "1" --padding "1" --border-foreground 212 \
         "configuration menu" "select a category to configure"

      local choice
      choice=$(gum choose \
         "disk" \
         "accounts" \
         "network" \
         "advanced" \
         "save and return to menu")

      case "$choice" in
         "disk")
            edit_config_disks
            ;;
         "accounts")
            edit_config_users
            ;;
         "network")
            edit_config_network
            ;;
         "advanced")
            edit_config_advanced
            ;;
         "save and return to menu" | *)
            break
            ;;
      esac
   done

   source config.sh
}

edit_config_disks() {
   clear

   gum style --border normal --margin "1" --padding "1" "disk setup"

   gum style --bold "select the primary installation disk"
   echo "this disk will be COMPLETELY ERASED for zfs root"
   echo "format: id (size) | model | [detected filesystems]"

   local selected_entry
   selected_entry=$(list_disks_by_id | gum choose --height 15 --header "choose a disk")
    
   local disk_id_path=""

   if [[ -n "$selected_entry" ]]; then
      local short_id
      short_id=$(echo "$selected_entry" | awk '{print $1}')
      
      disk_id_path="/dev/disk/by-id/${short_id}"
        
      update_config_value "MAIN_DISK_ID" "$disk_id_path"
      gum style --foreground 2 "set MAIN_DISK_ID to ${disk_id_path}"
   else
      gum style --foreground 3 "skipped disk selection"
      return
   fi

   echo
   gum style --bold "swap configuration"
   local swap_choice
   swap_choice=$(gum choose --header "where should the cryptswap reside?" "main drive (partition)" "separate drive")

   if [[ "$swap_choice" == "main drive (partition)" ]]; then
      update_config_value "SWAP_STRATEGY" "main"
      update_config_value "SWAP_DISK_ID" ""
      gum style --foreground 2 "swap set to main drive"
   else
      update_config_value "SWAP_STRATEGY" "separate"
      
      echo
      gum style --bold "select the disk for swap"
      echo "this disk will be COMPLETELY ERASED for swap"

      local main_disk_short
      main_disk_short=$(basename "$disk_id_path")
      
      local swap_disk_entry
      swap_disk_entry=$(list_disks_by_id | grep -v "$main_disk_short" | gum choose --height 15 --header "choose a separate disk for swap")

      if [[ -n "$swap_disk_entry" ]]; then
         local swap_short_id
         swap_short_id=$(echo "$swap_disk_entry" | awk '{print $1}')
         local swap_disk_path="/dev/disk/by-id/${swap_short_id}"
         
         update_config_value "SWAP_DISK_ID" "$swap_disk_path"
         gum style --foreground 2 "set SWAP_DISK_ID to ${swap_disk_path}"
      else
         gum style --foreground 9 "no disk selected for swap. defaulting to main drive strategy"
         update_config_value "SWAP_STRATEGY" "main"
         update_config_value "SWAP_DISK_ID" ""
      fi
   fi

   echo
   gum style --bold "set the zfs boot encryption passphrase"
   echo "this password will be required every time you boot the system"

   local zfs_passphrase
   zfs_passphrase=$(gum input --password --placeholder "enter zfs boot passphrase")

   if [[ -n "$zfs_passphrase" ]]; then
      local zfs_passphrase_confirm
      zfs_passphrase_confirm=$(gum input --password --placeholder "confirm passphrase")

      if [[ "$zfs_passphrase" == "$zfs_passphrase_confirm" ]]; then
         update_config_value "ZFS_BOOT_PASSPHRASE" "$zfs_passphrase"

         gum style --foreground 2 "zfs boot passphrase has been set"
      else
         gum style --foreground 9 "passphrases do not match. no changes were made"
      fi
   else
      gum style --foreground 3 "skipped zfs passphrase change. the existing value will be used"
   fi

   sleep 2
}

edit_config_users() {
   clear

   gum style --border normal --margin "1" --padding "1" "accounts"
    
   local vars_to_edit=( "SUDO_USER" "SUDO_USER_PASSWORD" "RESTRICTED_USER" "RESTRICTED_USER_PASSWORD" "ROOT_PASSWORD" )
    
   for var in "${vars_to_edit[@]}"; do
      if [[ "$var" == *_PASSWORD ]]; then
         local new_pass
         new_pass=$(gum input --password --header "enter new password for ${var}")

         if [[ -n "$new_pass" ]]; then
            local new_pass_confirm
            new_pass_confirm=$(gum input --password --header "confirm new password for ${var}")

            if [[ "$new_pass" == "$new_pass_confirm" ]]; then
               update_config_value "$var" "$new_pass"
               gum style --foreground 2 "password for ${var} has been updated"
            else
               gum style --foreground 9 "passwords do not match for ${var}. no changes were made"
            fi
         else
            gum style --foreground 3 "skipped password change for ${var}. the existing value will be used"
         fi
      else
         local current_val new_val
         current_val=$(grep "export ${var}=" config.sh | cut -d'"' -f2)
         new_val=$(gum input --value "$current_val" --header "enter value for ${var}")
        
         if [[ -n "$new_val" ]] && [[ "$new_val" != "$current_val" ]]; then
            update_config_value "$var" "$new_val"
            gum style --foreground 2 "${var} set to ${new_val}"
         else
            gum style --foreground 3 "skipped changing ${var}"
         fi
      fi
      echo
   done
    
   gum style --foreground 2 "account settings configuration finished"
   sleep 2
}

edit_config_network() {
   clear

   gum style --border normal --margin "1" --padding "1" "network"

   local current_hostname new_hostname
   current_hostname=$(grep 'HOSTNAME' config.sh | cut -d'"' -f2)

   new_hostname=$(gum input --value "$current_hostname" --header "enter the system hostname")

   if [[ -n "$new_hostname" ]]; then
      update_config_value "HOSTNAME" "$new_hostname"
      gum style --foreground 2 "hostname set to ${new_hostname}"
   fi

   echo "ipv6 support"
   echo "disable if your isp/router handles ipv6 poorly"
   echo "current disabled: ${SYS_DISABLE_IPV6}"

   local ipv6_choice
   ipv6_choice=$(gum choose "enabled" "disabled")

   if [[ "$ipv6_choice" == "disabled" ]]; then
      update_config_value "SYS_DISABLE_IPV6" "true"
   else
      update_config_value "SYS_DISABLE_IPV6" "false"
   fi

   sleep 2
}

edit_config_advanced() {
   while true; do
      clear
      gum style --border normal --margin "1" --padding "1" "advanced configuration"
      
      local choice
      choice=$(gum choose \
         "kernel variant" \
         "zfs tuning" \
         "performance tuning" \
         "miscellaneous" \
         "personalization (dotfiles/ssh)" \
         "return")
         
      case "$choice" in
         "kernel variant")
            edit_config_kernel
            ;;
         "zfs tuning")
            edit_config_zfs
            ;;
         "performance tuning")
            edit_config_performance
            ;;
         "miscellaneous")
            edit_config_advanced_misc
            ;;
         "personalization (dotfiles/ssh)")
            edit_config_personalization
            ;;
         "return" | *)
            return
            ;;
      esac
   done
}

edit_config_kernel() {
   clear
   gum style --bold "select kernel variant"
   echo "current: ${KERNEL}"
   
   local kernel_choice
   kernel_choice=$(gum choose \
      "linux-cachyos" \
      "linux-cachyos-lts" \
      "linux-cachyos-hardened" \
      "linux-cachyos-bore" \
      "linux-cachyos-server" \
      "linux-cachyos-rt-bore" \
      "linux-cachyos-rc" \
      "linux-cachyos-eevdf" \
      "linux-cachyos-bmq" \
      "linux-cachyos-deckify")
      
   if [[ -n "$kernel_choice" ]]; then
      update_config_value "KERNEL" "$kernel_choice"
      gum style --foreground 2 "kernel set to ${kernel_choice}"
      sleep 1
   fi
}

edit_config_zfs() {
   clear
   gum style --bold "zfs tuning"
   
   echo "select compression algorithm"
   echo "current: ${ZFS_COMPRESSION}"
   local comp_choice
   comp_choice=$(gum choose \
      "lz4" "zstd" "zstd-1" "zstd-2" "zstd-3" "zstd-9" "zstd-19" "off" "gzip" "zle" "lzjb")
   
   if [[ -n "$comp_choice" ]]; then
      update_config_value "ZFS_COMPRESSION" "$comp_choice"
   fi
   
   echo
   gum style --bold "zfs arc limit"
   echo "limiting arc is recommended to prevent ram starvation"
   echo "current: ${ZFS_ARC_MAX}"
   
   local total_ram_mb
   total_ram_mb=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
   total_ram_mb=$((total_ram_mb / 1024))
   
   local arc_choice
   arc_choice=$(gum choose \
      "automatic (zfs default, usually 50% of ram)" \
      "default (limit to 50% of ram)" \
      "custom value")
      
   local arc_val="0"
   
   case "$arc_choice" in
      "default"*)
         arc_val=$((total_ram_mb * 1024 * 1024 / 2))
         ;;
      "custom value")
         local custom_mb
         custom_mb=$(gum input --placeholder "enter max arc size in mb" --value "4096")
         if [[ "$custom_mb" =~ ^[0-9]+$ ]]; then
            arc_val=$((custom_mb * 1024 * 1024))
         else
            gum style --foreground 9 "invalid number, defaulting to auto"
         fi
         ;;
      *)
         arc_val="0"
         ;;
   esac
   
   update_config_value "ZFS_ARC_MAX" "$arc_val"

   echo
   gum style --bold "zfs sync write policy"
   echo "warning: disabling sync writes risks data loss on power failure"
   echo "current sync=disabled: ${ZFS_SYNC_DISABLED}"

   local sync_choice
   sync_choice=$(gum choose "standard (sync=standard)" "unsafe performance (sync=disabled)")

   if [[ "$sync_choice" == *"disabled"* ]]; then
      if gum confirm "are you sure? you might lose the last 5 seconds of data on power loss"; then
         update_config_value "ZFS_SYNC_DISABLED" "true"
      else
         update_config_value "ZFS_SYNC_DISABLED" "false"
      fi
   else
      update_config_value "ZFS_SYNC_DISABLED" "false"
   fi

   echo
   gum style --bold "snapshot policy (sanoid)"
   echo "configure automatic snapshots"
   echo "current: ${ZFS_SNAPSHOT_POLICY}"
   
   local snap_choice
   snap_choice=$(gum choose \
      "production (frequent, hourly, daily, monthly)" \
      "daily (daily, monthly)" \
      "none (manual management)")
      
   local snap_val="production"
   case "$snap_choice" in
      "production"*) snap_val="production" ;;
      "daily"*) snap_val="daily" ;;
      "none"*) snap_val="none" ;;
   esac
   update_config_value "ZFS_SNAPSHOT_POLICY" "$snap_val"

   echo
   gum style --bold "monthly scrub timer"
   echo "systemd timer to verify data integrity"
   echo "current: ${ZFS_SCRUB_ENABLED}"
   
   local scrub_choice
   scrub_choice=$(gum choose "enable" "disable")
   if [[ "$scrub_choice" == "enable" ]]; then
      update_config_value "ZFS_SCRUB_ENABLED" "true"
   else
      update_config_value "ZFS_SCRUB_ENABLED" "false"
   fi

   gum style --foreground 2 "zfs settings updated"
   sleep 1
}

edit_config_performance() {
   clear
   gum style --bold "performance tuning"

   echo "transparent hugepages (thp)"
   echo "controls how the kernel manages large memory pages"
   echo "current: ${SYS_THP_POLICY}"
   
   local thp_choice
   thp_choice=$(gum choose \
      "madvise (default, sane)" \
      "always (good for math/compile, bad for latency/redis)" \
      "never (critical for redis, mongodb, gaming latency)")
   
   local thp_val="madvise"
   case "$thp_choice" in
      "madvise"*) thp_val="madvise" ;;
      "always"*) thp_val="always" ;;
      "never"*) thp_val="never" ;;
   esac
   update_config_value "SYS_THP_POLICY" "$thp_val"

   echo
   echo "i/o scheduler enforcement"
   echo "controls how disk read/write requests are queued"
   echo "current: ${SYS_IO_SCHEDULER}"

   local io_choice
   io_choice=$(gum choose \
      "none (best for modern nvme)" \
      "kyber (low latency, good for fast ssds)" \
      "bfq (complex, high overhead, good for hdd)" \
      "mq-deadline (simple, fallback)")
   
   local io_val="none"
   case "$io_choice" in
      "none"*) io_val="none" ;;
      "kyber"*) io_val="kyber" ;;
      "bfq"*) io_val="bfq" ;;
      "mq-deadline"*) io_val="mq-deadline" ;;
   esac
   update_config_value "SYS_IO_SCHEDULER" "$io_val"

   echo
   echo "systemd aggressive shutdown"
   echo "reduces the timeout for hung services from 90s to 10s"
   echo "current: ${SYS_AGGRESSIVE_SHUTDOWN}"

   local watchdog_choice
   watchdog_choice=$(gum choose "standard (90s timeout)" "aggressive (10s timeout)")

   if [[ "$watchdog_choice" == *"aggressive"* ]]; then
      update_config_value "SYS_AGGRESSIVE_SHUTDOWN" "true"
   else
      update_config_value "SYS_AGGRESSIVE_SHUTDOWN" "false"
   fi

   echo
   echo "vm.swappiness (0-100)"
   echo "how aggressively the kernel swaps to disk. 10 is good for desktops."
   echo "current: ${SYS_SWAPPINESS}"

   local swap_val
   swap_val=$(gum input --value "${SYS_SWAPPINESS}" --placeholder "10")
   if [[ "$swap_val" =~ ^[0-9]+$ ]] && [ "$swap_val" -ge 0 ] && [ "$swap_val" -le 100 ]; then
      update_config_value "SYS_SWAPPINESS" "$swap_val"
   else
      gum style --foreground 9 "invalid swappiness value (must be 0-100)"
   fi

   gum style --foreground 2 "performance settings updated."
   sleep 1
}

edit_config_advanced_misc() {
   clear
   gum style --bold "miscellaneous configuration"

   echo
   echo "custom kernel arguments"
   echo "append raw arguments to the kernel command line (e.g. 'i915.enable_psr=0')"
   echo "current: ${KERNEL_OPTS}"

   local custom_args
   custom_args=$(gum input --value "${KERNEL_OPTS}" --placeholder "${KERNEL_OPTS}")
   
   update_config_value "KERNEL_OPTS" "$custom_args"

   gum style --foreground 2 "misc settings updated"
   sleep 1
}

edit_config_personalization() {
   clear
   gum style --bold "personalization"
   
   local current_repo
   current_repo=$(grep 'DOTFILES_REPO' config.sh | cut -d'"' -f2)
   
   echo "enter a git repository url for your dotfiles"
   echo "if set, this will replace the default dotfiles included in recipes"
   
   local new_repo
   new_repo=$(gum input --placeholder "https://github.com/username/dotfiles.git" --value "$current_repo")
   
   update_config_value "DOTFILES_REPO" "$new_repo"
   
   echo
   local current_gh_user
   current_gh_user=$(grep 'GITHUB_USERNAME_KEYS' config.sh | cut -d'"' -f2)
   
   echo "enter your github username to auto-install ssh public keys:"
   local new_gh_user
   new_gh_user=$(gum input --placeholder "username" --value "$current_gh_user")
   
   update_config_value "GITHUB_USERNAME_KEYS" "$new_gh_user"
   
   gum style --foreground 2 "personalization settings updated"
   sleep 1
}