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


if [ ! -s "$SETTINGS_FILE" ]; then
    cat << SETTINGS_EOF > "$SETTINGS_FILE"
{
  "game_dir": "$HOME/.minecraft",
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M --enable-native-access=ALL-UNNAMED"
}
SETTINGS_EOF
fi

# Ensure authlib-injector exists
if [ ! -s "$AUTHLIB_JAR" ]; then
    echo -e "\e[1;34m==> Downloading authlib-injector...\e[0m"
    curl -sL "https://github.com/yushijinhun/authlib-injector/releases/download/v1.2.5/authlib-injector-1.2.5.jar" -o "$AUTHLIB_JAR" || \
    curl -sL "https://authlib-injector.yushijinhun.com/artifact/latest/authlib-injector.jar" -o "$AUTHLIB_JAR"
fi

# Helper function to refresh directory variables
sync_directories() {
    MC_DIR=$(jq -r '.game_dir // "'"$HOME/.minecraft"'"' "$SETTINGS_FILE")
    VERSIONS_DIR="$MC_DIR/versions"
    LIBS_DIR="$MC_DIR/libraries"
    ASSETS_DIR="$MC_DIR/assets"
    mkdir -p "$VERSIONS_DIR" "$LIBS_DIR" "$ASSETS_DIR/indexes" "$ASSETS_DIR/objects"
}
sync_directories

# ==========================================
# PROGRESS BAR HELPER
# ==========================================
render_progress_bar() {
    local current=$1
    local total=$2
    local label=${3:-"Progress"}
    local width=30
    if [ "$total" -le 0 ]; then return; fi
    local percent=$(( 100 * current / total ))
    local filled=$(( width * current / total ))
    local empty=$(( width - filled ))
    
    local bar_fill=$(printf "%*s" "$filled" "" | tr ' ' '#')
    local bar_empty=$(printf "%*s" "$empty" "" | tr ' ' '-')
    
    printf "\r\e[1;34m%-15s\e[0m \e[1;36m[%s%s]\e[0m \e[1;32m%3d%%\e[0m (\e[1;33m%d/%d\e[0m)" "$label" "$bar_fill" "$bar_empty" "$percent" "$current" "$total"
}

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
    local client_url
    client_url=$(jq -r '.downloads.client.url' "$target_ver_json")
    local target_jar="$target_ver_dir/$target_ver.jar"
    curl -sL "$client_url" -o "$target_jar"

    echo -e "\e[1;34m==> [3/4] Downloading version libraries...\e[0m"
    mapfile -t libs_list < <(jq -r '.libraries[] | select(.downloads.artifact != null) | .downloads.artifact | "\(.path)|\(.url)"' "$target_ver_json")
    local total_libs=${#libs_list[@]}
    local curr_lib=0
    for item in "${libs_list[@]}"; do
        local l_path="${item%%|*}"
        local l_url="${item##*|}"
        local dest="$LIBS_DIR/$l_path"
        if [ ! -s "$dest" ]; then
            mkdir -p "$(dirname "$dest")"
            curl -sL "$l_url" -o "$dest"
        fi
        ((curr_lib++))
        render_progress_bar "$curr_lib" "$total_libs" "Libraries"
    done
    echo ""

    find "$LIBS_DIR" -name "*natives-linux*.jar" -exec unzip -n -q -d "$target_ver_dir/natives" {} + 2>/dev/null || true

    echo -e "\e[1;34m==> [4/4] Verifying and downloading assets...\e[0m"
    local a_index_name a_index_url a_index_file
    a_index_name=$(jq -r '.assetIndex.id' "$target_ver_json")
    a_index_url=$(jq -r '.assetIndex.url' "$target_ver_json")
    a_index_file="$ASSETS_DIR/indexes/$a_index_name.json"

    if [ ! -s "$a_index_file" ]; then
        curl -sL "$a_index_url" -o "$a_index_file"
    fi

    mapfile -t hash_list < <(jq -r '.objects | to_entries[] | .value.hash' "$a_index_file")
    local missing_assets=()
    for h in "${hash_list[@]}"; do
        local pfx="${h:0:2}"
        if [ ! -s "$ASSETS_DIR/objects/$pfx/$h" ]; then
            missing_assets+=("$h")
        fi
    done

    local total_missing=${#missing_assets[@]}
    if [ "$total_missing" -gt 0 ]; then
        echo "  Downloading $total_missing missing assets in parallel..."
        export ASSETS_DIR
        dl_asset() {
            local h="$1"
            local p="${h:0:2}"
            mkdir -p "$ASSETS_DIR/objects/$p"
            curl -sL "https://resources.download.minecraft.net/$p/$h" -o "$ASSETS_DIR/objects/$p/$h"
        }
        export -f dl_asset
        printf "%s\n" "${missing_assets[@]}" | xargs -n 1 -P 16 -I {} bash -c 'dl_asset "$@"' _ {}
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
        curl -sL "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar" -o "$fabric_installer"
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
    curl -sL "$neo_installer_url" -o "$tmp_installer"
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
    curl -sL "$forge_installer_url" -o "$tmp_installer"
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
        curl -sL "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/0.11.0/quilt-installer-0.11.0.jar" -o "$quilt_installer"
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
                echo -e "  [1] Standard ~/.minecraft"
                echo -e "  [2] Inside minecraft-cli ($CLI_DIR/instances)"
                echo -e "  [3] Custom full path"
                read -rp "Select [1-3]: " dir_choice
                case "$dir_choice" in
                    1)
                        jq --arg d "$HOME/.minecraft" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        ;;
                    2)
                        mkdir -p "$CLI_DIR/instances"
                        jq --arg d "$CLI_DIR/instances" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        ;;
                    3)
                        read -rp "Enter absolute folder path: " custom_dir
                        if [ -n "$custom_dir" ]; then
                            mkdir -p "$custom_dir"
                            jq --arg d "$custom_dir" '.game_dir = $d' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                        fi
                        ;;
                esac
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
    printf "  \e[1;37mGame Path:\e[0m  \e[1;32m%s\e[0m\n" "$MC_DIR"
    printf "  \e[1;37mRAM:\e[0m        -Xms\e[1;32m%s\e[0m / -Xmx\e[1;32m%s\e[0m\n" "$MIN_RAM" "$MAX_RAM"
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

INSTANCE_DIR="$VERSIONS_DIR/$SELECTED_VERSION"
if [ -d "$INSTANCE_DIR/mods" ] || [ -d "$INSTANCE_DIR/resourcepacks" ]; then
    ACTIVE_GAMEDIR="$INSTANCE_DIR"
else
    ACTIVE_GAMEDIR="$MC_DIR"
fi

mkdir -p "$ACTIVE_GAMEDIR/mods" "$ACTIVE_GAMEDIR/resourcepacks" "$ACTIVE_GAMEDIR/shaderpacks"

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

# Authlib agent & Custom Skin Server handling (only attached if server is online)
if [ "$SELECTED_TYPE" == "authlib" ] && [ -n "$SELECTED_SERVER" ]; then
    if [ "$SERVER_ONLINE" = true ]; then
        JVM_FLAGS+=("-javaagent:$AUTHLIB_JAR=$SELECTED_SERVER")
    fi
elif [ "$SELECTED_TYPE" == "offline" ]; then
    OFF_SKIN_SRV=$(echo "$SELECTED_RAW" | jq -r '.skin_server // empty')
    if [ -n "$OFF_SKIN_SRV" ]; then
        SKIN_SRV_STATUS=$(curl -sL --connect-timeout 3 --max-time 4 -o /dev/null -w "%{http_code}" "$OFF_SKIN_SRV")
        if [ "$SKIN_SRV_STATUS" -eq 200 ] || [ "$SKIN_SRV_STATUS" -eq 204 ]; then
            JVM_FLAGS+=("-javaagent:$AUTHLIB_JAR=$OFF_SKIN_SRV")
        fi
    fi
fi

# ==========================================
# PARSE DYNAMIC JVM & GAME ARGUMENTS (NEOFORGE / FORGE / FABRIC / VANILLA)
# ==========================================
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
    echo "$val"
}

extract_json_args() {
    local j_file="$1"
    local a_key="$2"
    jq -r --arg k "$a_key" '
      .[$k] // [] | .[] | 
      if type == "string" then . 
      elif type == "object" then
        if .value then
          if ((.rules // []) | length == 0) or any(.rules[]; (.action == "allow" and ((.os.name // "linux") == "linux"))) then
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
        [[ "$arg" == *java.library.path* ]] && continue
        [[ "$arg" == *cp* ]] && continue
        expanded=$(substitute_vars "$arg")
        JVM_FLAGS+=("$expanded")
    done
fi

mapfile -t VER_JVM_ARGS < <(extract_json_args "$VERSION_JSON" "arguments.jvm")
for arg in "${VER_JVM_ARGS[@]}"; do
    [[ "$arg" == *java.library.path* ]] && continue
    [[ "$arg" == *cp* ]] && continue
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
