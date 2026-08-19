#!/bin/bash

list_disks_by_id() {
   find /dev/disk/by-id/ -type l | sort | while read -r disk_path; do
      local disk_name
      disk_name=$(basename "$disk_path")

      if [[ "$disk_name" == *"-part"* ]]; then
         continue
      fi

      if [[ "$disk_name" == *"wwn-"* ]]; then
         continue
      fi

      local size model fs_info

      size=$(lsblk -dno SIZE "$disk_path" 2>/dev/null || echo "N/A")
      model=$(lsblk -dno MODEL "$disk_path" 2>/dev/null | tr -s ' ' || echo "Unknown Model")
      fs_info=$(lsblk -no FSTYPE "$disk_path" 2>/dev/null | sort | uniq | grep -v "^$" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
      
      if [[ -z "$fs_info" ]]; then
         fs_info="empty/raw"
      fi

      if [[ -n "$size" ]]; then
         echo "$disk_name ($size) | $model | [$fs_info]"
      fi
   done
}