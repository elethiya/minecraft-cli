#!/usr/bin/env bash

# ==========================================
# BASE DIRECTORIES & CONFIGURATION
# ==========================================
CLI_DIR="$HOME/minecraft-cli"
SETTINGS_FILE="$CLI_DIR/settings.json"
AUTHLIB_DIR="$CLI_DIR/authlib"
AUTHLIB_JAR="$AUTHLIB_DIR/authlib-injector.jar"
ACCOUNTS_DB="$AUTHLIB_DIR/accounts.json"
SKINS_DIR="$CLI_DIR/skins"
CAPES_DIR="$CLI_DIR/capes"

mkdir -p "$CLI_DIR" "$AUTHLIB_DIR" "$SKINS_DIR" "$CAPES_DIR"

ensure_accounts_db() {
    if [ ! -s "$ACCOUNTS_DB" ] || ! jq -e '.accounts and (.accounts | type == "array")' "$ACCOUNTS_DB" >/dev/null 2>&1; then
        if [ -s "$ACCOUNTS_DB" ] && jq -e '.username and .type' "$ACCOUNTS_DB" >/dev/null 2>&1; then
            jq '{accounts: [.]}' "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
        else
            echo '{"accounts":[]}' > "$ACCOUNTS_DB"
        fi
    fi
}
ensure_accounts_db


setup_first_time_directory() {
    if [ ! -s "$SETTINGS_FILE" ] || [ -z "$(jq -r '.game_dir // empty' "$SETTINGS_FILE" 2>/dev/null)" ]; then
        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m         WELCOME TO MINECRAFT LAUNCHER        \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "  Please select the directory where you want to"
        echo -e "  install and store your Minecraft game files:\n"
        echo -e "  \e[1;32m[1]\e[0m Standard \e[1;33m~/.minecraft\e[0m"
        echo -e "      (Default location: $HOME/.minecraft)\n"
        echo -e "  \e[1;32m[2]\e[0m Inside Launcher Directory"
        echo -e "      (Location: $CLI_DIR/.minecraft)\n"
        echo -e "  \e[1;32m[3]\e[0m Custom Path"
        echo -e "      (Specify any folder on your system)"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select an option [1-3, default: 1]: " first_choice

        local chosen_dir="$HOME/.minecraft"
        case "$first_choice" in
            2)
                chosen_dir="$CLI_DIR/.minecraft"
                ;;
            3)
                while true; do
                    read -rp "Enter directory path: " custom_input
                    custom_input="${custom_input/#\~/$HOME}"
                    if [ -n "$custom_input" ]; then
                        chosen_dir="$custom_input"
                        break
                    fi
                    echo -e "\e[1;31m[-] Path cannot be empty.\e[0m"
                done
                ;;
            *)
                chosen_dir="$HOME/.minecraft"
                ;;
        esac

        mkdir -p "$chosen_dir"
        echo -e "\e[1;32m[+] Game directory set to: $chosen_dir\e[0m"

        local cur_max="4G"
        local cur_min="2G"
        local cur_jvm="-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M --enable-native-access=ALL-UNNAMED"
        if [ -s "$SETTINGS_FILE" ]; then
            cur_max=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE" 2>/dev/null)
            cur_min=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE" 2>/dev/null)
            cur_jvm=$(jq -r '.jvm_args // "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M --enable-native-access=ALL-UNNAMED"' "$SETTINGS_FILE" 2>/dev/null)
        fi

        cat << SETTINGS_EOF > "$SETTINGS_FILE"
{
  "game_dir": "$chosen_dir",
  "max_ram": "$cur_max",
  "min_ram": "$cur_min",
  "jvm_args": "$cur_jvm"
}
SETTINGS_EOF
        sleep 1.2
    fi
}
setup_first_time_directory

# ==========================================
# PROGRESS BAR HELPER WITH SPEED & ETA
# ==========================================
render_progress_bar() {
    local current=$1
    local total=$2
    local label=${3:-"Progress"}
    local start_ms=${4:-0}
    local cur_bytes=${5:-0}
    local tot_bytes=${6:-0}
    local width=22

    if [ "$total" -le 0 ]; then return; fi
    local percent=$(( 100 * current / total ))
    [ "$percent" -gt 100 ] && percent=100
    local filled=$(( width * percent / 100 ))
    local empty=$(( width - filled ))

    local bar_fill=$(printf "%*s" "$filled" "" | tr ' ' '#')
    local bar_empty=$(printf "%*s" "$empty" "" | tr ' ' '-')

    local extra_info=""
    local now_ms=$(date +%s%3N 2>/dev/null || date +%s)
    local elapsed_ms=$(( now_ms - start_ms ))

    if [ "$start_ms" -gt 0 ] && [ "$elapsed_ms" -ge 150 ]; then
        if [ "$cur_bytes" -gt 0 ]; then
            local speed_bps=$(( (cur_bytes * 1000) / elapsed_ms ))
            local speed_str=""
            if [ "$speed_bps" -ge 1048576 ]; then
                speed_str=$(awk -v b="$speed_bps" 'BEGIN { printf "%.2f MB/s", b / 1048576 }')
            elif [ "$speed_bps" -ge 1024 ]; then
                speed_str=$(awk -v b="$speed_bps" 'BEGIN { printf "%.1f KB/s", b / 1024 }')
            else
                speed_str="${speed_bps} B/s"
            fi

            local eta_str="--"
            if [ "$tot_bytes" -gt 0 ] && [ "$speed_bps" -gt 0 ]; then
                local rem_bytes=$(( tot_bytes - cur_bytes ))
                if [ "$rem_bytes" -gt 0 ]; then
                    local rem_sec=$(( rem_bytes / speed_bps ))
                    if [ "$rem_sec" -ge 3600 ]; then
                        eta_str=$(printf "%02dh %02dm" $(( rem_sec / 3600 )) $(( (rem_sec % 3600) / 60 )))
                    elif [ "$rem_sec" -ge 60 ]; then
                        eta_str=$(printf "%02dm %02ds" $(( rem_sec / 60 )) $(( rem_sec % 60 )))
                    else
                        eta_str=$(printf "%02ds" "$rem_sec")
                    fi
                else
                    eta_str="00s"
                fi
            fi
            extra_info=" \e[1;33m$speed_str\e[0m | \e[1;36mETA: $eta_str\e[0m"
        else
            local items_per_sec=$(awk -v c="$current" -v e="$elapsed_ms" 'BEGIN { printf "%.1f", (c * 1000) / e }')
            local rem_items=$(( total - current ))
            local rem_sec=0
            [ "$current" -gt 0 ] && rem_sec=$(( (rem_items * elapsed_ms) / (current * 1000) ))
            local eta_str="--"
            if [ "$rem_sec" -ge 60 ]; then
                eta_str=$(printf "%02dm %02ds" $(( rem_sec / 60 )) $(( rem_sec % 60 )))
            else
                eta_str=$(printf "%02ds" "$rem_sec")
            fi
            extra_info=" \e[1;33m${items_per_sec} items/s\e[0m | \e[1;36mETA: $eta_str\e[0m"
        fi
    else
        extra_info=" \e[1;30m-- MB/s | ETA: --\e[0m"
    fi

    local current_fmt="$current"
    local total_fmt="$total"
    if [ "$tot_bytes" -gt 0 ] && [ "$tot_bytes" -eq "$total" ]; then
        if [ "$tot_bytes" -ge 1048576 ]; then
            current_fmt=$(awk -v b="$current" 'BEGIN { printf "%.1f", b / 1048576 }')
            total_fmt=$(awk -v b="$total" 'BEGIN { printf "%.1f MB", b / 1048576 }')
        elif [ "$tot_bytes" -ge 1024 ]; then
            current_fmt=$(awk -v b="$current" 'BEGIN { printf "%.1f", b / 1024 }')
            total_fmt=$(awk -v b="$total" 'BEGIN { printf "%.1f KB", b / 1024 }')
        fi
    fi

    printf "\r\e[1;34m%-12s\e[0m \e[1;36m[%s%s]\e[0m \e[1;32m%3d%%\e[0m (\e[1;33m%s/%s\e[0m)%b \033[K" \
        "$label" "$bar_fill" "$bar_empty" "$percent" "$current_fmt" "$total_fmt" "$extra_info"
}

download_single_file_with_progress() {
    local url="$1"
    local dest="$2"
    local label=${3:-"Downloading"}
    local expected_size=${4:-0}

    mkdir -p "$(dirname "$dest")"
    rm -f "$dest"

    local start_ms=$(date +%s%3N 2>/dev/null || date +%s)
    curl -sL "$url" -o "$dest" &
    local c_pid=$!

    if [ "$expected_size" -le 0 ]; then
        expected_size=$(curl -sI --connect-timeout 2 --max-time 3 -L "$url" 2>/dev/null | grep -i "^content-length:" | tail -n 1 | awk '{print $2}' | tr -d '\r' || echo 0)
        expected_size=${expected_size:-0}
    fi

    while kill -0 "$c_pid" 2>/dev/null; do
        local cur_sz=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        local display_tot="${expected_size:-0}"
        [ "$display_tot" -le 0 ] && display_tot="$cur_sz"
        render_progress_bar "$cur_sz" "$display_tot" "$label" "$start_ms" "$cur_sz" "$expected_size"
        sleep 0.1
    done
    wait "$c_pid"
    local cur_sz=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    render_progress_bar "$cur_sz" "$cur_sz" "$label" "$start_ms" "$cur_sz" "$cur_sz"
    echo ""
}

# Ensure authlib-injector exists
if [ ! -s "$AUTHLIB_JAR" ]; then
    echo -e "\e[1;34m==> Downloading authlib-injector...\e[0m"
    download_single_file_with_progress "https://github.com/yushijinhun/authlib-injector/releases/download/v1.2.5/authlib-injector-1.2.5.jar" "$AUTHLIB_JAR" "Authlib Agent"
fi

# Helper function to refresh directory variables
sync_directories() {
    MC_DIR=$(jq -r '.game_dir // "'"$HOME/.minecraft"'"' "$SETTINGS_FILE")
    VERSIONS_DIR="$MC_DIR/versions"
    LIBS_DIR="$MC_DIR/libraries"
    ASSETS_DIR="$MC_DIR/assets"
    mkdir -p "$VERSIONS_DIR" "$LIBS_DIR" "$ASSETS_DIR/indexes" "$ASSETS_DIR/objects" "$SKINS_DIR" "$CAPES_DIR" "$CLI_DIR/tools" "$CLI_DIR/versions"

    # Ensure every installed version folder has its own mods, resourcepacks, and shaderpacks directory inside it
    # Also expose shortcuts in ~/minecraft-cli/versions/<version_name>/
    if [ -d "$VERSIONS_DIR" ]; then
        for v_dir in "$VERSIONS_DIR"/*; do
            if [ -d "$v_dir" ]; then
                local v_name
                v_name=$(basename "$v_dir")
                mkdir -p "$v_dir/mods" "$v_dir/resourcepacks" "$v_dir/shaderpacks" "$v_dir/saves" "$v_dir/config"

                local cli_v_dir="$CLI_DIR/versions/$v_name"
                mkdir -p "$cli_v_dir"
                ln -sfn "$v_dir/mods" "$cli_v_dir/mods"
                ln -sfn "$v_dir/resourcepacks" "$cli_v_dir/resourcepacks"
                ln -sfn "$v_dir/shaderpacks" "$cli_v_dir/shaderpacks"
                ln -sfn "$v_dir/saves" "$cli_v_dir/saves"
                ln -sfn "$v_dir/config" "$cli_v_dir/config"
            fi
        done
    fi

    # Clean up stale versions in ~/minecraft-cli/versions/
    if [ -d "$CLI_DIR/versions" ]; then
        for cli_v in "$CLI_DIR/versions"/*; do
            if [ -d "$cli_v" ]; then
                local v_name
                v_name=$(basename "$cli_v")
                if [ ! -d "$VERSIONS_DIR/$v_name" ]; then
                    rm -rf "$cli_v"
                fi
            fi
        done
    fi

    local first_ver=""
    if [ -d "$VERSIONS_DIR" ]; then
        first_ver=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | head -n 1)
    fi
    if [ -n "$first_ver" ] && [ -d "$VERSIONS_DIR/$first_ver" ]; then
        ln -sfn "$VERSIONS_DIR/$first_ver/mods" "$CLI_DIR/mods"
        ln -sfn "$VERSIONS_DIR/$first_ver/resourcepacks" "$CLI_DIR/resourcepacks"
        ln -sfn "$VERSIONS_DIR/$first_ver/shaderpacks" "$CLI_DIR/shaderpacks"
    fi
}
sync_directories

# ==========================================
# CORE DOWNLOADER HELPER (VANILLA ENGINE)
# ==========================================
download_vanilla_version() {
    local target_ver="$1"
    if [ -z "$target_ver" ]; then return 1; fi

    echo -e "\e[1;34m==> Fetching Mojang version manifest...\e[0m"
    local manifest_json
    manifest_json=$(curl -s "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    if [ -z "$manifest_json" ]; then
        echo -e "\e[1;31m[-] Failed to fetch official version manifest.\e[0m"
        return 1
    fi

    local version_url
    version_url=$(echo "$manifest_json" | jq -r --arg v "$target_ver" '.versions[] | select(.id == $v) | .url')
    if [ -z "$version_url" ] || [ "$version_url" == "null" ]; then
        echo -e "\e[1;31m[-] Version '$target_ver' not found in official manifest.\e[0m"
        return 1
    fi

    local target_ver_dir="$VERSIONS_DIR/$target_ver"
    mkdir -p "$target_ver_dir" "$target_ver_dir/natives"

    echo -e "\n\e[1;34m==> [1/4] Downloading version metadata ($target_ver.json)...\e[0m"
    local target_ver_json="$target_ver_dir/$target_ver.json"
    curl -sL "$version_url" -o "$target_ver_json"

    echo -e "\e[1;34m==> [2/4] Downloading client binary ($target_ver.jar)...\e[0m"
    local client_url client_sz
    client_url=$(jq -r '.downloads.client.url' "$target_ver_json")
    client_sz=$(jq -r '.downloads.client.size // 0' "$target_ver_json")
    local target_jar="$target_ver_dir/$target_ver.jar"
    download_single_file_with_progress "$client_url" "$target_jar" "Client Jar" "$client_sz"

    echo -e "\e[1;34m==> [3/4] Downloading version libraries...\e[0m"
    mapfile -t libs_list < <(jq -r '.libraries[] | select(.downloads.artifact != null) | .downloads.artifact | "\(.path)|\(.url)|\(.size // 0)"' "$target_ver_json")
    local total_libs=${#libs_list[@]}
    local total_lib_bytes=0
    for item in "${libs_list[@]}"; do
        local sz="${item##*|}"
        (( total_lib_bytes += sz ))
    done

    local curr_lib=0
    local done_lib_bytes=0
    local start_lib_ms=$(date +%s%3N 2>/dev/null || date +%s)
    for item in "${libs_list[@]}"; do
        IFS='|' read -r l_path l_url l_sz <<< "$item"
        local dest="$LIBS_DIR/$l_path"
        if [ ! -s "$dest" ]; then
            mkdir -p "$(dirname "$dest")"
            curl -sL "$l_url" -o "$dest"
        fi
        ((curr_lib++))
        ((done_lib_bytes += l_sz))
        render_progress_bar "$curr_lib" "$total_libs" "Libraries" "$start_lib_ms" "$done_lib_bytes" "$total_lib_bytes"
    done
    echo ""

    find "$LIBS_DIR" -name "*natives-linux*.jar" -exec unzip -n -q -d "$target_ver_dir/natives" {} + 2>/dev/null || true

    echo -e "\e[1;34m==> [4/4] Verifying and downloading assets...\e[0m"
    local a_index_name a_index_url a_index_file
    a_index_name=$(jq -r '.assetIndex.id' "$target_ver_json")
    a_index_url=$(jq -r '.assetIndex.url' "$target_ver_json")
    a_index_file="$ASSETS_DIR/indexes/$a_index_name.json"

    if [ ! -s "$a_index_file" ]; then
        download_single_file_with_progress "$a_index_url" "$a_index_file" "Asset Index"
    fi

    mapfile -t hash_size_list < <(jq -r '.objects | to_entries[] | "\(.value.hash):\(.value.size // 0)"' "$a_index_file")
    local missing_assets=()
    local total_asset_bytes=0
    for item in "${hash_size_list[@]}"; do
        local h="${item%%:*}"
        local sz="${item##*:}"
        local pfx="${h:0:2}"
        if [ ! -s "$ASSETS_DIR/objects/$pfx/$h" ]; then
            missing_assets+=("$h:$sz")
            (( total_asset_bytes += sz ))
        fi
    done

    local total_missing=${#missing_assets[@]}
    if [ "$total_missing" -gt 0 ]; then
        echo -e "\e[1;34m==> Downloading $total_missing missing assets in parallel (16 threads)...\e[0m"
        export ASSETS_DIR
        local done_count=0
        local done_bytes=0
        local start_asset_ms=$(date +%s%3N 2>/dev/null || date +%s)
        while read -r sz; do
            sz=${sz:-0}
            ((done_count++))
            ((done_bytes += sz))
            if (( done_count % 10 == 0 || done_count == total_missing )); then
                render_progress_bar "$done_count" "$total_missing" "Assets" "$start_asset_ms" "$done_bytes" "$total_asset_bytes"
            fi
        done < <(printf "%s\n" "${missing_assets[@]}" | xargs -P 16 -n 25 bash -c '
            for entry in "$@"; do
                h="${entry%%:*}"
                sz="${entry##*:}"
                p="${h:0:2}"
                dest="$ASSETS_DIR/objects/$p/$h"
                if [ ! -s "$dest" ]; then
                    mkdir -p "$ASSETS_DIR/objects/$p"
                    curl -sL --retry 2 --retry-connrefused "https://resources.download.minecraft.net/$p/$h" -o "$dest"
                fi
                echo "$sz"
            done
        ' _)
        echo ""
    else
        echo -e "  \e[1;32mAll assets are already verified and up-to-date.\e[0m"
    fi

    echo -e "\n\e[1;32m[+] Version $target_ver installed successfully in $target_ver_dir!\e[0m"
    return 0
}

ensure_vanilla_installed() {
    local mc_ver="$1"
    if [ ! -f "$VERSIONS_DIR/$mc_ver/$mc_ver.json" ] || [ ! -f "$VERSIONS_DIR/$mc_ver/$mc_ver.jar" ]; then
        echo -e "\n\e[1;33m[*] Base Minecraft $mc_ver is required and not installed yet.\e[0m"
        echo -e "\e[1;34m==> Downloading and preparing base Minecraft $mc_ver first...\e[0m"
        download_vanilla_version "$mc_ver" || return 1
    fi
    return 0
}

# ==========================================
# VERSION INSTALLERS (VANILLA, FABRIC, NEOFORGE, FORGE, QUILT, SNAPSHOTS)
# ==========================================
install_vanilla_releases() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m           OFFICIAL VANILLA RELEASES          \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"

    local manifest_json
    manifest_json=$(curl -s "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    if [ -z "$manifest_json" ]; then
        echo -e "\e[1;31m[-] Failed to fetch official version manifest.\e[0m"
        read -rp "Press Enter to return..."
        return
    fi

    mapfile -t TOP_RELEASES < <(echo "$manifest_json" | jq -r '[.versions[] | select(.type=="release")][0:12] | .[].id')
    echo -e "\e[1;33mPopular / Recent Official Releases:\e[0m"
    for i in "${!TOP_RELEASES[@]}"; do
        printf "  \e[1;32m[%d]\e[0m %s\n" "$((i+1))" "${TOP_RELEASES[$i]}"
    done
    echo -e "  \e[1;33m[c]\e[0m Type a custom release version (e.g. 1.20.4, 1.16.5, 1.8.9)"
    echo -e "  \e[1;31m[b]\e[0m Back"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select version to install: " v_opt

    local target_ver=""
    if [[ "$v_opt" =~ ^[0-9]+$ ]] && [ "$v_opt" -ge 1 ] && [ "$v_opt" -le "${#TOP_RELEASES[@]}" ]; then
        target_ver="${TOP_RELEASES[$((v_opt-1))]}"
    elif [ "$v_opt" == "c" ] || [ "$v_opt" == "C" ]; then
        read -rp "Enter exact Minecraft version: " target_ver
    else
        return
    fi

    [ -n "$target_ver" ] && download_vanilla_version "$target_ver"
    read -rp "Press Enter to return..."
}

install_snapshot_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m         OFFICIAL SNAPSHOTS & TESTING         \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"

    local manifest_json
    manifest_json=$(curl -s "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    if [ -z "$manifest_json" ]; then
        echo -e "\e[1;31m[-] Failed to fetch official version manifest.\e[0m"
        read -rp "Press Enter to return..."
        return
    fi

    mapfile -t TOP_SNAPSHOTS < <(echo "$manifest_json" | jq -r '[.versions[] | select(.type=="snapshot")][0:12] | .[].id')
    echo -e "\e[1;33mRecent Official Snapshots:\e[0m"
    for i in "${!TOP_SNAPSHOTS[@]}"; do
        printf "  \e[1;32m[%d]\e[0m %s\n" "$((i+1))" "${TOP_SNAPSHOTS[$i]}"
    done
    echo -e "  \e[1;33m[c]\e[0m Type a custom snapshot ID (e.g. 24w34a)"
    echo -e "  \e[1;31m[b]\e[0m Back"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select snapshot to install: " s_opt

    local target_ver=""
    if [[ "$s_opt" =~ ^[0-9]+$ ]] && [ "$s_opt" -ge 1 ] && [ "$s_opt" -le "${#TOP_SNAPSHOTS[@]}" ]; then
        target_ver="${TOP_SNAPSHOTS[$((s_opt-1))]}"
    elif [ "$s_opt" == "c" ] || [ "$s_opt" == "C" ]; then
        read -rp "Enter exact snapshot ID: " target_ver
    else
        return
    fi

    [ -n "$target_ver" ] && download_vanilla_version "$target_ver"
    read -rp "Press Enter to return..."
}

install_fabric_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m             FABRIC LOADER INSTALLER          \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"

    mapfile -t VANILLA_INSTALLED < <(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V)

    if [ ${#VANILLA_INSTALLED[@]} -gt 0 ]; then
        echo -e "\e[1;33mDetected Installed Minecraft Versions:\e[0m"
        for i in "${!VANILLA_INSTALLED[@]}"; do
            printf "  \e[1;32m[%d]\e[0m %s\n" "$((i+1))" "${VANILLA_INSTALLED[$i]}"
        done
        echo -e "  \e[1;33m[c]\e[0m Type a different Minecraft version (e.g. 1.21.1, 1.20.4)"
        echo -e "  \e[1;31m[b]\e[0m Back"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select option: " f_opt

        local target_mc=""
        if [[ "$f_opt" =~ ^[0-9]+$ ]] && [ "$f_opt" -ge 1 ] && [ "$f_opt" -le "${#VANILLA_INSTALLED[@]}" ]; then
            target_mc="${VANILLA_INSTALLED[$((f_opt-1))]}"
        elif [ "$f_opt" == "c" ] || [ "$f_opt" == "C" ]; then
            read -rp "Enter exact Minecraft version (e.g. 1.21.1): " target_mc
        else
            return
        fi
    else
        read -rp "Enter Minecraft version for Fabric (e.g. 1.21.1, 1.20.4): " target_mc
    fi

    if [ -z "$target_mc" ]; then return; fi

    ensure_vanilla_installed "$target_mc" || {
        read -rp "Press Enter to return..."
        return
    }

    echo -e "\n\e[1;34m==> Fetching Fabric Installer...\e[0m"
    local fabric_installer="$CLI_DIR/fabric-installer.jar"
    if [ ! -s "$fabric_installer" ]; then
        download_single_file_with_progress "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar" "$fabric_installer" "Fabric Inst."
    fi

    [ -f "$MC_DIR/launcher_profiles.json" ] || echo '{"profiles":{}}' > "$MC_DIR/launcher_profiles.json"

    echo -e "\e[1;34m==> Running Fabric Installer for Minecraft $target_mc...\e[0m"
    java -jar "$fabric_installer" client -dir "$MC_DIR" -mcversion "$target_mc"

    echo -e "\n\e[1;32m[+] Fabric Loader installed successfully for $target_mc!\e[0m"
    read -rp "Press Enter to return..."
}

install_neoforge_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m            NEOFORGE LOADER INSTALLER         \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"

    echo -e "\e[1;33mPopular Minecraft Versions for NeoForge:\e[0m"
    echo -e "  \e[1;32m[1]\e[0m 1.21.1 (NeoForge 21.1)"
    echo -e "  \e[1;32m[2]\e[0m 1.21   (NeoForge 21.0)"
    echo -e "  \e[1;32m[3]\e[0m 1.20.6 (NeoForge 20.6)"
    echo -e "  \e[1;32m[4]\e[0m 1.20.4 (NeoForge 20.4)"
    echo -e "  \e[1;33m[c]\e[0m Custom Minecraft Version"
    echo -e "  \e[1;31m[b]\e[0m Back"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select option: " nf_opt

    local target_mc=""
    case "$nf_opt" in
        1) target_mc="1.21.1" ;;
        2) target_mc="1.21" ;;
        3) target_mc="1.20.6" ;;
        4) target_mc="1.20.4" ;;
        c|C) read -rp "Enter exact Minecraft version (1.20.2+): " target_mc ;;
        *) return ;;
    esac

    if [ -z "$target_mc" ]; then return; fi

    ensure_vanilla_installed "$target_mc" || {
        read -rp "Press Enter to return..."
        return
    }

    echo -e "\n\e[1;34m==> Fetching NeoForge releases from Maven...\e[0m"
    local neo_prefix=""
    if [[ "$target_mc" =~ ^1\.21\.1$ ]]; then neo_prefix="21.1."
    elif [[ "$target_mc" =~ ^1\.21$ ]]; then neo_prefix="21.0."
    elif [[ "$target_mc" =~ ^1\.20\.6$ ]]; then neo_prefix="20.6."
    elif [[ "$target_mc" =~ ^1\.20\.4$ ]]; then neo_prefix="20.4."
    elif [[ "$target_mc" =~ ^1\.([0-9]+)\.([0-9]+)$ ]]; then
        neo_prefix="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}."
    fi

    local neo_versions_json
    neo_versions_json=$(curl -s "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge")
    local target_neo_ver=""
    if [ -n "$neo_prefix" ]; then
        target_neo_ver=$(echo "$neo_versions_json" | jq -r --arg p "$neo_prefix" '[.versions[] | select(startswith($p) and (contains("beta") | not) and (contains("alpha") | not))] | .[-1] // empty')
        if [ -z "$target_neo_ver" ]; then
            target_neo_ver=$(echo "$neo_versions_json" | jq -r --arg p "$neo_prefix" '[.versions[] | select(startswith($p))] | .[-1] // empty')
        fi
    fi

    if [ -z "$target_neo_ver" ]; then
        echo -e "\e[1;33m[*] Could not auto-detect exact NeoForge build.\e[0m"
        read -rp "Enter NeoForge version (e.g. 21.1.249): " target_neo_ver
    fi

    if [ -z "$target_neo_ver" ]; then return; fi

    echo -e "\e[1;32m[+] Selected NeoForge version: $target_neo_ver\e[0m"
    local neo_installer_url="https://maven.neoforged.net/releases/net/neoforged/neoforge/$target_neo_ver/neoforge-$target_neo_ver-installer.jar"
    local tmp_installer="/tmp/neoforge-$target_neo_ver-installer.jar"

    echo -e "\e[1;34m==> Downloading NeoForge Installer...\e[0m"
    download_single_file_with_progress "$neo_installer_url" "$tmp_installer" "NeoForge Inst."
    if [ ! -s "$tmp_installer" ]; then
        echo -e "\e[1;31m[-] Failed to download NeoForge installer.\e[0m"
        rm -f "$tmp_installer"
        read -rp "Press Enter to return..."
        return
    fi

    [ -f "$MC_DIR/launcher_profiles.json" ] || echo '{"profiles":{}}' > "$MC_DIR/launcher_profiles.json"

    echo -e "\e[1;34m==> Running NeoForge Installer (this may take 1-2 minutes)...\e[0m"
    java -jar "$tmp_installer" --installClient "$MC_DIR"
    rm -f "$tmp_installer"

    echo -e "\n\e[1;32m[+] NeoForge $target_neo_ver installed successfully!\e[0m"
    read -rp "Press Enter to return..."
}

install_forge_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m           MINECRAFT FORGE INSTALLER          \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"

    echo -e "\e[1;33mPopular Minecraft Versions for Forge:\e[0m"
    echo -e "  \e[1;32m[1]\e[0m 1.20.1"
    echo -e "  \e[1;32m[2]\e[0m 1.19.2"
    echo -e "  \e[1;32m[3]\e[0m 1.18.2"
    echo -e "  \e[1;32m[4]\e[0m 1.16.5"
    echo -e "  \e[1;32m[5]\e[0m 1.12.2"
    echo -e "  \e[1;33m[c]\e[0m Custom Minecraft Version"
    echo -e "  \e[1;31m[b]\e[0m Back"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select option: " fge_opt

    local target_mc=""
    case "$fge_opt" in
        1) target_mc="1.20.1" ;;
        2) target_mc="1.19.2" ;;
        3) target_mc="1.18.2" ;;
        4) target_mc="1.16.5" ;;
        5) target_mc="1.12.2" ;;
        c|C) read -rp "Enter exact Minecraft version: " target_mc ;;
        *) return ;;
    esac

    if [ -z "$target_mc" ]; then return; fi

    ensure_vanilla_installed "$target_mc" || {
        read -rp "Press Enter to return..."
        return
    }

    echo -e "\n\e[1;34m==> Fetching Forge promotions...\e[0m"
    local forge_promos
    forge_promos=$(curl -s "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")
    local forge_ver
    forge_ver=$(echo "$forge_promos" | jq -r --arg v "$target_mc" '.promos[$v + "-recommended"] // .promos[$v + "-latest"] // empty')

    if [ -z "$forge_ver" ]; then
        read -rp "Enter Forge version (e.g. 47.4.10): " forge_ver
    fi

    if [ -z "$forge_ver" ]; then return; fi

    echo -e "\e[1;32m[+] Selected Forge version: $target_mc-$forge_ver\e[0m"
    local forge_installer_url="https://maven.minecraftforge.net/net/minecraftforge/forge/$target_mc-$forge_ver/forge-$target_mc-$forge_ver-installer.jar"
    local tmp_installer="/tmp/forge-$target_mc-$forge_ver-installer.jar"

    echo -e "\e[1;34m==> Downloading Forge Installer...\e[0m"
    download_single_file_with_progress "$forge_installer_url" "$tmp_installer" "Forge Inst."
    if [ ! -s "$tmp_installer" ]; then
        echo -e "\e[1;31m[-] Failed to download Forge installer.\e[0m"
        rm -f "$tmp_installer"
        read -rp "Press Enter to return..."
        return
    fi

    [ -f "$MC_DIR/launcher_profiles.json" ] || echo '{"profiles":{}}' > "$MC_DIR/launcher_profiles.json"

    echo -e "\e[1;34m==> Running Forge Installer...\e[0m"
    java -jar "$tmp_installer" --installClient "$MC_DIR"
    rm -f "$tmp_installer"

    echo -e "\n\e[1;32m[+] Minecraft Forge $target_mc-$forge_ver installed successfully!\e[0m"
    read -rp "Press Enter to return..."
}

install_quilt_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m             QUILT LOADER INSTALLER           \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"
    read -rp "Enter Minecraft version for Quilt (e.g. 1.21.1, 1.20.4): " target_mc
    if [ -z "$target_mc" ]; then return; fi

    ensure_vanilla_installed "$target_mc" || {
        read -rp "Press Enter to return..."
        return
    }

    local quilt_installer="$CLI_DIR/quilt-installer.jar"
    if [ ! -s "$quilt_installer" ]; then
        echo -e "\e[1;34m==> Downloading Quilt Installer...\e[0m"
        download_single_file_with_progress "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/0.11.0/quilt-installer-0.11.0.jar" "$quilt_installer" "Quilt Inst."
    fi

    [ -f "$MC_DIR/launcher_profiles.json" ] || echo '{"profiles":{}}' > "$MC_DIR/launcher_profiles.json"
    echo -e "\e[1;34m==> Running Quilt Installer...\e[0m"
    java -jar "$quilt_installer" install client "$target_mc" --install-dir="$MC_DIR"

    echo -e "\n\e[1;32m[+] Quilt Loader installed successfully for $target_mc!\e[0m"
    read -rp "Press Enter to return..."
}

install_new_version() {
    while true; do
        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m           MINECRAFT VERSION INSTALLER        \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "Target Directory: \e[1;32m$MC_DIR\e[0m\n"
        echo -e "Select Version / Loader to Install:"
        echo -e "  \e[1;32m[1]\e[0m Official Vanilla Releases (1.21.1, 1.20.4, 1.16.5, etc.)"
        echo -e "  \e[1;34m[2]\e[0m Official Snapshots & Pre-releases (Testing builds)"
        echo -e "  \e[1;35m[3]\e[0m Fabric Loader (High performance mod loader)"
        echo -e "  \e[1;33m[4]\e[0m NeoForge Loader (Modern Forge mod loader)"
        echo -e "  \e[1;33m[5]\e[0m Minecraft Forge (Classic mod loader)"
        echo -e "  \e[1;35m[6]\e[0m Quilt Loader (Modern modular mod loader)"
        echo -e "  \e[1;37m[c]\e[0m Custom Mojang Version ID"
        echo -e "  \e[1;31m[b]\e[0m Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select installer option: " i_choice

        case "$i_choice" in
            1) install_vanilla_releases ;;
            2) install_snapshot_version ;;
            3) install_fabric_version ;;
            4) install_neoforge_version ;;
            5) install_forge_version ;;
            6) install_quilt_version ;;
            c|C)
                read -rp "Enter exact Mojang version ID: " cust_id
                [ -n "$cust_id" ] && download_vanilla_version "$cust_id" && read -rp "Press Enter to return..."
                ;;
            b|B) break ;;
        esac
    done
}

# ==========================================
# OFFLINE SKINS & CAPES MANAGER
# ==========================================
manage_offline_skins() {
    while true; do
        mapfile -t OFF_ACCS < <(jq -c '.accounts[] | select(.type=="offline")' "$ACCOUNTS_DB" 2>/dev/null)
        if [ ${#OFF_ACCS[@]} -eq 0 ]; then
            clear
            echo -e "\e[1;35m==============================================\e[0m"
            echo -e "\e[1;36m         OFFLINE SKINS & CAPES MANAGER        \e[0m"
            echo -e "\e[1;35m==============================================\e[0m"
            echo -e "\e[1;33mNo offline accounts registered yet.\e[0m"
            echo -e "Please create an offline account first in Account Manager.\n"
            echo -e "  \e[1;32m[c]\e[0m Create Offline Account Now"
            echo -e "  \e[1;31m[b]\e[0m Back"
            read -rp "Select option: " no_acc_choice
            case "$no_acc_choice" in
                c|C)
                    read -rp "Enter Username: " off_u
                    if [ -n "$off_u" ]; then
                        off_hash=$(printf "OfflinePlayer:%s" "$off_u" | md5sum | awk '{print $1}')
                        off_uuid="${off_hash:0:8}-${off_hash:8:4}-3${off_hash:13:3}-${off_hash:16:4}-${off_hash:20:12}"
                        new_entry=$(jq -n --arg u "$off_u" --arg id "$off_uuid" '{type: "offline", username: $u, uuid: $id, token: "0", server: null}')
                        ensure_accounts_db
                        jq --argjson entry "$new_entry" \
                            '.accounts = [((.accounts // [])[] | select(.username != $entry.username or .type != "offline"))] + [$entry]' \
                            "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                        echo -e "\e[1;32m[+] Offline account '$off_u' registered.\e[0m"
                        sleep 1
                    fi
                    ;;
                *) return ;;
            esac
            continue
        fi

        local cur_acc="${OFF_ACCS[0]}"
        if [ ${#OFF_ACCS[@]} -gt 1 ]; then
            clear
            echo -e "\e[1;35m==============================================\e[0m"
            echo -e "\e[1;36m           SELECT OFFLINE PROFILE             \e[0m"
            echo -e "\e[1;35m==============================================\e[0m"
            for i in "${!OFF_ACCS[@]}"; do
                u=$(echo "${OFF_ACCS[$i]}" | jq -r '.username')
                printf "  \e[1;32m[%d]\e[0m %s\n" "$((i+1))" "$u"
            done
            echo -e "  \e[1;31m[b]\e[0m Back"
            echo -e "\e[1;35m----------------------------------------------\e[0m"
            read -rp "Select profile: " p_choice
            if [[ "$p_choice" =~ ^[0-9]+$ ]] && [ "$p_choice" -ge 1 ] && [ "$p_choice" -le "${#OFF_ACCS[@]}" ]; then
                cur_acc="${OFF_ACCS[$((p_choice-1))]}"
            else
                return
            fi
        fi

        local u_name skin_p cape_p srv_p
        u_name=$(echo "$cur_acc" | jq -r '.username')
        skin_p=$(echo "$cur_acc" | jq -r '.skin // "None"')
        cape_p=$(echo "$cur_acc" | jq -r '.cape // "None"')
        srv_p=$(echo "$cur_acc" | jq -r '.skin_server // "None"')

        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m         OFFLINE SKINS & CAPES MANAGER        \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        printf "  \e[1;37mAccount:\e[0m        \e[1;32m%s\e[0m (Offline)\n" "$u_name"
        printf "  \e[1;37mSkin File:\e[0m      %s\n" "$skin_p"
        printf "  \e[1;37mCape File:\e[0m      %s\n" "$cape_p"
        printf "  \e[1;37mSkin Server:\e[0m    \e[1;34m%s\e[0m\n" "$srv_p"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        echo -e "  \e[1;32m[1]\e[0m Set Skin Image (.png file or image URL)"
        echo -e "  \e[1;32m[2]\e[0m Set Cape Image (.png file or image URL)"
        echo -e "  \e[1;33m[3]\e[0m Set Custom Authlib / Skin Server URL"
        echo -e "  \e[1;31m[4]\e[0m Clear Skin & Cape"
        echo -e "  \e[1;32m[b]\e[0m Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select option: " s_choice

        case "$s_choice" in
            1)
                echo -e "\n\e[1;36m-- Set Skin for $u_name --\e[0m"
                echo "Enter either:"
                echo "  • Absolute path to a .png file (e.g. /home/.../skin.png)"
                echo "  • Image URL (e.g. https://.../skin.png)"
                read -rp "Input: " in_skin
                if [ -n "$in_skin" ]; then
                    local dest="$SKINS_DIR/${u_name}.png"
                    if [ -f "$in_skin" ]; then
                        cp "$in_skin" "$dest"
                    elif [[ "$in_skin" =~ ^https?:// ]]; then
                        curl -sL "$in_skin" -o "$dest"
                    fi
                    if [ -s "$dest" ]; then
                        ensure_accounts_db
                        jq --arg u "$u_name" --arg p "$dest" \
                            '.accounts = [((.accounts // [])[] | if (.username == $u and .type == "offline") then (.skin = $p) else . end)]' \
                            "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                        for inst_csl in "$VERSIONS_DIR"/*/CustomSkinLoader/LocalSkin/skins; do
                            [ -d "$inst_csl" ] && cp "$dest" "$inst_csl/${u_name}.png" 2>/dev/null
                        done
                        echo -e "\e[1;32m[+] Skin set successfully!\e[0m"
                    else
                        echo -e "\e[1;31m[-] Failed to load skin image.\e[0m"
                    fi
                    sleep 1.5
                fi
                ;;
            2)
                echo -e "\n\e[1;36m-- Set Cape for $u_name --\e[0m"
                read -rp "Enter path to cape .png file or direct image URL: " in_cape
                if [ -n "$in_cape" ]; then
                    local dest="$CAPES_DIR/${u_name}.png"
                    if [ -f "$in_cape" ]; then
                        cp "$in_cape" "$dest"
                    elif [[ "$in_cape" =~ ^https?:// ]]; then
                        curl -sL "$in_cape" -o "$dest"
                    fi
                    if [ -s "$dest" ]; then
                        ensure_accounts_db
                        jq --arg u "$u_name" --arg p "$dest" \
                            '.accounts = [((.accounts // [])[] | if (.username == $u and .type == "offline") then (.cape = $p) else . end)]' \
                            "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                        for inst_csl in "$VERSIONS_DIR"/*/CustomSkinLoader/LocalSkin/capes; do
                            [ -d "$inst_csl" ] && cp "$dest" "$inst_csl/${u_name}.png" 2>/dev/null
                        done
                        echo -e "\e[1;32m[+] Cape set successfully!\e[0m"
                    else
                        echo -e "\e[1;31m[-] Failed to load cape image.\e[0m"
                    fi
                    sleep 1.5
                fi
                ;;
            3)
                echo -e "\n\e[1;36m-- Configure Skin / Auth Server --\e[0m"
                echo "Enter Yggdrasil / Skin API server URL (e.g. https://elethiya.com/api/yggdrasil)"
                echo "Leave empty to disable custom skin server."
                read -rp "Server URL: " custom_srv
                ensure_accounts_db
                if [ -n "$custom_srv" ]; then
                    jq --arg u "$u_name" --arg s "$custom_srv" \
                        '.accounts = [((.accounts // [])[] | if (.username == $u and .type == "offline") then (.skin_server = $s) else . end)]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;32m[+] Custom skin server set to: $custom_srv\e[0m"
                else
                    jq --arg u "$u_name" \
                        '.accounts = [((.accounts // [])[] | if (.username == $u and .type == "offline") then del(.skin_server) else . end)]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;33m[*] Custom skin server removed.\e[0m"
                fi
                sleep 1.5
                ;;
            4)
                rm -f "$SKINS_DIR/${u_name}.png" "$CAPES_DIR/${u_name}.png"
                for inst_csl in "$VERSIONS_DIR"/*/CustomSkinLoader/LocalSkin; do
                    [ -d "$inst_csl" ] && rm -f "$inst_csl/skins/${u_name}.png" "$inst_csl/capes/${u_name}.png" 2>/dev/null
                done
                ensure_accounts_db
                jq --arg u "$u_name" \
                    '.accounts = [((.accounts // [])[] | if (.username == $u and .type == "offline") then (del(.skin) | del(.cape)) else . end)]' \
                    "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                echo -e "\e[1;32m[+] Skin and cape cleared.\e[0m"
                sleep 1.2
                ;;
            b|B)
                break
                ;;
        esac
    done
}

# ==========================================
# SETTINGS / DIRECTORY & RAM CONFIGURATION TUI
# ==========================================
configure_settings() {
    while true; do
        sync_directories
        MAX_RAM=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE")
        MIN_RAM=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE")
        JVM_ARGS=$(jq -r '.jvm_args // ""' "$SETTINGS_FILE")

        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m       LAUNCHER DIRECTORY & RAM SETTINGS      \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        printf "  \e[1;33m[1]\e[0m Game Directory     : \e[1;32m%s\e[0m\n" "$MC_DIR"
        printf "  \e[1;33m[2]\e[0m Maximum RAM (-Xmx) : \e[1;32m%s\e[0m\n" "$MAX_RAM"
        printf "  \e[1;33m[3]\e[0m Minimum RAM (-Xms) : \e[1;32m%s\e[0m\n" "$MIN_RAM"
        printf "  \e[1;33m[4]\e[0m Custom JVM Flags   : \e[1;34m%s\e[0m\n" "$JVM_ARGS"
        echo -e "\n  \e[1;32m[b]\e[0m Save and Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select option: " s_choice

        case "$s_choice" in
            1)
                echo -e "\nChoose Game Directory Location:"
                echo -e "  [1] Standard ~/.minecraft ($HOME/.minecraft)"
                echo -e "  [2] Inside launcher directory ($CLI_DIR/.minecraft)"
                echo -e "  [3] Custom full path"
                read -rp "Select [1-3, default: 1]: " dir_choice
                case "$dir_choice" in
                    2)
                        mkdir -p "$CLI_DIR/.minecraft"
                        jq --arg d "$CLI_DIR/.minecraft" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        ;;
                    3)
                        read -rp "Enter directory path: " custom_dir
                        custom_dir="${custom_dir/#\~/$HOME}"
                        if [ -n "$custom_dir" ]; then
                            mkdir -p "$custom_dir"
                            jq --arg d "$custom_dir" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        fi
                        ;;
                    *)
                        jq --arg d "$HOME/.minecraft" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        ;;
                esac
                sync_directories
                ;;
            2)
                read -rp "Enter Maximum RAM (e.g. 4G, 6G, 4096M): " new_max
                if [[ "$new_max" =~ ^[0-9]+[GMgm]$ ]]; then
                    new_max="${new_max^^}"
                    jq --arg r "$new_max" '.max_ram = $r' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                fi
                ;;
            3)
                read -rp "Enter Minimum RAM (e.g. 2G, 2048M): " new_min
                if [[ "$new_min" =~ ^[0-9]+[GMgm]$ ]]; then
                    new_min="${new_min^^}"
                    jq --arg r "$new_min" '.min_ram = $r' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                fi
                ;;
            4)
                read -rp "Enter extra JVM flags: " new_flags
                jq --arg f "$new_flags" '.jvm_args = $f' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                ;;
            b|B)
                break
                ;;
        esac
    done
}

# ==========================================
# ACCOUNT MANAGER TUI
# ==========================================
manage_accounts() {
    while true; do
        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m           ACCOUNT MANAGER & PROFILES         \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"

        mapfile -t ACCOUNTS < <(jq -c '.accounts[]' "$ACCOUNTS_DB" 2>/dev/null)
        local total_acc=${#ACCOUNTS[@]}

        if [ "$total_acc" -gt 0 ]; then
            echo -e "\e[1;33mRegistered Accounts:\e[0m"
            for i in "${!ACCOUNTS[@]}"; do
                acc="${ACCOUNTS[$i]}"
                u_name=$(echo "$acc" | jq -r '.username')
                a_type=$(echo "$acc" | jq -r '.type')
                a_srv=$(echo "$acc" | jq -r '.server // "N/A"')
                printf "  \e[1;32m[%d]\e[0m %-18s (\e[1;34m%s\e[0m | %s)\n" "$((i+1))" "$u_name" "$a_type" "$a_srv"
            done
            echo ""
        else
            echo -e "\e[1;33mNo accounts registered.\e[0m\n"
        fi

        echo -e "  \e[1;32m[a]\e[0m Add New Authlib / Yggdrasil Account"
        echo -e "  \e[1;32m[o]\e[0m Add New Offline Account"
        if [ "$total_acc" -gt 0 ]; then
            echo -e "  \e[1;31m[d]\e[0m Delete an Account"
        fi
        echo -e "  \e[1;32m[b]\e[0m Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select an option: " a_opt

        case "$a_opt" in
            a|A)
                echo -e "\n\e[1;36m-- Add Authlib Account --\e[0m"
                read -rp "Authlib API Root URL [default: https://elethiya.com/api/yggdrasil]: " in_srv
                in_srv="${in_srv:-https://elethiya.com/api/yggdrasil}"
                read -rp "Username / Email: " in_user
                read -rsp "Password: " in_pass
                echo ""

                client_tok=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | md5sum | head -c 32)
                auth_payload=$(jq -n \
                  --arg user "$in_user" --arg pass "$in_pass" --arg client "$client_tok" \
                  '{agent: {name: "Minecraft", version: 1}, username: $user, password: $pass, clientToken: $client, requestUser: true}')

                echo -e "\e[1;34m==> Authenticating with $in_srv...\e[0m"
                auth_resp=$(curl -s --connect-timeout 8 --max-time 15 -X POST "$in_srv/authserver/authenticate" \
                  -H "Content-Type: application/json" \
                  -d "$auth_payload")

                if [ -z "$auth_resp" ]; then
                    echo -e "\e[1;31m[-] Connection failed: Server did not respond or URL is unreachable.\e[0m"
                    read -rp "Press Enter to continue..."
                    continue
                fi

                if ! echo "$auth_resp" | jq -e . >/dev/null 2>&1; then
                    echo -e "\e[1;31m[-] Invalid response: Server returned non-JSON data (e.g. 404/502 error or offline server).\e[0m"
                    echo -e "\e[1;33m[*] Please verify the Authlib API Root URL and ensure the server is online.\e[0m"
                    read -rp "Press Enter to continue..."
                    continue
                fi

                tok=$(echo "$auth_resp" | jq -r '.accessToken // empty' 2>/dev/null)
                uid=$(echo "$auth_resp" | jq -r '.selectedProfile.id // empty' 2>/dev/null)
                pname=$(echo "$auth_resp" | jq -r '.selectedProfile.name // empty' 2>/dev/null)

                if [ -n "$tok" ] && [ -n "$pname" ]; then
                    new_entry=$(jq -n \
                        --arg u "$pname" --arg id "$uid" --arg t "$tok" --arg s "$in_srv" --arg ct "$client_tok" \
                        '{type: "authlib", username: $u, uuid: $id, token: $t, server: $s, clientToken: $ct}')

                    ensure_accounts_db
                    jq --argjson entry "$new_entry" \
                        '.accounts = [((.accounts // [])[] | select(.username != $entry.username or (.server // "") != ($entry.server // "")))] + [$entry]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;32m[+] Account '$pname' added.\e[0m"
                    sleep 1.2
                else
                    err_check=$(echo "$auth_resp" | jq -r '.errorMessage // .error // .message // "Authentication failed"' 2>/dev/null)
                    echo -e "\e[1;31m[-] $err_check\e[0m"
                    read -rp "Press Enter to continue..."
                fi
                ;;
            o|O)
                echo -e "\n\e[1;36m-- Add Offline Account --\e[0m"
                read -rp "Enter Username: " off_u
                if [ -n "$off_u" ]; then
                    off_hash=$(printf "OfflinePlayer:%s" "$off_u" | md5sum | awk '{print $1}')
                    off_uuid="${off_hash:0:8}-${off_hash:8:4}-3${off_hash:13:3}-${off_hash:16:4}-${off_hash:20:12}"
                    new_entry=$(jq -n --arg u "$off_u" --arg id "$off_uuid" '{type: "offline", username: $u, uuid: $id, token: "0", server: null}')
                    ensure_accounts_db
                    jq --argjson entry "$new_entry" \
                        '.accounts = [((.accounts // [])[] | select(.username != $entry.username or .type != "offline"))] + [$entry]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;32m[+] Offline account '$off_u' registered.\e[0m"
                    sleep 1.2
                fi
                ;;
            d|D)
                read -rp "Enter account number to delete: " d_idx
                if [[ "$d_idx" =~ ^[0-9]+$ ]] && [ "$d_idx" -ge 1 ] && [ "$d_idx" -le "$total_acc" ]; then
                    target_del="${ACCOUNTS[$((d_idx-1))]}"
                    del_u=$(echo "$target_del" | jq -r '.username')
                    del_t=$(echo "$target_del" | jq -r '.type')
                    del_s=$(echo "$target_del" | jq -r '.server // empty')
                    ensure_accounts_db
                    jq --arg u "$del_u" --arg t "$del_t" --arg s "$del_s" \
                        '.accounts = [((.accounts // [])[] | select(.username != $u or .type != $t or (.server // "") != $s))]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;32m[+] Account deleted.\e[0m"
                    sleep 1
                fi
                ;;
            b|B)
                break
                ;;
        esac
    done
}

manage_mods_and_packs() {
    while true; do
        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m         MODS & RESOURCE PACKS MANAGER        \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "Each version has shortcut folders in: \e[1;33m$CLI_DIR/versions/<version>/\e[0m"
        echo -e "  • mods/          (Place your mod .jar files here)"
        echo -e "  • resourcepacks/ (Place texture/resource pack .zip files)"
        echo -e "  • shaderpacks/   (Place shader .zip files)"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        echo -e "\e[1;33mInstalled Game Versions & Mod Counts:\e[0m"
        for i in "${!INSTALLED_VERSIONS[@]}"; do
            v_name="${INSTALLED_VERSIONS[$i]}"
            v_mod_dir="$VERSIONS_DIR/$v_name/mods"
            local count=0
            if [ -d "$v_mod_dir" ]; then
                count=$(find "$v_mod_dir" -maxdepth 1 -name "*.jar" 2>/dev/null | wc -l)
            fi
            printf "  \e[1;32m[%d]\e[0m %-30s (\e[1;34m%d mods\e[0m)\n" "$((i+1))" "$v_name" "$count"
        done
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        echo -e "  \e[1;32m[1-${#INSTALLED_VERSIONS[@]}]\e[0m Select version to manage mods / resource packs / shaders"
        echo -e "  \e[1;36m[o]\e[0m Open main versions directory ($CLI_DIR/versions) in file manager"
        echo -e "  \e[1;31m[b]\e[0m Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select option: " mp_choice

        if [ "$mp_choice" == "b" ] || [ "$mp_choice" == "B" ]; then
            break
        elif [ "$mp_choice" == "o" ] || [ "$mp_choice" == "O" ]; then
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$CLI_DIR/versions" >/dev/null 2>&1 &
                echo -e "\e[1;32m[+] Opened $CLI_DIR/versions in file manager.\e[0m"
                sleep 1
            else
                echo -e "Versions shortcut path: \e[1;32m$CLI_DIR/versions\e[0m"
                read -rp "Press Enter to continue..."
            fi
        elif [[ "$mp_choice" =~ ^[0-9]+$ ]] && [ "$mp_choice" -ge 1 ] && [ "$mp_choice" -le "${#INSTALLED_VERSIONS[@]}" ]; then
            local target_ver="${INSTALLED_VERSIONS[$((mp_choice-1))]}"
            local target_mods="$VERSIONS_DIR/$target_ver/mods"
            local target_rp="$VERSIONS_DIR/$target_ver/resourcepacks"
            local target_sp="$VERSIONS_DIR/$target_ver/shaderpacks"
            local cli_ver_dir="$CLI_DIR/versions/$target_ver"

            mkdir -p "$target_mods" "$target_rp" "$target_sp"
            ln -sfn "$target_mods" "$CLI_DIR/mods"
            ln -sfn "$target_rp" "$CLI_DIR/resourcepacks"
            ln -sfn "$target_sp" "$CLI_DIR/shaderpacks"

            echo -e "\n\e[1;34m==> Version: $target_ver\e[0m"
            echo -e "Version Shortcuts : \e[1;32m$cli_ver_dir\e[0m"
            echo -e "Actual Mods Path  : \e[1;33m$target_mods\e[0m"
            echo -e "\nInstalled Mods:"
            local has_mods=false
            for m in "$target_mods"/*; do
                if [ -f "$m" ]; then
                    echo -e "  • \e[1;32m$(basename "$m")\e[0m"
                    has_mods=true
                fi
            done
            [ "$has_mods" = false ] && echo -e "  \e[1;30m(No mods installed in this version folder yet)\e[0m"
            echo ""

            echo -e "Open folder in file manager:"
            echo -e "  \e[1;32m[1]\e[0m Open Mods folder"
            echo -e "  \e[1;32m[2]\e[0m Open Resource Packs folder"
            echo -e "  \e[1;32m[3]\e[0m Open Shader Packs folder"
            echo -e "  \e[1;32m[4]\e[0m Open Version Shortcut folder ($cli_ver_dir)"
            echo -e "  \e[1;31m[b]\e[0m Back"
            read -rp "Select option [1-4, or b]: " open_opt

            case "$open_opt" in
                1) command -v xdg-open >/dev/null 2>&1 && xdg-open "$target_mods" >/dev/null 2>&1 & ;;
                2) command -v xdg-open >/dev/null 2>&1 && xdg-open "$target_rp" >/dev/null 2>&1 & ;;
                3) command -v xdg-open >/dev/null 2>&1 && xdg-open "$target_sp" >/dev/null 2>&1 & ;;
                4) command -v xdg-open >/dev/null 2>&1 && xdg-open "$cli_ver_dir" >/dev/null 2>&1 & ;;
            esac
            sleep 0.8
        fi
    done
}

# ==========================================
# MAIN INTERACTIVE MENU
# ==========================================
while true; do
    sync_directories
    MAX_RAM=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE")
    MIN_RAM=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE")

    mapfile -t INSTALLED_VERSIONS < <(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)
    mapfile -t ACCOUNTS < <(jq -c '.accounts[]' "$ACCOUNTS_DB" 2>/dev/null)

    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m             MINECRAFT CLI LAUNCHER           \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"
    printf "  \e[1;37mGame Path:\e[0m      \e[1;32m%s\e[0m\n" "$MC_DIR"
    printf "  \e[1;37mVersions Dir:\e[0m   \e[1;32m%s\e[0m\n" "$CLI_DIR/versions"
    printf "  \e[1;37mActive Mods:\e[0m    \e[1;32m%s\e[0m\n" "$CLI_DIR/mods"
    printf "  \e[1;37mRAM:\e[0m            -Xms\e[1;32m%s\e[0m / -Xmx\e[1;32m%s\e[0m\n" "$MIN_RAM" "$MAX_RAM"
    echo -e "\e[1;35m----------------------------------------------\e[0m"

    echo -e "\e[1;33mInstalled Game Versions:\e[0m"
    if [ ${#INSTALLED_VERSIONS[@]} -eq 0 ]; then
        echo -e "  \e[1;31mNo versions installed in current directory.\e[0m"
    else
        for i in "${!INSTALLED_VERSIONS[@]}"; do
            v_name="${INSTALLED_VERSIONS[$i]}"
            v_json="$VERSIONS_DIR/$v_name/$v_name.json"
            v_badge="\e[1;32m(Vanilla)\e[0m"
            if [[ "$v_name" =~ [Ff]abric ]] || ( [ -f "$v_json" ] && grep -qi "fabric" "$v_json" 2>/dev/null ); then
                v_badge="\e[1;35m(Fabric)\e[0m"
            elif [[ "$v_name" =~ [Nn]eo[Ff]orge ]] || ( [ -f "$v_json" ] && grep -qi "neoforge" "$v_json" 2>/dev/null ); then
                v_badge="\e[1;33m(NeoForge)\e[0m"
            elif [[ "$v_name" =~ [Ff]orge ]] || ( [ -f "$v_json" ] && grep -qi "minecraftforge" "$v_json" 2>/dev/null ); then
                v_badge="\e[1;33m(Forge)\e[0m"
            elif [[ "$v_name" =~ [Qq]uilt ]] || ( [ -f "$v_json" ] && grep -qi "quilt" "$v_json" 2>/dev/null ); then
                v_badge="\e[1;35m(Quilt)\e[0m"
            elif [[ "$v_name" =~ [Oo]pti[Ff]ine ]] || ( [ -f "$v_json" ] && grep -qi "optifine" "$v_json" 2>/dev/null ); then
                v_badge="\e[1;36m(OptiFine)\e[0m"
            elif [[ "$v_name" =~ ^[0-9]{2}w[0-9]{2}[a-z] ]] || ( [ -f "$v_json" ] && [ "$(jq -r '.type // empty' "$v_json" 2>/dev/null)" == "snapshot" ] ); then
                v_badge="\e[1;34m(Snapshot)\e[0m"
            fi
            printf "  \e[1;32m[%d]\e[0m %-30s %b\n" "$((i+1))" "$v_name" "$v_badge"
        done
    fi

    echo -e "\n\e[1;33mCommands & Tools:\e[0m"
    echo -e "  \e[1;32m[i]\e[0m Install Version / Mod Loader (Vanilla, Fabric, NeoForge, Forge, Quilt)"
    echo -e "  \e[1;35m[m]\e[0m Manage Mods & Resource Packs"
    echo -e "  \e[1;36m[s]\e[0m Offline Skins & Capes Manager"
    echo -e "  \e[1;33m[r]\e[0m Configure Directory, RAM & JVM Flags"
    echo -e "  \e[1;33m[u]\e[0m Manage Accounts (Authlib / Offline)"
    echo -e "  \e[1;31m[q]\e[0m Quit"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select version number to launch or tool option: " main_choice

    case "$main_choice" in
        i|I)
            install_new_version
            ;;
        m|M)
            manage_mods_and_packs
            ;;
        s|S)
            manage_offline_skins
            ;;
        r|R)
            configure_settings
            ;;
        u|U)
            manage_accounts
            ;;
        q|Q)
            exit 0
            ;;
        *)
            if [[ "$main_choice" =~ ^[0-9]+$ ]] && [ "$main_choice" -ge 1 ] && [ "$main_choice" -le "${#INSTALLED_VERSIONS[@]}" ]; then
                SELECTED_VERSION="${INSTALLED_VERSIONS[$((main_choice-1))]}"
                break
            fi
            ;;
    esac
done

# ==========================================
# SELECT ACTIVE ACCOUNT
# ==========================================
if [ ${#ACCOUNTS[@]} -eq 0 ]; then
    echo -e "\n\e[1;31m[-] No accounts found. Please add an account first.\e[0m"
    manage_accounts
    mapfile -t ACCOUNTS < <(jq -c '.accounts[]' "$ACCOUNTS_DB" 2>/dev/null)
fi

while true; do
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m           SELECT ACCOUNT TO PLAY             \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"
    for i in "${!ACCOUNTS[@]}"; do
        acc="${ACCOUNTS[$i]}"
        u_name=$(echo "$acc" | jq -r '.username')
        a_type=$(echo "$acc" | jq -r '.type')
        a_srv=$(echo "$acc" | jq -r '.server // "Local"')
        printf "  \e[1;32m[%d]\e[0m %-18s (\e[1;34m%s\e[0m | %s)\n" "$((i+1))" "$u_name" "$a_type" "$a_srv"
    done
    echo -e "  \e[1;31m[b]\e[0m Cancel / Exit"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select account number or [b] to cancel: " pick_acc

    if [ "$pick_acc" == "b" ] || [ "$pick_acc" == "B" ]; then
        echo -e "\e[1;33m[*] Launch cancelled.\e[0m"
        exit 0
    fi

    if [[ "$pick_acc" =~ ^[0-9]+$ ]] && [ "$pick_acc" -ge 1 ] && [ "$pick_acc" -le "${#ACCOUNTS[@]}" ]; then
        SELECTED_RAW="${ACCOUNTS[$((pick_acc-1))]}"
        SELECTED_TYPE=$(echo "$SELECTED_RAW" | jq -r '.type')
        SELECTED_USER=$(echo "$SELECTED_RAW" | jq -r '.username')
        SELECTED_UUID=$(echo "$SELECTED_RAW" | jq -r '.uuid')
        SELECTED_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.token // "0"')
        SELECTED_SERVER=$(echo "$SELECTED_RAW" | jq -r '.server // empty')
        SELECTED_CLIENT_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.clientToken // empty')

        SERVER_ONLINE=true
        if [ "$SELECTED_TYPE" == "authlib" ]; then
            echo -e "\n\e[1;34m==> Checking authentication server status...\e[0m"
            SRV_STATUS=$(curl -sL --connect-timeout 4 --max-time 6 -o /dev/null -w "%{http_code}" "$SELECTED_SERVER")

            if [ "$SRV_STATUS" -eq 200 ] || [ "$SRV_STATUS" -eq 204 ]; then
                echo -e "\e[1;34m==> Validating session with $SELECTED_SERVER...\e[0m"
                VAL_CODE=$(curl -s --connect-timeout 6 --max-time 8 -o /dev/null -w "%{http_code}" -X POST "$SELECTED_SERVER/authserver/validate" \
                    -H "Content-Type: application/json" \
                    -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\"}")

                if [ "$VAL_CODE" -ne 204 ] && [ "$VAL_CODE" -ne 200 ]; then
                    echo -e "\e[1;33m[*] Refreshing session...\e[0m"
                    REFRESH_RESP=$(curl -s --connect-timeout 6 --max-time 8 -X POST "$SELECTED_SERVER/authserver/refresh" \
                        -H "Content-Type: application/json" \
                        -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\", \"requestUser\": true}")

                    if [ -n "$REFRESH_RESP" ] && echo "$REFRESH_RESP" | jq -e . >/dev/null 2>&1; then
                        NEW_TOKEN=$(echo "$REFRESH_RESP" | jq -r '.accessToken // empty' 2>/dev/null)
                        if [ -n "$NEW_TOKEN" ]; then
                            ensure_accounts_db
                            jq --arg user "$SELECTED_USER" --arg srv "$SELECTED_SERVER" --arg tok "$NEW_TOKEN" \
                               '.accounts = [((.accounts // [])[] | if (.username == $user and (.server // "") == $srv) then (.token = $tok) else . end)]' \
                               "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                        fi
                    fi
                fi
            else
                SERVER_ONLINE=false
                echo -e "\n\e[1;31m[-] Authlib server is currently offline or unreachable (HTTP ${SRV_STATUS:-Down}).\e[0m"
                echo -e "\e[1;33m[*] Would you like to launch the game in offline mode instead?\e[0m"
                read -rp "Launch in offline mode? [y/N]: " confirm_offline
                if [[ "$confirm_offline" =~ ^[yY]([eE][sS])?$ ]]; then
                    echo -e "\e[1;32m[+] Launching game in offline mode...\e[0m"
                    SELECTED_TYPE="offline"
                    SELECTED_TOKEN="0"
                    sleep 1.2
                else
                    echo -e "\e[1;33m[*] Launch cancelled.\e[0m"
                    sleep 1
                    continue
                fi
            fi
        fi
        break
    fi
done

# ==========================================
# CONSTRUCT RUNTIME CLASSPATH & DETECT GAME DIR
# ==========================================
VERSION_JSON="$VERSIONS_DIR/$SELECTED_VERSION/$SELECTED_VERSION.json"
MAIN_CLASS=$(jq -r '.mainClass' "$VERSION_JSON")
INHERITS_FROM=$(jq -r '.inheritsFrom // empty' "$VERSION_JSON")

ACTIVE_GAMEDIR="$VERSIONS_DIR/$SELECTED_VERSION"
mkdir -p "$ACTIVE_GAMEDIR/mods" "$ACTIVE_GAMEDIR/resourcepacks" "$ACTIVE_GAMEDIR/shaderpacks" "$ACTIVE_GAMEDIR/saves" "$ACTIVE_GAMEDIR/config"

# Update unhidden top-level symlinks in $CLI_DIR for easy access
ln -sfn "$ACTIVE_GAMEDIR/mods" "$CLI_DIR/mods"
ln -sfn "$ACTIVE_GAMEDIR/resourcepacks" "$CLI_DIR/resourcepacks"
ln -sfn "$ACTIVE_GAMEDIR/shaderpacks" "$CLI_DIR/shaderpacks"

# Copy existing saves if version saves folder is brand new
if [ -d "$MC_DIR/saves" ] && [ -z "$(ls -A "$ACTIVE_GAMEDIR/saves" 2>/dev/null)" ]; then
    cp -rn "$MC_DIR/saves"/* "$ACTIVE_GAMEDIR/saves/" 2>/dev/null
fi

CP_ENTRIES=()

# Helper to resolve and cache maven library paths
resolve_lib() {
    local l_name="$1"
    local l_path="$2"
    local l_url="$3"

    local jar_path=""
    if [ -n "$l_path" ] && [ "$l_path" != "null" ]; then
        jar_path="$LIBS_DIR/$l_path"
    elif [[ "$l_name" == *:* ]]; then
        IFS=':' read -r group artifact ver <<< "$l_name"
        group_path="${group//.//}"
        jar_path="$LIBS_DIR/$group_path/$artifact/$ver/$artifact-$ver.jar"
    fi

    if [ -n "$jar_path" ]; then
        if [ ! -s "$jar_path" ] && [ -n "$l_url" ] && [ "$l_url" != "null" ]; then
            mkdir -p "$(dirname "$jar_path")"
            if [[ "$l_url" =~ \.jar$ ]]; then
                curl -sL "$l_url" -o "$jar_path" 2>/dev/null
            else
                local rel="${jar_path#$LIBS_DIR/}"
                curl -sL "${l_url%/}/$rel" -o "$jar_path" 2>/dev/null
            fi
        fi
        [ -f "$jar_path" ] && CP_ENTRIES+=("$jar_path")
    fi
}

mapfile -t VERSION_LIBS < <(jq -c '.libraries[]' "$VERSION_JSON" 2>/dev/null)
for lib_raw in "${VERSION_LIBS[@]}"; do
    l_name=$(echo "$lib_raw" | jq -r '.name // empty')
    l_path=$(echo "$lib_raw" | jq -r '.downloads.artifact.path // empty')
    l_url=$(echo "$lib_raw" | jq -r '.downloads.artifact.url // .url // empty')
    resolve_lib "$l_name" "$l_path" "$l_url"
done

if [ -n "$INHERITS_FROM" ] && [ -f "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" ]; then
    BASE_JSON="$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json"
    ASSET_INDEX=$(jq -r '.assetIndex.id // empty' "$BASE_JSON")
    [ -z "$ASSET_INDEX" ] && ASSET_INDEX=$(jq -r '.assetIndex.id // "'"$INHERITS_FROM"'"' "$VERSION_JSON")
    BASE_JAR="$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.jar"

    mapfile -t BASE_LIBS < <(jq -c '.libraries[]' "$BASE_JSON" 2>/dev/null)
    for lib_raw in "${BASE_LIBS[@]}"; do
        l_name=$(echo "$lib_raw" | jq -r '.name // empty')
        l_path=$(echo "$lib_raw" | jq -r '.downloads.artifact.path // empty')
        l_url=$(echo "$lib_raw" | jq -r '.downloads.artifact.url // .url // empty')
        resolve_lib "$l_name" "$l_path" "$l_url"
    done
else
    ASSET_INDEX=$(jq -r '.assetIndex.id // "'"$SELECTED_VERSION"'"' "$VERSION_JSON")
    BASE_JAR="$VERSIONS_DIR/$SELECTED_VERSION/$SELECTED_VERSION.jar"
fi

[ -f "$BASE_JAR" ] && CP_ENTRIES+=("$BASE_JAR")

FULL_CLASSPATH=$(printf "%s\n" "${CP_ENTRIES[@]}" | sort -u | tr '\n' ':')
NATIVES_PATH="$VERSIONS_DIR/$SELECTED_VERSION/natives"
[ ! -d "$NATIVES_PATH" ] && [ -n "$INHERITS_FROM" ] && NATIVES_PATH="$VERSIONS_DIR/$INHERITS_FROM/natives"

MAX_RAM=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE")
MIN_RAM=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE")
EXTRA_JVM=$(jq -r '.jvm_args // ""' "$SETTINGS_FILE")

JVM_FLAGS=(
    "-Xmx$MAX_RAM"
    "-Xms$MIN_RAM"
    "-Djava.library.path=$NATIVES_PATH"
)

if [ -n "$BASE_JAR" ] && [ -f "$BASE_JAR" ]; then
    JVM_FLAGS+=("-Dfabric.gameJarPath=$BASE_JAR")
fi

if [ -n "$EXTRA_JVM" ]; then
    read -r -a EXTRA_FLAGS <<< "$EXTRA_JVM"
    JVM_FLAGS+=("${EXTRA_FLAGS[@]}")
fi

# Authlib agent & Offline Skins/Capes handling
if [ "$SELECTED_TYPE" == "authlib" ] && [ -n "$SELECTED_SERVER" ]; then
    if [ "$SERVER_ONLINE" = true ]; then
        JVM_FLAGS+=("-javaagent:$AUTHLIB_JAR=$SELECTED_SERVER" "-Dauthlibinjector.noLogFile")
    fi
elif [ "$SELECTED_TYPE" == "offline" ]; then
    OFF_SKIN_SRV=$(echo "$SELECTED_RAW" | jq -r '.skin_server // empty')
    if [ -n "$OFF_SKIN_SRV" ]; then
        SKIN_SRV_STATUS=$(curl -sL --connect-timeout 3 --max-time 4 -o /dev/null -w "%{http_code}" "$OFF_SKIN_SRV")
        if [ "$SKIN_SRV_STATUS" -eq 200 ] || [ "$SKIN_SRV_STATUS" -eq 204 ]; then
            JVM_FLAGS+=("-javaagent:$AUTHLIB_JAR=$OFF_SKIN_SRV" "-Dauthlibinjector.noLogFile")
        fi
    else
        # Sync configured skin and cape paths to $SKINS_DIR and $CAPES_DIR if needed
        STORED_SKIN=$(echo "$SELECTED_RAW" | jq -r '.skin // empty')
        STORED_CAPE=$(echo "$SELECTED_RAW" | jq -r '.cape // empty')
        [ -n "$STORED_SKIN" ] && [ -f "$STORED_SKIN" ] && [ "$STORED_SKIN" != "$SKINS_DIR/${SELECTED_USER}.png" ] && cp "$STORED_SKIN" "$SKINS_DIR/${SELECTED_USER}.png"
        [ -n "$STORED_CAPE" ] && [ -f "$STORED_CAPE" ] && [ "$STORED_CAPE" != "$CAPES_DIR/${SELECTED_USER}.png" ] && cp "$STORED_CAPE" "$CAPES_DIR/${SELECTED_USER}.png"

        USER_SKIN="$SKINS_DIR/${SELECTED_USER}.png"
        USER_CAPE="$CAPES_DIR/${SELECTED_USER}.png"

        # Prepare CustomSkinLoader mod for offline skins & capes
        CSL_JAR="$CLI_DIR/tools/CustomSkinLoader_Universal-15.0.1.jar"
        if [ -f "$CSL_JAR" ]; then
            mkdir -p "$ACTIVE_GAMEDIR/mods"
            cp -n "$CSL_JAR" "$ACTIVE_GAMEDIR/mods/" 2>/dev/null

            CSL_DIR="$ACTIVE_GAMEDIR/CustomSkinLoader"
            mkdir -p "$CSL_DIR/LocalSkin/skins" "$CSL_DIR/LocalSkin/capes"
            cat > "$CSL_DIR/CustomSkinLoader.json" << 'CSL_EOF'
{
  "version": "15.0.1",
  "enable": true,
  "load_list": [
    {
      "name": "LocalSkin",
      "type": "LocalSkin"
    },
    {
      "name": "Mojang",
      "type": "Mojang"
    }
  ]
}
CSL_EOF
            if [ -s "$USER_SKIN" ]; then
                cp "$USER_SKIN" "$CSL_DIR/LocalSkin/skins/${SELECTED_USER}.png" 2>/dev/null
            fi
            if [ -s "$USER_CAPE" ]; then
                cp "$USER_CAPE" "$CSL_DIR/LocalSkin/capes/${SELECTED_USER}.png" 2>/dev/null
            fi
        fi
    fi
fi

# ==========================================
# PARSE DYNAMIC JVM & GAME ARGUMENTS (NEOFORGE / FORGE / FABRIC / VANILLA)
# ==========================================
SELECTED_CLIENT_ID=$(echo "$SELECTED_RAW" | jq -r '.clientToken // empty' 2>/dev/null)
[ -z "$SELECTED_CLIENT_ID" ] && SELECTED_CLIENT_ID="${SELECTED_UUID//-/}"

substitute_vars() {
    local val="$1"
    val="${val//\$\{library_directory\}/$LIBS_DIR}"
    val="${val//\$\{classpath_separator\}/:}"
    val="${val//\$\{natives_directory\}/$NATIVES_PATH}"
    val="${val//\$\{version_name\}/$SELECTED_VERSION}"
    val="${val//\$\{auth_player_name\}/$SELECTED_USER}"
    val="${val//\$\{auth_uuid\}/$SELECTED_UUID}"
    val="${val//\$\{auth_access_token\}/$SELECTED_TOKEN}"
    val="${val//\$\{game_directory\}/$ACTIVE_GAMEDIR}"
    val="${val//\$\{assets_root\}/$ASSETS_DIR}"
    val="${val//\$\{assets_index_name\}/$ASSET_INDEX}"
    val="${val//\$\{version_type\}/release}"
    val="${val//\$\{user_type\}/mojang}"
    val="${val//\$\{launcher_name\}/minecraft-cli}"
    val="${val//\$\{launcher_version\}/1.0.0}"
    val="${val//\$\{clientid\}/$SELECTED_CLIENT_ID}"
    val="${val//\$\{auth_xuid\}/0}"
    val="${val//\$\{classpath\}/$FULL_CLASSPATH}"
    echo "$val"
}

extract_json_args() {
    local j_file="$1"
    local a_key="$2"
    local part1="${a_key%%.*}"
    local part2="${a_key##*.}"
    jq -r --arg p1 "$part1" --arg p2 "$part2" '
      (.[$p1][$p2] // .[$p1] // []) | 
      if type == "array" then .[] else . end |
      if type == "string" then . 
      elif type == "object" then
        if .value then
          if ((.rules // []) | length == 0) then
            if (.value | type) == "array" then .value[] else .value end
          elif any(.rules[]; 
                 (.action == "allow" and 
                  ((.os // null) == null or .os.name == "linux") and
                  ((.features // null) == null)
                 )
               ) then
            if (.value | type) == "array" then .value[] else .value end
          else empty end
        else empty end
      else empty end
    ' "$j_file" 2>/dev/null
}

# Add dynamic JVM arguments from version JSON
if [ -n "$INHERITS_FROM" ] && [ -f "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" ]; then
    mapfile -t BASE_JVM_ARGS < <(extract_json_args "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" "arguments.jvm")
    for arg in "${BASE_JVM_ARGS[@]}"; do
        [ -z "$arg" ] && continue
        [[ "$arg" == *java.library.path* ]] && continue
        [[ "$arg" == "-cp" || "$arg" == "-classpath" || "$arg" == *classpath* ]] && continue
        [[ "$arg" != -* ]] && continue
        expanded=$(substitute_vars "$arg")
        JVM_FLAGS+=("$expanded")
    done
fi

mapfile -t VER_JVM_ARGS < <(extract_json_args "$VERSION_JSON" "arguments.jvm")
for arg in "${VER_JVM_ARGS[@]}"; do
    [ -z "$arg" ] && continue
    [[ "$arg" == *java.library.path* ]] && continue
    [[ "$arg" == "-cp" || "$arg" == "-classpath" || "$arg" == *classpath* ]] && continue
    [[ "$arg" != -* ]] && continue
    expanded=$(substitute_vars "$arg")
    JVM_FLAGS+=("$expanded")
done

# Build Game Arguments
GAME_ARGS=()
mapfile -t VER_GAME_ARGS < <(extract_json_args "$VERSION_JSON" "arguments.game")
if [ ${#VER_GAME_ARGS[@]} -gt 0 ]; then
    for arg in "${VER_GAME_ARGS[@]}"; do
        expanded=$(substitute_vars "$arg")
        GAME_ARGS+=("$expanded")
    done
fi

if [ -n "$INHERITS_FROM" ] && [ -f "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" ]; then
    mapfile -t BASE_GAME_ARGS < <(extract_json_args "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" "arguments.game")
    for arg in "${BASE_GAME_ARGS[@]}"; do
        expanded=$(substitute_vars "$arg")
        GAME_ARGS+=("$expanded")
    done
fi

# Fallback: check if username flag was injected, otherwise append standard flags
has_user_arg=false
for g_arg in "${GAME_ARGS[@]}"; do
    if [ "$g_arg" == "--username" ]; then
        has_user_arg=true
        break
    fi
done

if [ "$has_user_arg" = false ]; then
    LEGACY_ARGS=$(jq -r '.minecraftArguments // empty' "$VERSION_JSON")
    if [ -z "$LEGACY_ARGS" ] && [ -n "$INHERITS_FROM" ] && [ -f "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" ]; then
        LEGACY_ARGS=$(jq -r '.minecraftArguments // empty' "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json")
    fi

    if [ -n "$LEGACY_ARGS" ]; then
        EXPANDED_LEGACY=$(substitute_vars "$LEGACY_ARGS")
        read -r -a PARSED_LEGACY <<< "$EXPANDED_LEGACY"
        GAME_ARGS+=("${PARSED_LEGACY[@]}")
    else
        GAME_ARGS+=(
            "--username" "$SELECTED_USER"
            "--version" "$SELECTED_VERSION"
            "--gameDir" "$ACTIVE_GAMEDIR"
            "--assetsDir" "$ASSETS_DIR"
            "--assetIndex" "$ASSET_INDEX"
            "--uuid" "$SELECTED_UUID"
            "--accessToken" "$SELECTED_TOKEN"
            "--versionType" "release"
        )
    fi
fi

clear
echo -e "\e[1;32m==============================================\e[0m"
echo -e "\e[1;36m           STARTING MINECRAFT CLIENT          \e[0m"
echo -e "\e[1;32m==============================================\e[0m"
printf "  \e[1;33mProfile:\e[0m   %s (%s)\n" "$SELECTED_USER" "$SELECTED_TYPE"
printf "  \e[1;33mVersion:\e[0m   %s\n" "$SELECTED_VERSION"
printf "  \e[1;33mGameDir:\e[0m   %s\n" "$ACTIVE_GAMEDIR"
printf "  \e[1;33mMemory:\e[0m    -Xms%s / -Xmx%s\n" "$MIN_RAM" "$MAX_RAM"
echo -e "\e[1;32m==============================================\e[0m\n"

exec java \
    "${JVM_FLAGS[@]}" \
    -cp "$FULL_CLASSPATH" \
    "$MAIN_CLASS" \
    "${GAME_ARGS[@]}"
