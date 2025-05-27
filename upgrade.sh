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

echo "[3] Reset permission file dan folder..."
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

echo "[3.1] Menghapus core WordPress lama..."
FILES_TO_DELETE=(
    "index.php" "wp-activate.php" "wp-blog-header.php" "wp-comments-post.php"
    "wp-cron.php" "wp-links-opml.php" "wp-load.php" "wp-login.php"
    "wp-mail.php" "wp-settings.php" "wp-signup.php" "wp-trackback.php" "xmlrpc.php"
)

FOLDERS_TO_DELETE=(
    "wp-admin" "wp-includes"
)

for wp_path in "${WP_PATHS[@]}"; do
    echo "→ Membersihkan di: $wp_path"

    for file in "${FILES_TO_DELETE[@]}"; do
        if [ -f "$wp_path/$file" ]; then
            rm -f "$wp_path/$file"
            echo "   ↳ Hapus file: $file"
        fi
    done

    for folder in "${FOLDERS_TO_DELETE[@]}"; do
        if [ -d "$wp_path/$folder" ]; then
            rm -rf "$wp_path/$folder"
            echo "   ↳ Hapus folder: $folder"
        fi
    done
done


echo "[4] Mengekstrak WordPress..."
unzip -q "$ZIP_FILE" -d "$TMP_DIR"
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "❌ Folder 'wordpress' tidak ditemukan setelah ekstrak."
    exit 1
fi


echo "[4.1] Memperbarui instalasi WordPress..."
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
            echo "❌ Tidak ada plugin '$plugin_name' di situs resmi."
            echo "⚠️ Plugin '$plugin_name' belum diperbarui."
            continue
        fi

        PLUGIN_ZIP_URL="https://downloads.wordpress.org/plugin/${plugin_name}.latest-stable.zip"
        PLUGIN_ZIP_PATH="$TMP_DIR/${plugin_name}.zip"

        wget -q -O "$PLUGIN_ZIP_PATH" "$PLUGIN_ZIP_URL"

        if [ ! -f "$PLUGIN_ZIP_PATH" ]; then
            echo "⚠️ Gagal mengunduh plugin: $plugin_name"
            continue
        fi

        unzip -q "$PLUGIN_ZIP_PATH" -d "$TMP_DIR"

        if [ -d "$TMP_DIR/$plugin_name" ]; then
            rm -rf "$PLUGIN_DIR/$plugin_name"
            mv "$TMP_DIR/$plugin_name" "$PLUGIN_DIR/"
            echo "✔ Plugin '$plugin_name' berhasil diperbarui."
        else
            echo "⚠️ Struktur plugin tidak valid: $plugin_name"
        fi

        rm -f "$PLUGIN_ZIP_PATH"
    done
done

echo "[6] Memperbarui theme secara manual dari wordpress.org..."

for wp_path in "${WP_PATHS[@]}"; do
    THEME_DIR="$wp_path/wp-content/themes"
    echo "→ Memproses theme di: $THEME_DIR"

    if [ ! -d "$THEME_DIR" ]; then
        echo "⚠️ Folder theme tidak ditemukan: $THEME_DIR"
        continue
    fi

    for theme_folder in "$THEME_DIR"/*/; do
        theme_name=$(basename "$theme_folder")
        echo "   ↳ Perbarui theme: $theme_name"

        THEME_PAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://wordpress.org/themes/${theme_name}/")
        if [ "$THEME_PAGE_STATUS" != "200" ]; then
            echo "❌ Tidak ada theme '$theme_name' di situs resmi."
            echo "⚠️ Theme '$theme_name' belum diperbarui."
            continue
        fi

        THEME_ZIP_URL="https://downloads.wordpress.org/theme/${theme_name}.latest-stable.zip"
        THEME_ZIP_PATH="$TMP_DIR/${theme_name}.zip"

        wget -q -O "$THEME_ZIP_PATH" "$THEME_ZIP_URL"

        if [ ! -f "$THEME_ZIP_PATH" ]; then
            echo "⚠️ Gagal mengunduh theme: $theme_name"
            continue
        fi

        unzip -q "$THEME_ZIP_PATH" -d "$TMP_DIR"

        if [ -d "$TMP_DIR/$theme_name" ]; then
            rm -rf "$THEME_DIR/$theme_name"
            mv "$TMP_DIR/$theme_name" "$THEME_DIR/"
            echo "✔ Theme '$theme_name' berhasil diperbarui."
        else
            echo "⚠️ Struktur theme tidak valid: $theme_name"
        fi

        rm -f "$THEME_ZIP_PATH"
    done
done

rm -rf "$TMP_DIR"


echo "[7] Menampilkan user terdaftar dan opsi reset password..."

for WP_PATH in "${WP_PATHS[@]}"; do
    echo "→ Memproses instalasi di: $WP_PATH"
    CONFIG_FILE="$WP_PATH/wp-config.php"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "   ❌ wp-config.php tidak ditemukan di $WP_PATH"
        continue
    fi

    DB_NAME=$(php -r "include('$CONFIG_FILE'); echo DB_NAME;" 2>/dev/null)
    DB_USER=$(php -r "include('$CONFIG_FILE'); echo DB_USER;" 2>/dev/null)
    DB_PASSWORD=$(php -r "include('$CONFIG_FILE'); echo DB_PASSWORD;" 2>/dev/null)
    RAW_DB_HOST=$(php -r "include('$CONFIG_FILE'); echo DB_HOST;" 2>/dev/null)
    DB_HOST=$(echo "$RAW_DB_HOST" | cut -d':' -f1)
    DB_PORT=$(echo "$RAW_DB_HOST" | cut -s -d':' -f2)
    TABLE_PREFIX=$(php -r "include('$CONFIG_FILE'); echo \$table_prefix;" 2>/dev/null)

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_HOST" ] || [ -z "$TABLE_PREFIX" ]; then
        echo "   ❌ Gagal membaca konfigurasi dari wp-config.php"
        continue
    fi

    MYSQL_CMD=(mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST")
    if [ -n "$DB_PORT" ]; then
        MYSQL_CMD+=(-P "$DB_PORT")
    fi
    MYSQL_CMD+=("$DB_NAME")

    QUERY_USERS="SELECT ID, user_login FROM ${TABLE_PREFIX}users;"
    USERS=($("${MYSQL_CMD[@]}" -N -e "$QUERY_USERS" 2>/dev/null))

    if [ ${#USERS[@]} -eq 0 ]; then
        echo "   ⚠️ Tidak ada user ditemukan di database."
        continue
    fi

    echo "   📋 Daftar User WordPress:"
    USER_IDS=()
    USERNAMES=()
    i=0
    while [ $i -lt ${#USERS[@]} ]; do
        ID="${USERS[$i]}"
        USER="${USERS[$((i+1))]}"

        ROLE_QUERY="SELECT meta_value FROM ${TABLE_PREFIX}usermeta WHERE user_id=$ID AND meta_key='${TABLE_PREFIX}capabilities';"
        META_VALUE=$("${MYSQL_CMD[@]}" -N -e "$ROLE_QUERY" 2>/dev/null)
        ROLE=$(echo "$META_VALUE" | sed -E 's/.*s:[0-9]+:"([^"]+)".*/\1/')

        LABEL=$(echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ" | cut -c$((i/2+1)))
        echo "    [$LABEL] $USER | Role: $ROLE"

        USER_IDS+=("$ID")
        USERNAMES+=("$USER")
        i=$((i + 2))
    done

    read -p "   ❓ Ingin mereset password salah satu user? (y/n): " jawab
    if [[ "$jawab" =~ ^[Yy]$ ]]; then
        read -p "   🔤 Pilih user [A-Z]: " pilihan
        pilihan_upper=$(echo "$pilihan" | tr '[:lower:]' '[:upper:]')
        idx=$(printf "%d" "'$pilihan_upper")
        idx=$((idx - 65))

        if [ $idx -ge 0 ] && [ $idx -lt ${#USER_IDS[@]} ]; then
            selected_id=${USER_IDS[$idx]}
            selected_user=${USERNAMES[$idx]}
            new_pass=$(openssl rand -base64 12)
            hashed_pass=$(php -r "require_once('$wp_path/wp-load.php'); echo wp_hash_password('$new_pass');")

            UPDATE_QUERY="UPDATE ${TABLE_PREFIX}users SET user_pass='$hashed_pass' WHERE ID=$selected_id;"
            "${MYSQL_CMD[@]}" -e "$UPDATE_QUERY" 2>/dev/null

            echo "   ✅ Password user '$selected_user' berhasil direset!"
            echo "   🔐 Password baru: $new_pass"
        else
            echo "   ❌ Pilihan tidak valid."
        fi
    else
        echo "   ⏩ Melewati reset password."
    fi
done

echo "✅ Selesai. Semua WordPress telah diperbarui."
echo "⚠️ Silahkan periksa file malware/backdoor diluar struktur web dan segera hapus!"
