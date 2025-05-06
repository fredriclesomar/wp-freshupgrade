#!/bin/bash

while getopts u: flag; do
    case "${flag}" in
        u) USERCPANEL=${OPTARG};;
        *) echo "Usage: $0 -u usercpanel"; exit 1;;
    esac
done

if [ -z "$USERCPANEL" ]; then
    echo "❌ Username cPanel tidak diberikan."
    echo "Usage: $0 -u usercpanel"
    exit 1
fi
BASE_DIR="/home/${USERCPANEL}/public_html"
WP_URL="https://wordpress.org/latest.zip"
TMP_DIR="/home/${USERCPANEL}/tmp_wp"
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

echo "[3.5] Reset permission file dan folder (kecuali folder 0750)..."
for wp_path in "${WP_PATHS[@]}"; do
    echo "→ Reset permission di: $wp_path"

    find "$wp_path" -type f -exec chmod 0644 {} \;

    find "$wp_path" -type d | while read -r dir; do
        current_perm=$(stat -c "%a" "$dir")
        if [ "$current_perm" != "750" ]; then
            chmod 0755 "$dir"
        fi
    done
done

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

echo "[5] Memperbarui plugin secara manual dari wordpress.org..."

for wp_path in "${WP_PATHS[@]}"; do
    PLUGIN_DIR="$wp_path/wp-content/plugins"
    echo "→ Memproses plugin di: $PLUGIN_DIR"

    if [ ! -d "$PLUGIN_DIR" ]; then
        echo "⚠️ Folder plugin tidak ditemukan: $PLUGIN_DIR"
        continue
    fi

    for plugin_folder in "$PLUGIN_DIR"/*/; do
        plugin_name=$(basename "$plugin_folder")
        echo "   ↳ Perbarui plugin: $plugin_name"

        PLUGIN_PAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://wordpress.org/plugins/${plugin_name}/")
        if [ "$PLUGIN_PAGE_STATUS" != "200" ]; then
            echo "     ❌ Tidak ada plugin '$plugin_name' di situs resmi."
            echo "     ⚠️ Plugin '$plugin_name' belum diperbarui."
            continue
        fi

        PLUGIN_ZIP_URL="https://downloads.wordpress.org/plugin/${plugin_name}.latest-stable.zip"
        PLUGIN_ZIP_PATH="$TMP_DIR/${plugin_name}.zip"

        wget -q -O "$PLUGIN_ZIP_PATH" "$PLUGIN_ZIP_URL"

        if [ ! -f "$PLUGIN_ZIP_PATH" ]; then
            echo "     ⚠️ Gagal mengunduh plugin: $plugin_name"
            continue
        fi

        unzip -q "$PLUGIN_ZIP_PATH" -d "$TMP_DIR"

        if [ -d "$TMP_DIR/$plugin_name" ]; then
            rm -rf "$PLUGIN_DIR/$plugin_name"
            mv "$TMP_DIR/$plugin_name" "$PLUGIN_DIR/"
            echo "     ✔ Plugin '$plugin_name' berhasil diperbarui."
        else
            echo "     ⚠️ Struktur plugin tidak valid: $plugin_name"
        fi

        rm -f "$PLUGIN_ZIP_PATH"
    done
done


#rm -rf "$TMP_DIR"

echo "✅ Selesai. Semua WordPress telah diperbarui."
