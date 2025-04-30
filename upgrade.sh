#!/bin/bash

BASE_DIR="/home/usercpanel/public_html"
WP_URL="https://wordpress.org/latest.zip"
TMP_DIR="/home/kare3343/tmp_wp"
ZIP_FILE="$TMP_DIR/latest.zip"
EXTRACT_DIR="$TMP_DIR/wordpress"

mkdir -p "$TMP_DIR"
rm -rf "$TMP_DIR"/*

echo "[1] Mendeteksi instalasi WordPress di $BASE_DIR..."
WP_PATHS=()

find "$BASE_DIR" -type f -name 'wp-config.php' > "$TMP_DIR/wp_paths.txt"

while IFS= read -r line; do
    dir=$(dirname "$line")
    WP_PATHS+=("$dir")
done < "$TMP_DIR/wp_paths.txt"

if [ ${#WP_PATHS[@]} -eq 0 ]; then
    echo "❌ Tidak ada instalasi WordPress ditemukan."
    exit 1
fi

echo "[2] Mengunduh WordPress versi terbaru..."
wget -q -O "$ZIP_FILE" "$WP_URL"
if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ Gagal mengunduh WordPress."
    exit 1
fi

echo "[3] Mengekstrak WordPress..."
unzip -q "$ZIP_FILE" -d "$TMP_DIR"
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "❌ Folder 'wordpress' tidak ditemukan setelah ekstrak."
    exit 1
fi

echo "[4] Memperbarui instalasi WordPress..."

for wp_path in "${WP_PATHS[@]}"; do
    echo "→ Memproses: $wp_path"

    for item in "$EXTRACT_DIR"/*; do
        name=$(basename "$item")

        if [ "$name" == "wp-config.php" ]; then
            continue
        fi

        if [ "$name" == "wp-content" ]; then
            mkdir -p "$wp_path/wp-content"
            for sub in "$item"/*; do
                subname=$(basename "$sub")
                if [ "$subname" == "uploads" ]; then
                    continue
                fi
                cp -r "$sub" "$wp_path/wp-content/"
            done
        else
            cp -r "$item" "$wp_path/"
        fi
    done

    echo "✔ WordPress diperbarui di: $wp_path"
done

echo "[5] Memperbarui plugin (jika wp-cli tersedia)..."

if command -v wp &> /dev/null; then
    for wp_path in "${WP_PATHS[@]}"; do
        echo "→ Update plugin di: $wp_path"
        wp plugin update --all --path="$wp_path"
    done
else
    echo "⚠️ WP-CLI tidak ditemukan. Plugin tidak diperbarui."
fi

#rm -rf "$TMP_DIR"

echo "✅ Selesai. Semua WordPress telah diperbarui."
