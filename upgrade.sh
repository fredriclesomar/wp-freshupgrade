#!/bin/bash


echo -e "\e[1;36m┌─────────────────────────────────────────────┐\e[0m"
echo -e "\e[1;36m│      \e[1;33mWordPress Maintenance & Hardening\e[1;36m      │\e[0m"
echo -e "\e[1;36m└─────────────────────────────────────────────┘\e[0m"
echo -e "\e[1;32mAuthor :\e[0m Fredric Lesomar"
echo -e "\e[1;32mEmail  :\e[0m hi@fredriclesomar.my.id"
echo -e "\e[1;32mVersi  :\e[0m 2.4"
echo


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
        echo "   ❌ Gagal membaca konfigurasi database."
        continue
    fi
echo "======================================================="
    echo "   Daftar user yang ada di database ($DB_NAME):"
    QUERY="SELECT ID, user_login, user_email, user_registered FROM ${TABLE_PREFIX}users;"
    USERS=$(mysql -N -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "${DB_PORT:-3306}" -D "$DB_NAME" -e "$QUERY" 2>/dev/null)

    if [ -z "$USERS" ]; then
        echo "   ❌ Gagal mendapatkan daftar user dari database."
        continue
    fi

    echo "$USERS" | awk '{print NR". "$2" <"$3"> (Registered: "$4")"}'

    echo -n "   Masukkan nomor user yang ingin direset passwordnya (atau ketik 0 untuk lewati): "
    read -r USER_CHOICE

    if [[ ! "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 0 ] || [ "$USER_CHOICE" -gt "$(echo "$USERS" | wc -l)" ]; then
        echo "   ❌ Pilihan tidak valid."
        continue
    fi

    if [ "$USER_CHOICE" -eq 0 ]; then
        echo "   → Lewati reset password."
        continue
    fi


    SELECTED_USER_LOGIN=$(echo "$USERS" | sed -n "${USER_CHOICE}p" | awk '{print $2}')
    SELECTED_USER_ID=$(echo "$USERS" | sed -n "${USER_CHOICE}p" | awk '{print $1}')

    NEW_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
    HASHED_PASS=$(php -r "
        require_once('$WP_PATH/wp-load.php');
        echo wp_hash_password('$NEW_PASS');
    ")

    if [ -z "$HASHED_PASS" ]; then
        echo "   ❌ Gagal menghasilkan hash password."
        continue
    fi

    SQL_UPDATE="UPDATE ${TABLE_PREFIX}users SET user_pass='$HASHED_PASS' WHERE ID=$SELECTED_USER_ID;"
    mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "${DB_PORT:-3306}" -D "$DB_NAME" -e "$SQL_UPDATE"

    echo "   ✔ Password user '$SELECTED_USER_LOGIN' berhasil direset menjadi: $NEW_PASS"
    
    echo "======================================================="
done

echo "[8] Apakah ingin melanjutkan proses hardening WordPress?"
read -p "   ❓ Lanjutkan proses hardening? (y/n): " harden_confirm

if [[ "$harden_confirm" =~ ^[Yy]$ ]]; then
    for wp_path in "${WP_PATHS[@]}"; do
        echo "🔐 Memulai hardening untuk: $wp_path"
        upload_dir="$wp_path/wp-content/uploads"
        backup_dir="/home/${USERCPANEL}/uploads_backup"
        htaccess_file="$upload_dir/.htaccess"

        read -p "   [1] Backup folder uploads ke luar public_html? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            mkdir -p "$backup_dir"
            zip -rq "$backup_dir/uploads_backup.zip" "$upload_dir"
            echo "   ✅ Backup selesai: $backup_dir/uploads_backup.zip"
        fi

        read -p "   [2] Tambahkan konfig blokir file .php di uploads? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "<FilesMatch \"\.(php|php5|phtml)$\">\nDeny from all\n</FilesMatch>" > "$htaccess_file"
            echo "   ✅ .htaccess ditambahkan."
        fi

        read -p "   [3] Nonaktifkan tombol tambah plugin dan theme? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            grep -q "DISALLOW_FILE_EDIT" "$wp_path/wp-config.php" || \
            echo "define('DISALLOW_FILE_MODS', true);" >> "$wp_path/wp-config.php"
            echo "   ✅ Konfigurasi ditambahkan."
        fi

        read -p "   [4] Tambahkan proteksi plugin dan theme editor? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            grep -q "DISALLOW_FILE_EDIT" "$wp_path/wp-config.php" || \
            echo "define('DISALLOW_FILE_EDIT', true);" >> "$wp_path/wp-config.php"
            echo "   ✅ Konfigurasi ditambahkan."
        fi

        # 5. Ubah permission wp-config.php
        read -p "   [5] Ubah permission wp-config.php ke 444? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            chmod 444 "$wp_path/wp-config.php"
            echo "   ✅ Permission diubah."
        fi

        read -p "   [6] Hapus plugin file manager jika ada? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$wp_path/wp-content/plugins/file-manager*"
            echo "   ✅ Plugin file manager dihapus (jika ada)."
        fi

        read -p "   [7] Blokir akses xmlrpc.php? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            htaccess_main="$wp_path/.htaccess"
            if ! grep -q "xmlrpc.php" "$htaccess_main"; then
                echo -e "\n<Files xmlrpc.php>\nOrder Allow,Deny\nDeny from all\n</Files>" >> "$htaccess_main"
                echo "   ✅ Akses xmlrpc.php diblokir."
            fi
        fi

        read -p "   [8] Hapus file PHP/HTML dalam uploads? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            find "$upload_dir" -type f \( -iname "*.php*" -o -iname "*.htm*" \) -delete
            echo "   ✅ File berbahaya dihapus."
        fi

        read -p "   [9] Tambahkan index.php di setiap folder uploads? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            find "$upload_dir" -type d | while read -r folder; do
                echo "<?php // Silence is golden ?>" > "$folder/index.php"
            done
            echo "   ✅ File index.php ditambahkan."
        fi
    done
else
    echo "⏩ Melewati proses hardening WordPress."
fi

echo "✅ Selesai. Semua WordPress telah diperbarui."
echo "⚠️ Silahkan periksa file malware/backdoor diluar struktur web dan segera hapus!"
