#!/bin/bash

apply_recipe_overlay() {
   local recipe_dir="$1"
   local overlay_root="${recipe_dir}/root"
   
   if [ ! -d "$overlay_root" ]; then
      return
   fi
   
   gum style --foreground 4 "applying filesystem overlay from ${overlay_root}..."
   
   find "$overlay_root" -type f | while read -r src_file; do
      local rel_path="${src_file#$overlay_root/}"
      local target_rel_path=""
      
      IFS='/' read -r -a path_parts <<< "$rel_path"
      
      for part in "${path_parts[@]}"; do
         if [[ "$part" == \$* ]]; then
            local var_name="${part:1}"
            
            if [[ -n "${!var_name:-}" ]]; then
               part="${!var_name}"
            fi
         fi
         
         if [[ -z "$target_rel_path" ]]; then
            target_rel_path="$part"
         else
            target_rel_path="${target_rel_path}/${part}"
         fi
      done
      
      local target_file="/mnt/$target_rel_path"
      local target_parent
      target_parent=$(dirname "$target_file")
      
      mkdir -p "$target_parent"
      cp "$src_file" "$target_file"
   done

   if [ -d "/mnt/home/$SUDO_USER" ]; then
      arch-chroot /mnt chown -R "$SUDO_USER:$SUDO_USER" "/home/$SUDO_USER"
   fi

   if [ -d "/mnt/home/$RESTRICTED_USER" ]; then
      arch-chroot /mnt chown -R "$RESTRICTED_USER:$RESTRICTED_USER" "/home/$RESTRICTED_USER"
   fi
}