#!/usr/bin/env bash

# ==========================================
# BASE DIRECTORIES & CONFIGURATION
# ==========================================
CLI_DIR="$HOME/minecraft-cli"
SETTINGS_FILE="$CLI_DIR/settings.json"
AUTHLIB_DIR="$CLI_DIR/authlib"
AUTHLIB_JAR="$AUTHLIB_DIR/authlib-injector.jar"
ACCOUNTS_DB="$AUTHLIB_DIR/accounts.json"

mkdir -p "$CLI_DIR" "$AUTHLIB_DIR"

if [ ! -s "$ACCOUNTS_DB" ]; then
    echo '{"accounts":[]}' > "$ACCOUNTS_DB"
fi

if [ ! -s "$SETTINGS_FILE" ]; then
    cat << SETTINGS_EOF > "$SETTINGS_FILE"
{
  "game_dir": "$HOME/.minecraft",
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"
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
# VERSION INSTALLER FUNCTION
# ==========================================
install_new_version() {
    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m           MINECRAFT VERSION INSTALLER        \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "Target Directory: \e[1;32m$MC_DIR\e[0m\n"

    echo -e "\e[1;34m==> Fetching Mojang version manifest...\e[0m"
    MANIFEST_JSON=$(curl -s "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    if [ -z "$MANIFEST_JSON" ]; then
        echo -e "\e[1;31m[-] Failed to fetch official version manifest.\e[0m"
        read -rp "Press Enter to return..."
        return
    fi

    LATEST_RELEASE=$(echo "$MANIFEST_JSON" | jq -r '.latest.release')
    mapfile -t TOP_RELEASES < <(echo "$MANIFEST_JSON" | jq -r '[.versions[] | select(.type=="release")][0:10] | .[].id')

    echo -e "\e[1;33mPopular / Recent Official Releases:\e[0m"
    for i in "${!TOP_RELEASES[@]}"; do
        printf "  \e[1;32m[%d]\e[0m %s\n" "$((i+1))" "${TOP_RELEASES[$i]}"
    done
    echo -e "  \e[1;33m[c]\e[0m Type a custom version ID (e.g. 1.20.4, 1.16.5)"
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

    if [ -z "$target_ver" ]; then return; fi

    VERSION_URL=$(echo "$MANIFEST_JSON" | jq -r --arg v "$target_ver" '.versions[] | select(.id == $v) | .url')
    if [ -z "$VERSION_URL" ] || [ "$VERSION_URL" == "null" ]; then
        echo -e "\e[1;31m[-] Version '$target_ver' not found in official manifest.\e[0m"
        read -rp "Press Enter to return..."
        return
    fi

    TARGET_VER_DIR="$VERSIONS_DIR/$target_ver"
    mkdir -p "$TARGET_VER_DIR" "$TARGET_VER_DIR/natives"

    echo -e "\n\e[1;34m==> [1/4] Downloading version metadata ($target_ver.json)...\e[0m"
    TARGET_VER_JSON="$TARGET_VER_DIR/$target_ver.json"
    curl -sL "$VERSION_URL" -o "$TARGET_VER_JSON"

    echo -e "\e[1;34m==> [2/4] Downloading client binary ($target_ver.jar)...\e[0m"
    CLIENT_URL=$(jq -r '.downloads.client.url' "$TARGET_VER_JSON")
    TARGET_JAR="$TARGET_VER_DIR/$target_ver.jar"
    curl -sL "$CLIENT_URL" -o "$TARGET_JAR"

    echo -e "\e[1;34m==> [3/4] Downloading version libraries...\e[0m"
    mapfile -t LIBS_LIST < <(jq -r '.libraries[] | select(.downloads.artifact != null) | .downloads.artifact | "\(.path)|\(.url)"' "$TARGET_VER_JSON")
    local total_libs=${#LIBS_LIST[@]}
    local curr_lib=0
    for item in "${LIBS_LIST[@]}"; do
        l_path="${item%%|*}"
        l_url="${item##*|}"
        dest="$LIBS_DIR/$l_path"
        if [ ! -s "$dest" ]; then
            mkdir -p "$(dirname "$dest")"
            curl -sL "$l_url" -o "$dest"
        fi
        ((curr_lib++))
        render_progress_bar "$curr_lib" "$total_libs" "Libraries"
    done
    echo ""

    find "$LIBS_DIR" -name "*natives-linux*.jar" -exec unzip -n -q -d "$TARGET_VER_DIR/natives" {} + 2>/dev/null || true

    echo -e "\e[1;34m==> [4/4] Verifying and downloading assets...\e[0m"
    A_INDEX_NAME=$(jq -r '.assetIndex.id' "$TARGET_VER_JSON")
    A_INDEX_URL=$(jq -r '.assetIndex.url' "$TARGET_VER_JSON")
    A_INDEX_FILE="$ASSETS_DIR/indexes/$A_INDEX_NAME.json"

    if [ ! -s "$A_INDEX_FILE" ]; then
        curl -sL "$A_INDEX_URL" -o "$A_INDEX_FILE"
    fi

    mapfile -t HASH_LIST < <(jq -r '.objects | to_entries[] | .value.hash' "$A_INDEX_FILE")
    MISSING_ASSETS=()
    for h in "${HASH_LIST[@]}"; do
        pfx="${h:0:2}"
        if [ ! -s "$ASSETS_DIR/objects/$pfx/$h" ]; then
            MISSING_ASSETS+=("$h")
        fi
    done

    local total_missing=${#MISSING_ASSETS[@]}
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
        printf "%s\n" "${MISSING_ASSETS[@]}" | xargs -n 1 -P 16 -I {} bash -c 'dl_asset "$@"' _ {}
    fi

    echo -e "\n\e[1;32m[+] Version $target_ver installed successfully in $TARGET_VER_DIR!\e[0m"
    read -rp "Press Enter to return..."
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

                auth_resp=$(curl -s -X POST "$in_srv/authserver/authenticate" \
                  -H "Content-Type: application/json" \
                  -d "$auth_payload")

                tok=$(echo "$auth_resp" | jq -r '.accessToken // empty')
                uid=$(echo "$auth_resp" | jq -r '.selectedProfile.id // empty')
                pname=$(echo "$auth_resp" | jq -r '.selectedProfile.name // empty')

                if [ -n "$tok" ] && [ -n "$pname" ]; then
                    new_entry=$(jq -n \
                        --arg u "$pname" --arg id "$uid" --arg t "$tok" --arg s "$in_srv" --arg ct "$client_tok" \
                        '{type: "authlib", username: $u, uuid: $id, token: $t, server: $s, clientToken: $ct}')

                    jq --argjson entry "$new_entry" '.accounts = [.accounts[] | select(.username != $entry.username or .server != $entry.server)] + [$entry]' \
                        "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    echo -e "\e[1;32m[+] Account '$pname' added.\e[0m"
                    sleep 1.2
                else
                    err_check=$(echo "$auth_resp" | jq -r '.errorMessage // "Authentication failed"')
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
                    jq --argjson entry "$new_entry" '.accounts = [.accounts[] | select(.username != $entry.username or .type != "offline")] + [$entry]' \
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
                    jq --arg u "$del_u" --arg t "$del_t" --arg s "$del_s" \
                        '.accounts = [.accounts[] | select(.username != $u or .type != $t or (.server // "") != $s)]' \
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
            if [[ "$v_name" =~ [Ff]abric ]]; then
                printf "  \e[1;32m[%d]\e[0m %-26s \e[1;35m(Fabric)\e[0m\n" "$((i+1))" "$v_name"
            else
                printf "  \e[1;32m[%d]\e[0m %-26s \e[1;34m(Standard)\e[0m\n" "$((i+1))" "$v_name"
            fi
        done
    fi

    echo -e "\n\e[1;33mCommands & Tools:\e[0m"
    echo -e "  \e[1;32m[i]\e[0m Install New Minecraft Version"
    echo -e "  \e[1;33m[r]\e[0m Configure Directory, RAM & JVM Flags"
    echo -e "  \e[1;33m[u]\e[0m Manage Accounts (Authlib / Offline)"
    echo -e "  \e[1;31m[q]\e[0m Quit"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select version number to launch or tool option: " main_choice

    case "$main_choice" in
        i|I)
            install_new_version
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
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select account number: " pick_acc

    if [[ "$pick_acc" =~ ^[0-9]+$ ]] && [ "$pick_acc" -ge 1 ] && [ "$pick_acc" -le "${#ACCOUNTS[@]}" ]; then
        SELECTED_RAW="${ACCOUNTS[$((pick_acc-1))]}"
        SELECTED_TYPE=$(echo "$SELECTED_RAW" | jq -r '.type')
        SELECTED_USER=$(echo "$SELECTED_RAW" | jq -r '.username')
        SELECTED_UUID=$(echo "$SELECTED_RAW" | jq -r '.uuid')
        SELECTED_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.token // "0"')
        SELECTED_SERVER=$(echo "$SELECTED_RAW" | jq -r '.server // empty')
        SELECTED_CLIENT_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.clientToken // empty')

        if [ "$SELECTED_TYPE" == "authlib" ]; then
            echo -e "\n\e[1;34m==> Validating session with $SELECTED_SERVER...\e[0m"
            VAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SELECTED_SERVER/authserver/validate" \
                -H "Content-Type: application/json" \
                -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\"}")

            if [ "$VAL_CODE" -ne 204 ] && [ "$VAL_CODE" -ne 200 ]; then
                echo -e "\e[1;33m[*] Refreshing session...\e[0m"
                REFRESH_RESP=$(curl -s -X POST "$SELECTED_SERVER/authserver/refresh" \
                    -H "Content-Type: application/json" \
                    -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\", \"requestUser\": true}")

                NEW_TOKEN=$(echo "$REFRESH_RESP" | jq -r '.accessToken // empty')
                if [ -n "$NEW_TOKEN" ]; then
                    SELECTED_TOKEN="$NEW_TOKEN"
                    jq --arg user "$SELECTED_USER" --arg srv "$SELECTED_SERVER" --arg tok "$NEW_TOKEN" \
                       '(.accounts[] | select(.username == $user and .server == $srv)).token = $tok' \
                       "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
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

mapfile -t VERSION_LIBS < <(jq -r '.libraries[] | (.downloads.artifact.path // .name)' "$VERSION_JSON" 2>/dev/null)
for lib in "${VERSION_LIBS[@]}"; do
    if [[ "$lib" == *:* ]]; then
        IFS=':' read -r group artifact ver <<< "$lib"
        group_path="${group//.//}"
        jar_path="$LIBS_DIR/$group_path/$artifact/$ver/$artifact-$ver.jar"
    else
        jar_path="$LIBS_DIR/$lib"
    fi
    [ -f "$jar_path" ] && CP_ENTRIES+=("$jar_path")
done

if [ -n "$INHERITS_FROM" ] && [ -f "$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json" ]; then
    BASE_JSON="$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.json"
    ASSET_INDEX=$(jq -r '.assetIndex.id' "$BASE_JSON")
    BASE_JAR="$VERSIONS_DIR/$INHERITS_FROM/$INHERITS_FROM.jar"

    mapfile -t BASE_LIBS < <(jq -r '.libraries[] | (.downloads.artifact.path // .name)' "$BASE_JSON" 2>/dev/null)
    for lib in "${BASE_LIBS[@]}"; do
        if [[ "$lib" == *:* ]]; then
            IFS=':' read -r group artifact ver <<< "$lib"
            group_path="${group//.//}"
            jar_path="$LIBS_DIR/$group_path/$artifact/$ver/$artifact-$ver.jar"
        else
            jar_path="$LIBS_DIR/$lib"
        fi
        [ -f "$jar_path" ] && CP_ENTRIES+=("$jar_path")
    done
else
    ASSET_INDEX=$(jq -r '.assetIndex.id // "'"$SELECTED_VERSION"'"' "$VERSION_JSON")
    BASE_JAR="$VERSIONS_DIR/$SELECTED_VERSION/$SELECTED_VERSION.jar"
fi

[ -f "$BASE_JAR" ] && CP_ENTRIES+=("$BASE_JAR")

FULL_CLASSPATH=$(printf "%s\n" "${CP_ENTRIES[@]}" | sort -u | tr '\n' ':')
NATIVES_PATH="$VERSIONS_DIR/$SELECTED_VERSION/natives"

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

if [ "$SELECTED_TYPE" == "authlib" ] && [ -n "$SELECTED_SERVER" ]; then
    JVM_FLAGS+=("-javaagent:$AUTHLIB_JAR=$SELECTED_SERVER")
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
    --username "$SELECTED_USER" \
    --version "$SELECTED_VERSION" \
    --gameDir "$ACTIVE_GAMEDIR" \
    --assetsDir "$ASSETS_DIR" \
    --assetIndex "$ASSET_INDEX" \
    --uuid "$SELECTED_UUID" \
    --accessToken "$SELECTED_TOKEN" \
    --userType "mojang" \
    --versionType "release"
