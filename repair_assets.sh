#!/usr/bin/env bash

MC_DIR="$HOME/.minecraft"
VERSION="1.21"
VERSION_JSON="$MC_DIR/versions/$VERSION/$VERSION.json"
ASSETS_DIR="$MC_DIR/assets"

ASSET_INDEX_NAME=$(jq -r '.assetIndex.id' "$VERSION_JSON")
ASSET_INDEX_URL=$(jq -r '.assetIndex.url' "$VERSION_JSON")
ASSET_INDEX_FILE="$ASSETS_DIR/indexes/$ASSET_INDEX_NAME.json"

mkdir -p "$ASSETS_DIR/indexes" "$ASSETS_DIR/objects"

echo "==> Fetching complete asset index..."
curl -sL "$ASSET_INDEX_URL" -o "$ASSET_INDEX_FILE"

mapfile -t ALL_HASHES < <(jq -r '.objects | to_entries[] | .value.hash' "$ASSET_INDEX_FILE")
MISSING_HASHES=()

for hash in "${ALL_HASHES[@]}"; do
    prefix="${hash:0:2}"
    target_file="$ASSETS_DIR/objects/$prefix/$hash"
    if [ ! -s "$target_file" ]; then
        MISSING_HASHES+=("$hash")
    fi
done

TOTAL_MISSING=${#MISSING_HASHES[@]}
echo "==> Found $TOTAL_MISSING missing/corrupted asset files."

if [ "$TOTAL_MISSING" -gt 0 ]; then
    export ASSETS_DIR
    download_asset() {
        h="$1"
        p="${h:0:2}"
        mkdir -p "$ASSETS_DIR/objects/$p"
        curl -sL "https://resources.download.minecraft.net/$p/$h" -o "$ASSETS_DIR/objects/$p/$h"
    }
    export -f download_asset

    echo "==> Downloading all missing assets (16 parallel streams)..."
    printf "%s\n" "${MISSING_HASHES[@]}" | xargs -n 1 -P 16 -I {} bash -c 'download_asset "$@"' _ {}
    echo "==> [OK] All assets downloaded successfully."
fi
