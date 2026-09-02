#!/usr/bin/env bash

# ==========================================
# CONFIGURATION
# ==========================================
MC_DIR="$HOME/.minecraft"
VERSION="1.21"
VERSION_DIR="$MC_DIR/versions/$VERSION"
LIBS_DIR="$MC_DIR/libraries"
ASSETS_DIR="$MC_DIR/assets"
NATIVES_DIR="$VERSION_DIR/natives"
AUTHLIB_DIR="$MC_DIR/authlib"
AUTHLIB_JAR="$AUTHLIB_DIR/authlib-injector.jar"
ACCOUNTS_DB="$AUTHLIB_DIR/accounts.json"

mkdir -p "$VERSION_DIR" "$LIBS_DIR" "$ASSETS_DIR/indexes" "$ASSETS_DIR/objects" "$NATIVES_DIR" "$AUTHLIB_DIR"

# Initialize accounts database if not present
if [ ! -s "$ACCOUNTS_DB" ]; then
    echo '{"accounts":[]}' > "$ACCOUNTS_DB"
fi

# ==========================================
# HELPER: PROGRESS BAR
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
# 1. SETUP AUTHLIB-INJECTOR
# ==========================================
if [ ! -s "$AUTHLIB_JAR" ]; then
    echo -e "\e[1;34m==> [1/6] Downloading latest authlib-injector...\e[0m"
    curl -sL "https://github.com/yushijinhun/authlib-injector/releases/download/v1.2.5/authlib-injector-1.2.5.jar" -o "$AUTHLIB_JAR" || \
    curl -sL "https://authlib-injector.yushijinhun.com/artifact/latest/authlib-injector.jar" -o "$AUTHLIB_JAR"
fi

# ==========================================
# 2. ACCOUNT MANAGEMENT MENU
# ==========================================
select_or_add_account() {
    while true; do
        clear
        echo -e "\e[1;35m==============================================\e[0m"
        echo -e "\e[1;36m         MINECRAFT CLI ACCOUNT MANAGER        \e[0m"
        echo -e "\e[1;35m==============================================\e[0m"

        mapfile -t ACCOUNTS < <(jq -c '.accounts[]' "$ACCOUNTS_DB" 2>/dev/null)
        local total_acc=${#ACCOUNTS[@]}

        if [ "$total_acc" -gt 0 ]; then
            echo -e "\e[1;33mAvailable Accounts:\e[0m"
            for i in "${!ACCOUNTS[@]}"; do
                acc="${ACCOUNTS[$i]}"
                u_name=$(echo "$acc" | jq -r '.username')
                a_type=$(echo "$acc" | jq -r '.type')
                a_srv=$(echo "$acc" | jq -r '.server // "N/A"')
                printf "  \e[1;32m[%d]\e[0m %-18s (\e[1;34m%s\e[0m | %s)\n" "$((i+1))" "$u_name" "$a_type" "$a_srv"
            done
            echo ""
        else
            echo -e "\e[1;33mNo accounts registered yet.\e[0m\n"
        fi

        echo -e "  \e[1;32m[a]\e[0m Add New Authlib (Yggdrasil) Account"
        echo -e "  \e[1;32m[o]\e[0m Add New Offline Account"
        if [ "$total_acc" -gt 0 ]; then
            echo -e "  \e[1;31m[d]\e[0m Delete an Account"
        fi
        echo -e "  \e[1;31m[q]\e[0m Quit"
        echo -e "\e[1;35m----------------------------------------------\e[0m"
        read -rp "Select an option or account number: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total_acc" ]; then
            SELECTED_RAW="${ACCOUNTS[$((choice-1))]}"
            SELECTED_TYPE=$(echo "$SELECTED_RAW" | jq -r '.type')
            SELECTED_USER=$(echo "$SELECTED_RAW" | jq -r '.username')
            SELECTED_UUID=$(echo "$SELECTED_RAW" | jq -r '.uuid')
            SELECTED_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.token // "0"')
            SELECTED_SERVER=$(echo "$SELECTED_RAW" | jq -r '.server // empty')
            SELECTED_CLIENT_TOKEN=$(echo "$SELECTED_RAW" | jq -r '.clientToken // empty')

            # If Authlib, validate/refresh token
            if [ "$SELECTED_TYPE" == "authlib" ]; then
                echo -e "\n\e[1;34m==> Validating session with $SELECTED_SERVER...\e[0m"
                VAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SELECTED_SERVER/authserver/validate" \
                    -H "Content-Type: application/json" \
                    -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\"}")

                if [ "$VAL_CODE" -ne 204 ] && [ "$VAL_CODE" -ne 200 ]; then
                    echo -e "\e[1;33m[*] Refreshing expired session token...\e[0m"
                    REFRESH_RESP=$(curl -s -X POST "$SELECTED_SERVER/authserver/refresh" \
                        -H "Content-Type: application/json" \
                        -d "{\"accessToken\": \"$SELECTED_TOKEN\", \"clientToken\": \"$SELECTED_CLIENT_TOKEN\", \"requestUser\": true}")

                    NEW_TOKEN=$(echo "$REFRESH_RESP" | jq -r '.accessToken // empty')
                    if [ -n "$NEW_TOKEN" ]; then
                        SELECTED_TOKEN="$NEW_TOKEN"
                        # Update DB
                        jq --arg user "$SELECTED_USER" --arg srv "$SELECTED_SERVER" --arg tok "$NEW_TOKEN" \
                           '(.accounts[] | select(.username == $user and .server == $srv)).token = $tok' \
                           "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                    else
                        echo -e "\e[1;31m[-] Session expired and refresh failed. Please re-add this account.\e[0m"
                        sleep 2
                        continue
                    fi
                fi
            fi
            break

        elif [ "$choice" == "a" ]; then
            echo -e "\n\e[1;36m-- Add Authlib (Yggdrasil) Account --\e[0m"
            read -rp "Authlib API Root URL [default: https://elethiya.com/api/yggdrasil]: " input_srv
            input_srv="${input_srv:-https://elethiya.com/api/yggdrasil}"
            read -rp "Username / Email: " input_user
            read -rsp "Password: " input_pass
            echo ""

            client_tok=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | md5sum | head -c 32)
            auth_payload=$(jq -n \
              --arg user "$input_user" \
              --arg pass "$input_pass" \
              --arg client "$client_tok" \
              '{agent: {name: "Minecraft", version: 1}, username: $user, password: $pass, clientToken: $client, requestUser: true}')

            auth_resp=$(curl -s -X POST "$input_srv/authserver/authenticate" \
              -H "Content-Type: application/json" \
              -d "$auth_payload")

            err_check=$(echo "$auth_resp" | jq -r '.errorMessage // empty' 2>/dev/null)
            if [ -n "$err_check" ]; then
                echo -e "\e[1;31m[-] Authentication failed: $err_check\e[0m"
                read -rp "Press Enter to return..."
                continue
            fi

            tok=$(echo "$auth_resp" | jq -r '.accessToken // empty')
            uid=$(echo "$auth_resp" | jq -r '.selectedProfile.id // empty')
            pname=$(echo "$auth_resp" | jq -r '.selectedProfile.name // empty')

            if [ -z "$tok" ] || [ -z "$pname" ]; then
                echo -e "\e[1;31m[-] Invalid response received from server.\e[0m"
                read -rp "Press Enter to return..."
                continue
            fi

            # Add to database
            new_entry=$(jq -n \
                --arg u "$pname" \
                --arg id "$uid" \
                --arg t "$tok" \
                --arg s "$input_srv" \
                --arg ct "$client_tok" \
                '{type: "authlib", username: $u, uuid: $id, token: $t, server: $s, clientToken: $ct}')

            jq --argjson entry "$new_entry" '.accounts = [.accounts[] | select(.username != $entry.username or .server != $entry.server)] + [$entry]' \
                "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"

            echo -e "\e[1;32m[+] Account '$pname' added successfully.\e[0m"
            sleep 1

        elif [ "$choice" == "o" ]; then
            echo -e "\n\e[1;36m-- Add Offline Account --\e[0m"
            read -rp "Enter In-Game Username: " off_user
            if [ -z "$off_user" ]; then continue; fi

            # Generate offline UUID (MD5 hash of "OfflinePlayer:" + username)
            off_hash=$(printf "OfflinePlayer:%s" "$off_user" | md5sum | awk '{print $1}')
            off_uuid="${off_hash:0:8}-${off_hash:8:4}-3${off_hash:13:3}-${off_hash:16:4}-${off_hash:20:12}"

            new_entry=$(jq -n \
                --arg u "$off_user" \
                --arg id "$off_uuid" \
                '{type: "offline", username: $u, uuid: $id, token: "0", server: null}')

            jq --argjson entry "$new_entry" '.accounts = [.accounts[] | select(.username != $entry.username or .type != "offline")] + [$entry]' \
                "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"

            echo -e "\e[1;32m[+] Offline profile '$off_user' created.\e[0m"
            sleep 1

        elif [ "$choice" == "d" ] && [ "$total_acc" -gt 0 ]; then
            read -rp "Enter account number to remove: " del_idx
            if [[ "$del_idx" =~ ^[0-9]+$ ]] && [ "$del_idx" -ge 1 ] && [ "$del_idx" -le "$total_acc" ]; then
                target_del="${ACCOUNTS[$((del_idx-1))]}"
                del_u=$(echo "$target_del" | jq -r '.username')
                del_t=$(echo "$target_del" | jq -r '.type')
                del_s=$(echo "$target_del" | jq -r '.server // empty')

                jq --arg u "$del_u" --arg t "$del_t" --arg s "$del_s" \
                   '.accounts = [.accounts[] | select(.username != $u or .type != $t or (.server // "") != $s)]' \
                   "$ACCOUNTS_DB" > "$ACCOUNTS_DB.tmp" && mv "$ACCOUNTS_DB.tmp" "$ACCOUNTS_DB"
                echo -e "\e[1;32m[+] Account removed.\e[0m"
                sleep 1
            fi
        elif [ "$choice" == "q" ]; then
            exit 0
        fi
    done
}

select_or_add_account

echo -e "\n\e[1;32m[+] Selected Account:\e[0m \e[1;33m$SELECTED_USER\e[0m (\e[1;36m$SELECTED_TYPE\e[0m)"

# ==========================================
# 3. METADATA & CLIENT JAR
# ==========================================
echo -e "\e[1;34m==> [3/6] Verifying client metadata & game binary...\e[0m"
VERSION_JSON="$VERSION_DIR/$VERSION.json"
if [ ! -s "$VERSION_JSON" ]; then
    VERSION_URL=$(curl -s https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | \
        jq -r --arg v "$VERSION" '.versions[] | select(.id == $v) | .url')
    curl -sL "$VERSION_URL" -o "$VERSION_JSON"
fi

CLIENT_JAR="$VERSION_DIR/$VERSION.jar"
if [ ! -s "$CLIENT_JAR" ]; then
    CLIENT_URL=$(jq -r '.downloads.client.url' "$VERSION_JSON")
    echo "  Downloading Minecraft $VERSION Client JAR..."
    curl -sL "$CLIENT_URL" -o "$CLIENT_JAR"
fi

# ==========================================
# 4. DOWNLOAD LIBRARIES & NATIVES
# ==========================================
echo -e "\e[1;34m==> [4/6] Verifying libraries & dependencies...\e[0m"

mapfile -t LIBS_TO_DOWNLOAD < <(jq -r '.libraries[] | select(.downloads.artifact != null) | .downloads.artifact | "\(.path)|\(.url)"' "$VERSION_JSON")
TOTAL_LIBS=${#LIBS_TO_DOWNLOAD[@]}
CURR_LIB=0

for entry in "${LIBS_TO_DOWNLOAD[@]}"; do
    path="${entry%%|*}"
    url="${entry##*|}"
    target="$LIBS_DIR/$path"
    if [ ! -s "$target" ]; then
        mkdir -p "$(dirname "$target")"
        curl -sL "$url" -o "$target"
    fi
    ((CURR_LIB++))
    render_progress_bar "$CURR_LIB" "$TOTAL_LIBS" "Libraries"
done
echo ""

find "$LIBS_DIR" -name "*natives-linux*.jar" -exec unzip -n -q -d "$NATIVES_DIR" {} + 2>/dev/null || true

# ==========================================
# 5. ASSET OBJECTS (ALL SOUNDS & TEXTURES)
# ==========================================
echo -e "\e[1;34m==> [5/6] Verifying game assets & resource objects...\e[0m"
ASSET_INDEX_NAME=$(jq -r '.assetIndex.id' "$VERSION_JSON")
ASSET_INDEX_URL=$(jq -r '.assetIndex.url' "$VERSION_JSON")
ASSET_INDEX_FILE="$ASSETS_DIR/indexes/$ASSET_INDEX_NAME.json"

if [ ! -s "$ASSET_INDEX_FILE" ]; then
    curl -sL "$ASSET_INDEX_URL" -o "$ASSET_INDEX_FILE"
fi

mapfile -t ALL_HASHES < <(jq -r '.objects | to_entries[] | .value.hash' "$ASSET_INDEX_FILE")
MISSING_HASHES=()
for hash in "${ALL_HASHES[@]}"; do
    prefix="${hash:0:2}"
    if [ ! -s "$ASSETS_DIR/objects/$prefix/$hash" ]; then
        MISSING_HASHES+=("$hash")
    fi
done

TOTAL_MISSING=${#MISSING_HASHES[@]}

if [ "$TOTAL_MISSING" -gt 0 ]; then
    echo "  Downloading $TOTAL_MISSING missing asset files..."
    export ASSETS_DIR
    download_single_asset() {
        h="$1"
        p="${h:0:2}"
        mkdir -p "$ASSETS_DIR/objects/$p"
        curl -sL "https://resources.download.minecraft.net/$p/$h" -o "$ASSETS_DIR/objects/$p/$h"
    }
    export -f download_single_asset

    # Parallel download with progress monitoring
    printf "%s\n" "${MISSING_HASHES[@]}" | xargs -n 1 -P 16 -I {} bash -c 'download_single_asset "$@"' _ {}
    echo -e "\e[1;32m  [OK] All assets synchronized.\e[0m"
else
    render_progress_bar 1 1 "Assets"
    echo -e " \e[1;32m[All assets up-to-date]\e[0m"
fi

# ==========================================
# 6. LAUNCH MINECRAFT
# ==========================================
echo -e "\e[1;32m==> [6/6] Launching Minecraft $VERSION...\e[0m"

CLASSPATH=$(find "$LIBS_DIR" -name "*.jar" | tr '\n' ':'):"$CLIENT_JAR"
MAIN_CLASS=$(jq -r '.mainClass' "$VERSION_JSON")

JVM_ARGS=("-Xmx4G" "-Xms2G" "-Djava.library.path=$NATIVES_DIR")

# Attach authlib agent only if an authlib server is defined for the profile
if [ "$SELECTED_TYPE" == "authlib" ] && [ -n "$SELECTED_SERVER" ]; then
    JVM_ARGS+=("-javaagent:$AUTHLIB_JAR=$SELECTED_SERVER")
fi

exec java \
    "${JVM_ARGS[@]}" \
    -cp "$CLASSPATH" \
    "$MAIN_CLASS" \
    --username "$SELECTED_USER" \
    --version "$VERSION" \
    --gameDir "$MC_DIR" \
    --assetsDir "$ASSETS_DIR" \
    --assetIndex "$ASSET_INDEX_NAME" \
    --uuid "$SELECTED_UUID" \
    --accessToken "$SELECTED_TOKEN" \
    --userType "mojang" \
    --versionType "release"
