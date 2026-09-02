#!/usr/bin/env bash

# ==========================================
# PATHS & CONFIGURATION
# ==========================================
MC_DIR="$HOME/.minecraft"
VERSIONS_DIR="$MC_DIR/versions"
LIBS_DIR="$MC_DIR/libraries"
ASSETS_DIR="$MC_DIR/assets"
AUTHLIB_DIR="$MC_DIR/authlib"
AUTHLIB_JAR="$AUTHLIB_DIR/authlib-injector.jar"
ACCOUNTS_DB="$AUTHLIB_DIR/accounts.json"
SETTINGS_FILE="$AUTHLIB_DIR/settings.json"

mkdir -p "$AUTHLIB_DIR"

if [ ! -s "$ACCOUNTS_DB" ]; then
    echo '{"accounts":[]}' > "$ACCOUNTS_DB"
fi

if [ ! -s "$SETTINGS_FILE" ]; then
    cat << 'SETTINGS_EOF' > "$SETTINGS_FILE"
{
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"
}
SETTINGS_EOF
fi

if [ ! -s "$AUTHLIB_JAR" ]; then
    echo -e "\e[1;34m==> Downloading authlib-injector...\e[0m"
    curl -sL "https://github.com/yushijinhun/authlib-injector/releases/download/v1.2.5/authlib-injector-1.2.5.jar" -o "$AUTHLIB_JAR" || \
    curl -sL "https://authlib-injector.yushijinhun.com/artifact/latest/authlib-injector.jar" -o "$AUTHLIB_JAR"
fi

# ==========================================
# SETTINGS / RAM CONFIGURATION TUI
# ==========================================
configure_settings() {
    while true; do
        MAX_RAM=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE")
        MIN_RAM=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE")
        JVM_ARGS=$(jq -r '.jvm_args // ""' "$SETTINGS_FILE")

        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m           LAUNCHER & RAM SETTINGS            \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"
        printf "  \e[1;33m[1]\e[0m Maximum RAM (-Xmx) : \e[1;32m%s\e[0m\n" "$MAX_RAM"
        printf "  \e[1;33m[2]\e[0m Minimum RAM (-Xms) : \e[1;32m%s\e[0m\n" "$MIN_RAM"
        printf "  \e[1;33m[3]\e[0m Custom JVM Flags   : \e[1;34m%s\e[0m\n" "$JVM_ARGS"
        echo -e "\n  \e[1;32m[b]\e[0m Save and Back to Main Menu"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select option: " s_choice

        case "$s_choice" in
            1)
                echo -e "\nExamples: 2G, 4G, 6G, 8G, 1024M"
                read -rp "Enter Maximum RAM (-Xmx): " new_max
                if [[ "$new_max" =~ ^[0-9]+[GMgm]$ ]]; then
                    new_max="${new_max^^}"
                    jq --arg r "$new_max" '.max_ram = $r' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                else
                    echo -e "\e[1;31m[-] Invalid format! Use e.g. 4G or 4096M\e[0m"
                    sleep 1.5
                fi
                ;;
            2)
                echo -e "\nExamples: 1G, 2G, 4G, 1024M"
                read -rp "Enter Minimum RAM (-Xms): " new_min
                if [[ "$new_min" =~ ^[0-9]+[GMgm]$ ]]; then
                    new_min="${new_min^^}"
                    jq --arg r "$new_min" '.min_ram = $r' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                else
                    echo -e "\e[1;31m[-] Invalid format! Use e.g. 2G or 2048M\e[0m"
                    sleep 1.5
                fi
                ;;
            3)
                echo -e "\nEnter extra JVM flags (space-separated):"
                read -rp "> " new_flags
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
                echo -e "\n\e[1;36m-- Add Authlib (Yggdrasil) Account --\e[0m"
                read -rp "Authlib API Root URL [default: https://elethiya.com/api/yggdrasil]: " in_srv
                in_srv="${in_srv:-https://elethiya.com/api/yggdrasil}"
                read -rp "Username / Email: " in_user
                read -rsp "Password: " in_pass
                echo ""

                client_tok=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | md5sum | head -c 32)
                auth_payload=$(jq -n \
                  --arg user "$in_user" \
                  --arg pass "$in_pass" \
                  --arg client "$client_tok" \
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
                    echo -e "\e[1;32m[+] Account '$pname' registered.\e[0m"
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
# MAIN INTERACTIVE LAUNCHER MENU
# ==========================================
while true; do
    MAX_RAM=$(jq -r '.max_ram // "4G"' "$SETTINGS_FILE")
    MIN_RAM=$(jq -r '.min_ram // "2G"' "$SETTINGS_FILE")

    mapfile -t INSTALLED_VERSIONS < <(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)
    mapfile -t ACCOUNTS < <(jq -c '.accounts[]' "$ACCOUNTS_DB" 2>/dev/null)

    clear
    echo -e "\e[1;35m==============================================\e[0m"
    echo -e "\e[1;36m             MINECRAFT CLI LAUNCHER           \e[0m"
    echo -e "\e[1;35m==============================================\e[0m"
    printf "  \e[1;37mActive RAM Profile:\e[0m  -Xms\e[1;32m%s\e[0m / -Xmx\e[1;32m%s\e[0m\n" "$MIN_RAM" "$MAX_RAM"
    echo -e "\e[1;35m----------------------------------------------\e[0m"

    echo -e "\e[1;33mInstalled Game Versions:\e[0m"
    if [ ${#INSTALLED_VERSIONS[@]} -eq 0 ]; then
        echo -e "  \e[1;31mNo versions found in ~/.minecraft/versions\e[0m"
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

    echo -e "\n\e[1;33mConfiguration & Controls:\e[0m"
    echo -e "  \e[1;33m[r]\e[0m Configure RAM & JVM Flags"
    echo -e "  \e[1;33m[u]\e[0m Manage Accounts (Add/Delete/Authlib/Offline)"
    echo -e "  \e[1;31m[q]\e[0m Quit"
    echo -e "\e[1;35m----------------------------------------------\e[0m"
    read -rp "Select version number to launch or menu option: " main_choice

    case "$main_choice" in
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
# SELECT ACTIVE ACCOUNT FOR THIS SESSION
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
                echo -e "\e[1;33m[*] Refreshing token...\e[0m"
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

# Determine active Game Directory (check if HMCL isolated this instance)
INSTANCE_DIR="$VERSIONS_DIR/$SELECTED_VERSION"
if [ -d "$INSTANCE_DIR/mods" ] || [ -d "$INSTANCE_DIR/resourcepacks" ]; then
    ACTIVE_GAMEDIR="$INSTANCE_DIR"
else
    ACTIVE_GAMEDIR="$MC_DIR"
fi

# Ensure standard mod & pack folders exist in the active game directory
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

# Crucial Fabric / Modloader JVM properties
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
