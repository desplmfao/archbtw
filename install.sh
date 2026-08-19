#!/usr/bin/env bash
set -euo pipefail

INSTALL_LOG="install.log"

source "utils.sh"
source "lib/config_menu.sh"

check_deps() {
   if ! command -v gum &> /dev/null; then
      pacman -S --noconfirm gum
   fi

   if ! command -v zpool &> /dev/null; then
      gum style --bold "zfs utilities not found. installing from archzfs repository..."
      
      if curl -s https://archzfs.leibelt.de/media/setup/init | bash; then
         gum style --foreground 2 "zfs utilities installed successfully"
      else
         gum style --bold --foreground 9 "fatal: failed to install zfs utilities"
         echo "cannot continue without zfs"
         exit 1
      fi
   fi
}

print_header() {
   gum style --border double --margin "1" --padding "1 2" --border-foreground 212 "installer" "$1"
}

list_recipes() {
   find recipes -mindepth 2 -name "recipe.conf" | while read -r conf_path; do
      local dir_path
      dir_path=$(dirname "$conf_path")
      
      local rel_path="${dir_path#recipes/}"
      
      local desc
      desc=$(grep 'description' "$conf_path" | cut -d'=' -f2 | tr -d '"')
      
      echo "$rel_path|$desc"
   done | sort -V -t'|' -k1,1 | while IFS='|' read -r rel_path desc; do
      echo "$rel_path $desc"
   done
}

run_recipe() {
   local recipe_name=$1
   local recipe_dir="recipes/$recipe_name"
   local recipe_path="$recipe_dir/install.sh"

   if [ ! -f "$recipe_path" ]; then
      gum style --bold --foreground 9 "error: recipe script not found at '${recipe_path}'."
      exit 1
   fi

   gum style --padding "1 0" --margin "1 0" --border thick --border-foreground 212 \
      "now running recipe: ${recipe_name}"

   echo "--- starting recipe: ${recipe_name} ---" >> "$INSTALL_LOG"

   (set -e; bash "$recipe_path") 2>&1 | tee -a "$INSTALL_LOG"

   local exit_code=$?

   if [[ $exit_code -ne 0 ]]; then
      gum style --bold --foreground 9 --padding "1 0" --margin "1 0" \
         "fatal: recipe '${recipe_name}' failed with exit code ${exit_code}"

      echo "please review the output above or in ${INSTALL_LOG} for the specific error message"
      echo "cannot continue the installation"
      exit 1
   else
      if [[ "$(basename "$recipe_name")" == "02_first_boot" ]] && [[ -n "${DOTFILES_REPO}" ]]; then
         gum style --foreground 3 "skipping file overlay for 02_first_boot (using custom dotfiles repo instead)"
      else
         apply_recipe_overlay "$recipe_dir"
      fi
      
      gum style --bold --foreground 2 --padding "0 0" "recipe '${recipe_name}' completed successfully"
   fi
}

run_full_install() {
   print_header "starting full installation"

   if ! gum confirm "this will erase ${MAIN_DISK_ID} and install shitlinux. are you sure?"; then
      echo "installation cancelled"
      return
   fi
   
   mapfile -t recipes_to_run < <(list_recipes | cut -d' ' -f1)
   
   for recipe in "${recipes_to_run[@]}"; do
      run_recipe "$recipe"
   done
   
   print_header "installation complete"

   echo "you can now reboot. we didn't unmount for you. you can chroot into it"
}

run_custom_install() {
   print_header "customize installation"
   
   mapfile -t chosen_recipes < <(list_recipes | gum choose --no-limit --height 15 --header "select recipes to run (spacebar to select, enter to confirm)" | cut -d' ' -f1)
   
   if [ ${#chosen_recipes[@]} -eq 0 ]; then
      echo "no recipes selected. returning to main menu"
      sleep 2
      return
   fi
   
   if ! gum confirm "ready to run the ${#chosen_recipes[@]} selected recipes?"; then
      echo "installation cancelled"
      return
   fi
   
   for recipe in "${chosen_recipes[@]}"; do
      run_recipe "$recipe"
   done

   print_header "custom installation complete"
}

main() {
   check_deps

   if [ ! -f config.sh ]; then
      gum style --foreground 9 "fatal: config.sh not found!"
      exit 1
   fi

   source config.sh

   echo "--- installation started at $(date) ---" > "$INSTALL_LOG"

   while true; do
      clear

      print_header "main menu"
        
      local choice
      choice=$(gum choose \
            "start auto installation" \
            "customize installation (advanced)" \
            "edit configuration" \
            "exit")

      case "$choice" in
         "start auto installation")
            run_full_install
            break
            ;;
         "customize installation (advanced)")
            run_custom_install
            break
            ;;
         "edit configuration")
            edit_config
            ;;
         "exit")
            echo "exiting installer"
            exit 0
            ;;
         *)
            echo "exiting installer"
            exit 0
            ;;
      esac
   done
}

main