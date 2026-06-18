#!/bin/bash
# WordPress Maintenance & Hardening
# Author: Fredric Lesomar
# Version: 2.9.1


MYSQL_DEFAULTS_FILES=()

cleanup() {
    echo " Membersihkan file temporary..."

    [ -f "${ZIP_FILE:-}" ] && rm -f "$ZIP_FILE"
    [ -d "${EXTRACT_DIR:-}" ] && rm -rf "$EXTRACT_DIR"

    # Hapus file konfigurasi MySQL temporary agar password database tidak tertinggal.
    if [ "${#MYSQL_DEFAULTS_FILES[@]}" -gt 0 ]; then
        for mysql_defaults_file in "${MYSQL_DEFAULTS_FILES[@]}"; do
            [ -f "$mysql_defaults_file" ] && rm -f "$mysql_defaults_file"
        done
    fi

}

echo -e "\e[1;36m┌─────────────────────────────────────────────┐\e[0m"
echo -e "\e[1;36m│ \e[1;33mWordPress Maintenance & Hardening\e[1;36m │\e[0m"
echo -e "\e[1;36m└─────────────────────────────────────────────┘\e[0m"
echo -e "\e[1;32mAuthor :\e[0m Fredric Lesomar ✅"
echo -e "\e[1;32mEmail  :\e[0m hi@fredriclesomar.my.id"
echo -e "\e[1;32mVersi  :\e[0m 2.9.1"
echo

if [[ "$1" == "--help" ]]; then
    echo "Usage:"
    echo "  ./upgrade.sh -u usercPanel [-m true|false]"
    echo
    echo "Opsi:"
    echo "  -u  Username cPanel (wajib)"
    echo "  -m  Skip instalasi Multisite (default: true)"
    echo
    echo "Contoh:"
    echo "  ./upgrade.sh -u usercPanel              # multisite akan di-skip"
    echo "  ./upgrade.sh -u usercPanel -m false     # tetap proses multisite"
    echo
    echo "Debug:"
    echo "  bash -x ./upgrade.sh -u usercPanel"
    echo "  bash -x ./upgrade.sh -u usercPanel -m false"
    echo
    echo "Kirim hasil debug ke email saya"
    exit 0
fi

if [[ "$1" == "--fitur" ]]; then
    echo "Update WordPress Core"
    echo "Support Multisite(kalau ada)"
    echo "Reset Permission: File ke 644, direktori ke 755"
    echo "Update Plugin & Theme"
    echo "Reset Password User"
    echo "Opsi Hardening atau mengamankan WP"
    echo "Clean-up otomatis"
    echo "Resume otomatis jika proses gagal/interrupted"
    echo "Koneksi MySQL lebih aman menggunakan temporary defaults file"
    echo
    exit 0
fi

SKIP_MULTISITE=true
while getopts u:m: flag; do
    case "${flag}" in
        u) USERCPANEL=${OPTARG} ;;
        m) SKIP_MULTISITE=${OPTARG} ;;
        *) echo "Usage: $0 -u usercpanel [-m true|false]"; exit 1 ;;
    esac
done

if [ -z "${USERCPANEL:-}" ]; then
    echo " Username cPanel tidak diberikan."
    echo "Usage: $0 -u usercpanel [-m true|false]"
    exit 1
fi

BASE_DIR="/home/${USERCPANEL}/public_html"
WP_URL="https://wordpress.org/latest.zip"
TMP_DIR="/home/${USERCPANEL}/tmp_wp"
PLUG_DIR="/home/${USERCPANEL}/WP_gagal_update"
ZIP_FILE="$TMP_DIR/latest.zip"
EXTRACT_DIR="$TMP_DIR/wordpress"
BACKUP_ROOT="/home/${USERCPANEL}/wp_backups"
SESI_LOCK="/home/${USERCPANEL}/wp_backups/sesi"
LOCKFILE="/tmp/upgrade_wp_${USERCPANEL}.lock"
STATE_FILE="$SESI_LOCK/upgrade_state.txt"
CORE_DONE_FILE="$SESI_LOCK/core_done.list"
PLUGIN_DONE_FILE="$SESI_LOCK/plugin_done.list"
THEME_DONE_FILE="$SESI_LOCK/theme_done.list"
USERS_DONE_FILE="$SESI_LOCK/users_done.list"
HARDEN_DONE_FILE="$SESI_LOCK/harden_done.list"

mkdir -p "$TMP_DIR"
mkdir -p "$PLUG_DIR"
mkdir -p "$BACKUP_ROOT"
mkdir -p "$SESI_LOCK"

# Bersihkan hanya hasil extract lama, bukan seluruh sesi resume.
rm -rf "$EXTRACT_DIR" 2>/dev/null || true

# Buat file state/done list jika belum ada, jangan dikosongkan setiap run.
touch "$CORE_DONE_FILE" 2>/dev/null || true
touch "$PLUGIN_DONE_FILE" 2>/dev/null || true
touch "$THEME_DONE_FILE" 2>/dev/null || true
touch "$USERS_DONE_FILE" 2>/dev/null || true
touch "$HARDEN_DONE_FILE" 2>/dev/null || true

# Jika state belum ada atau kosong, mulai dari 0.
[ -s "$STATE_FILE" ] || echo "0" > "$STATE_FILE"

save_state() {
    # $1 = step number (integer)
    echo "$1" > "$STATE_FILE"
}

get_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

site_mark_done() {
    # $1 = filename, $2 = wp_path
    if ! grep -Fxq "$2" "$1" 2>/dev/null; then
        printf "%s\n" "$2" >> "$1"
    fi
}

site_is_done() {
    # $1 = filename, $2 = wp_path
    grep -Fxq "$2" "$1" 2>/dev/null
}

clear_state() {
    rm -f "$STATE_FILE" \
          "$CORE_DONE_FILE" \
          "$PLUGIN_DONE_FILE" \
          "$THEME_DONE_FILE" \
          "$USERS_DONE_FILE" \
          "$HARDEN_DONE_FILE" 2>/dev/null || true
}

download_wordpress() {
    mkdir -p "$TMP_DIR"

    if ! curl -# -L "$WP_URL" -o "$ZIP_FILE"; then
        echo " Gagal mengunduh WordPress. Periksa koneksi internet atau firewall server."
        rm -f "$ZIP_FILE"
        return 1
    fi

    return 0
}

ensure_wordpress_zip() {
    if [ ! -s "$ZIP_FILE" ]; then
        echo "⚠️ File latest.zip tidak ditemukan. Mengunduh ulang WordPress untuk melanjutkan proses..."
        download_wordpress || return 1
    fi

    return 0
}

mysql_cnf_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

create_mysql_defaults_file() {
    local mysql_file

    mysql_file=$(mktemp "/tmp/wp_mysql_${USERCPANEL}_XXXXXX.cnf") || return 1
    chmod 600 "$mysql_file"

    {
        echo "[client]"
        printf 'user="%s"\n' "$(mysql_cnf_escape "$DB_USER")"
        printf 'password="%s"\n' "$(mysql_cnf_escape "$DB_PASSWORD")"
        printf 'host="%s"\n' "$(mysql_cnf_escape "$DB_HOST")"
        printf 'port="%s"\n' "${DB_PORT:-3306}"
        printf 'database="%s"\n' "$(mysql_cnf_escape "$DB_NAME")"
    } > "$mysql_file"

    MYSQL_DEFAULTS_FILES+=("$mysql_file")
    printf '%s' "$mysql_file"
}

cleanup_lock() {
    local exit_code=$?
    cleanup
    [ -f "$LOCKFILE" ] && rm -f "$LOCKFILE"
    return "$exit_code"
}

trap cleanup_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -e "$LOCKFILE" ]; then
    oldpid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        echo " Script sudah berjalan dengan PID $oldpid (lockfile: $LOCKFILE)."
        echo "Keluar."
        exit 1
    else
        echo "⚠️ Lockfile ditemukan tapi PID tidak aktif. Mengganti lockfile."
    fi
fi

echo $$ > "$LOCKFILE"

LAST_STEP=$(get_state)
echo "ℹ️ State terakhir: langkah $LAST_STEP (0 = belum mulai)."
echo

echo "[1️⃣ ] Mendeteksi instalasi WordPress di $BASE_DIR..."
WP_PATHS=()
MULTISITE_PATHS=()

if [ ! -d "$BASE_DIR" ]; then
    echo " Direktori $BASE_DIR tidak ditemukan."
    exit 1
fi

find "$BASE_DIR" -type f -name 'wp-config.php' > "$TMP_DIR/wp_paths.txt"

while IFS= read -r config_file; do
    dir=$(dirname "$config_file")

    if grep -E -q "define\s*\(\s*'MULTISITE'\s*,\s*true\s*\)" "$config_file"; then
        echo " Ada instalasi multisite di : $dir"
        if [ "$SKIP_MULTISITE" = true ]; then
            echo "⏩ Sementara lewati instalasi Multisite "
            echo "==============================================="
            echo " **Tambahkan opsi berikut agar Multisite diproses: ./upgrade.sh -u usercPanel -m false"
            echo "==============================================="
            echo
            continue
        else
            echo "✅ Memproses Multisite!"
            MULTISITE_PATHS+=("$dir")
        fi
    fi

    WP_PATHS+=("$dir")
done < "$TMP_DIR/wp_paths.txt"

if [ ${#WP_PATHS[@]} -eq 0 ]; then
    echo " Tidak ada instalasi WordPress ditemukan untuk diproses."
    exit 1
fi

if [ "$LAST_STEP" -lt 1 ]; then
    save_state 1
    LAST_STEP=1
fi

echo
if [ "$LAST_STEP" -lt 2 ]; then
    echo "[2️⃣ ] Mengunduh WordPress versi terbaru..."
    if ! download_wordpress; then
        exit 1
    fi
    save_state 2
    LAST_STEP=2
else
    echo " Lewati unduh WordPress — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 3 ]; then
    echo "[3️⃣ ] Reset permission file dan folder..."
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
    save_state 3
    LAST_STEP=3
else
    echo " Lewati reset permission — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 4 ]; then
    echo "[3️⃣ .1️⃣ ] Menghapus core WordPress lama dan membersihkan wp-content (kecuali uploads, plugins, themes)..."

    FILES_TO_DELETE=(
        "index.php"
        "wp-activate.php"
        "wp-blog-header.php"
        "wp-comments-post.php"
        "wp-cron.php"
        "wp-links-opml.php"
        "wp-load.php"
        "wp-login.php"
        "wp-mail.php"
        "wp-settings.php"
        "wp-signup.php"
        "wp-trackback.php"
        "xmlrpc.php"
    )

    FOLDERS_TO_DELETE=(
        "wp-admin"
        "wp-includes"
    )

    for wp_path in "${WP_PATHS[@]}"; do
        echo "→ Membersihkan di: $wp_path"

        for file in "${FILES_TO_DELETE[@]}"; do
            if [ -f "$wp_path/$file" ]; then
                rm -f "$wp_path/$file"
                echo " Hapus file: $file"
            fi
        done

        for folder in "${FOLDERS_TO_DELETE[@]}"; do
            if [ -d "$wp_path/$folder" ]; then
                rm -rf "$wp_path/$folder"
                echo " Hapus folder: $folder"
            fi
        done

        WPCONTENT="$wp_path/wp-content"
        if [ -d "$WPCONTENT" ]; then
            echo " Membersihkan isi $WPCONTENT kecuali uploads, plugins, themes..."
            for item in "$WPCONTENT"/*; do
                [ -e "$item" ] || continue
                name=$(basename "$item")
                if [[ "$name" != "uploads" && "$name" != "plugins" && "$name" != "themes" ]]; then
                    rm -rf "$item"
                    echo " Hapus: $name"
                fi
            done
        fi
    done

    save_state 4
    LAST_STEP=4
else
    echo " Lewati pembersihan core lama — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 5 ]; then
    echo "[4️⃣ ] Mengekstrak WordPress..."

    if ! ensure_wordpress_zip; then
        exit 1
    fi

    rm -rf "$EXTRACT_DIR" 2>/dev/null || true
    unzip -q "$ZIP_FILE" -d "$TMP_DIR"

    if [ ! -d "$EXTRACT_DIR" ]; then
        echo " Folder 'wordpress' tidak ditemukan setelah ekstrak."
        exit 1
    fi

    echo "[4️⃣ .1️⃣ ] Memperbarui instalasi WordPress..."

    for wp_path in "${WP_PATHS[@]}"; do
        if site_is_done "$CORE_DONE_FILE" "$wp_path"; then
            echo "→ Lewati core update (sudah selesai): $wp_path"
            continue
        fi

        echo "→ Memproses: $wp_path"
        backup_dir="$BACKUP_ROOT/$(basename "$wp_path")_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        backup_file="$backup_dir/backup.tar.gz"

        echo " Membuat backup dan simpan di → $backup_file..."
        if ! tar -zcf "$backup_file" -C "$(dirname "$wp_path")" "$(basename "$wp_path")"; then
            echo " Gagal membuat backup, proses dibatalkan."
            exit 1
        fi

        if [ ! -f "$backup_file" ]; then
            echo " File backup tidak terdeteksi, proses dibatalkan."
            exit 1
        fi

        echo " ✅ Berhasil buat backup dengan ukuran file : $(du -sh "$backup_file" | cut -f1)"

        for item in "$EXTRACT_DIR"/*; do
            [ -e "$item" ] || continue
            name=$(basename "$item")

            if [ "$name" == "wp-config.php" ]; then
                continue
            fi

            if [ "$name" == "wp-content" ]; then
                mkdir -p "$wp_path/wp-content"
                for sub in "$item"/*; do
                    [ -e "$sub" ] || continue
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

        echo "✔ WordPress berhasil diperbarui untuk: $wp_path"
        site_mark_done "$CORE_DONE_FILE" "$wp_path"
    done

    save_state 5
    LAST_STEP=5
else
    echo " Lewati ekstrak & pembaruan core — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 6 ]; then
    echo "[5️⃣ ] Memperbarui plugin. Ambil data dari wordpress.org..."
    FAILED_PLUGINS_FILE="$PLUG_DIR/plugin_gagal_update.txt"
    > "$FAILED_PLUGINS_FILE"

    for wp_path in "${WP_PATHS[@]}"; do
        if site_is_done "$PLUGIN_DONE_FILE" "$wp_path"; then
            echo "→ Lewati pembaruan plugin (sudah selesai): $wp_path"
            continue
        fi

        PLUGIN_DIR="$wp_path/wp-content/plugins"
        echo "→ Memproses plugin di: $PLUGIN_DIR"

        if [ ! -d "$PLUGIN_DIR" ]; then
            echo "⚠️ Folder plugin tidak ditemukan: $PLUGIN_DIR"
            site_mark_done "$PLUGIN_DONE_FILE" "$wp_path"
            continue
        fi

        shopt -s nullglob
        for plugin_folder in "$PLUGIN_DIR"/*/; do
            plugin_name=$(basename "$plugin_folder")
            echo " ↳ Perbarui plugin: $plugin_name"

            PLUGIN_PAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://wordpress.org/plugins/${plugin_name}/")
            if [ "$PLUGIN_PAGE_STATUS" != "200" ]; then
                echo " Tidak ada plugin '$plugin_name' di situs resmi WordPress.org."
                echo "$plugin_name - tidak ada di wordpress.org | $PLUGIN_DIR/$plugin_name" >> "$FAILED_PLUGINS_FILE"
                echo "️ Menghapus plugin '$plugin_name'..."
                rm -rf "$PLUGIN_DIR/$plugin_name"
                continue
            fi

            PLUGIN_ZIP_URL="https://downloads.wordpress.org/plugin/${plugin_name}.latest-stable.zip"
            PLUGIN_ZIP_PATH="$TMP_DIR/${plugin_name}.zip"
            rm -f "$PLUGIN_ZIP_PATH"
            rm -rf "$TMP_DIR/$plugin_name"

            wget -q -O "$PLUGIN_ZIP_PATH" "$PLUGIN_ZIP_URL"

            if [ ! -s "$PLUGIN_ZIP_PATH" ]; then
                echo "⚠️ Gagal mengunduh plugin: $plugin_name"
                echo "$plugin_name - tidak ada di wordpress.org | $PLUGIN_DIR/$plugin_name" >> "$FAILED_PLUGINS_FILE"
                echo "️ Menghapus plugin '$plugin_name'..."
                rm -rf "$PLUGIN_DIR/$plugin_name"
                rm -f "$PLUGIN_ZIP_PATH"
                continue
            fi

            unzip -q "$PLUGIN_ZIP_PATH" -d "$TMP_DIR"

            if [ -d "$TMP_DIR/$plugin_name" ]; then
                rm -rf "$PLUGIN_DIR/$plugin_name"
                mv "$TMP_DIR/$plugin_name" "$PLUGIN_DIR/"
                echo " ✔ Plugin '$plugin_name' berhasil diperbarui."
            else
                echo "⚠️ Struktur plugin tidak valid: $plugin_name"
                echo "$plugin_name - struktur tidak valid | $PLUGIN_DIR/$plugin_name" >> "$FAILED_PLUGINS_FILE"
                echo "️ Menghapus plugin '$plugin_name'..."
                rm -rf "$PLUGIN_DIR/$plugin_name"
                rm -rf "$TMP_DIR/$plugin_name"
            fi

            rm -f "$PLUGIN_ZIP_PATH"
        done
        shopt -u nullglob

        site_mark_done "$PLUGIN_DONE_FILE" "$wp_path"
    done

    if [ -s "$FAILED_PLUGINS_FILE" ]; then
        echo "======================================="
        echo " List Plugin yang gagal diperbarui : $FAILED_PLUGINS_FILE"
        echo "======================================="
    else
        echo "✅ Semua plugin berhasil diperbarui."
    fi

    save_state 6
    LAST_STEP=6
else
    echo " Lewati pembaruan plugin — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 7 ]; then
    echo "[6️⃣ ] Memperbarui theme. Ambil data dari wordpress.org..."
    FAILED_THEMES_FILE="$PLUG_DIR/tema_gagal_update.txt"
    > "$FAILED_THEMES_FILE"

    for wp_path in "${WP_PATHS[@]}"; do
        if site_is_done "$THEME_DONE_FILE" "$wp_path"; then
            echo "→ Lewati pembaruan theme (sudah selesai): $wp_path"
            continue
        fi

        THEME_DIR="$wp_path/wp-content/themes"
        echo "→ Memproses theme di: $THEME_DIR"

        if [ ! -d "$THEME_DIR" ]; then
            echo "⚠️ Folder theme tidak ditemukan: $THEME_DIR"
            site_mark_done "$THEME_DONE_FILE" "$wp_path"
            continue
        fi

        shopt -s nullglob
        for theme_folder in "$THEME_DIR"/*/; do
            theme_name=$(basename "$theme_folder")
            echo " ↳ Perbarui theme: $theme_name"

            THEME_PAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://wordpress.org/themes/${theme_name}/")
            if [ "$THEME_PAGE_STATUS" != "200" ]; then
                echo " Tidak ada theme '$theme_name' di situs resmi WordPress.org."
                echo "$theme_name - tidak ada di wordpress.org | $THEME_DIR/$theme_name" >> "$FAILED_THEMES_FILE"
                echo "️ Menghapus theme '$theme_name'..."
                rm -rf "$THEME_DIR/$theme_name"
                continue
            fi

            THEME_ZIP_URL="https://downloads.wordpress.org/theme/${theme_name}.latest-stable.zip"
            THEME_ZIP_PATH="$TMP_DIR/${theme_name}.zip"
            rm -f "$THEME_ZIP_PATH"
            rm -rf "$TMP_DIR/$theme_name"

            wget -q -O "$THEME_ZIP_PATH" "$THEME_ZIP_URL"

            if [ ! -s "$THEME_ZIP_PATH" ]; then
                echo "⚠️ Gagal mengunduh theme: $theme_name"
                echo "$theme_name - tidak ada di wordpress.org | $THEME_DIR/$theme_name" >> "$FAILED_THEMES_FILE"
                echo "️ Menghapus theme '$theme_name'..."
                rm -rf "$THEME_DIR/$theme_name"
                rm -f "$THEME_ZIP_PATH"
                continue
            fi

            unzip -q "$THEME_ZIP_PATH" -d "$TMP_DIR"

            if [ -d "$TMP_DIR/$theme_name" ]; then
                rm -rf "$THEME_DIR/$theme_name"
                mv "$TMP_DIR/$theme_name" "$THEME_DIR/"
                echo " ✔ Theme '$theme_name' berhasil diperbarui."
            else
                echo "⚠️ Struktur theme tidak valid: $theme_name"
                echo "$theme_name - struktur tidak valid | $THEME_DIR/$theme_name" >> "$FAILED_THEMES_FILE"
                echo "️ Menghapus theme '$theme_name'..."
                rm -rf "$THEME_DIR/$theme_name"
                rm -rf "$TMP_DIR/$theme_name"
            fi

            rm -f "$THEME_ZIP_PATH"
        done
        shopt -u nullglob

        site_mark_done "$THEME_DONE_FILE" "$wp_path"
    done

    if [ -s "$FAILED_THEMES_FILE" ]; then
        echo "======================================="
        echo " List Theme yang gagal diperbarui : $FAILED_THEMES_FILE"
        echo "======================================="
    else
        echo "✅ Semua theme berhasil diperbarui."
    fi

    save_state 7
    LAST_STEP=7
else
    echo " Lewati pembaruan theme — sudah tercatat di state."
fi

# Setelah core/plugin/theme selesai, folder temporary boleh dibersihkan.
rm -rf "$TMP_DIR" 2>/dev/null || true
mkdir -p "$TMP_DIR"

echo
if [ "$LAST_STEP" -lt 8 ]; then
    echo "[7️⃣ ] Menampilkan user terdaftar dan opsi reset password..."
    PROCESSED_MULTISITE=false

    for WP_PATH in "${WP_PATHS[@]}"; do
        if site_is_done "$USERS_DONE_FILE" "$WP_PATH"; then
            echo "→ Lewati user listing/reset (sudah selesai): $WP_PATH"
            continue
        fi

        echo "→ Memproses instalasi di: $WP_PATH"
        CONFIG_FILE="$WP_PATH/wp-config.php"

        if [ ! -f "$CONFIG_FILE" ]; then
            echo " wp-config.php tidak ditemukan di $WP_PATH"
            continue
        fi

        IS_MULTISITE=$(grep -E "define\(\s*'MULTISITE'\s*,\s*true\s*\)" "$CONFIG_FILE")
        if [[ -n "$IS_MULTISITE" && "$PROCESSED_MULTISITE" == true ]]; then
            echo " ⚠️ Lewati karena multisite sudah ditampilkan sebelumnya."
            site_mark_done "$USERS_DONE_FILE" "$WP_PATH"
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
            echo " Gagal membaca konfigurasi database."
            continue
        fi

        MYSQL_DEFAULTS_FILE=$(create_mysql_defaults_file)

        if [ -z "$MYSQL_DEFAULTS_FILE" ] || [ ! -f "$MYSQL_DEFAULTS_FILE" ]; then
            echo " Gagal membuat file konfigurasi MySQL temporary."
            continue
        fi

        echo "======================================================="
        echo " Daftar user yang ada di database ($DB_NAME):"

        QUERY="SELECT ID, user_login, user_email, user_registered FROM ${TABLE_PREFIX}users;"
        USERS=$(mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -e "$QUERY" 2>/dev/null)

        if [ -z "$USERS" ]; then
            echo " Gagal mendapatkan daftar user dari database."
            continue
        fi

        echo "$USERS" | awk '{print NR". "$2" <"$3"> (Registered: "$4")"}'

        if [[ -n "$IS_MULTISITE" ]]; then
            PROCESSED_MULTISITE=true
        fi

        while true; do
            echo -n " Masukkan nomor user yang ingin direset passwordnya (0 untuk lewati user | q untuk keluar): "
            read -r USER_CHOICE

            if [[ "$USER_CHOICE" == "q" || "$USER_CHOICE" == "Q" ]]; then
                echo " → Keluar dari reset password."
                break
            fi

            if [[ ! "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 0 ] || [ "$USER_CHOICE" -gt "$(echo "$USERS" | wc -l)" ]; then
                echo " Pilihan tidak valid."
                continue
            fi

            if [ "$USER_CHOICE" -eq 0 ]; then
                echo " → Lewati user ini."
                break
            fi

            SELECTED_USER_LOGIN=$(echo "$USERS" | sed -n "${USER_CHOICE}p" | awk '{print $2}')
            SELECTED_USER_ID=$(echo "$USERS" | sed -n "${USER_CHOICE}p" | awk '{print $1}')
            NEW_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

            if [ ! -f "$WP_PATH/wp-load.php" ]; then
                echo " File wp-load.php tidak ditemukan, tidak bisa generate hash password."
                continue
            fi

            HASHED_PASS=$(php -r " require_once('$WP_PATH/wp-load.php'); echo wp_hash_password('$NEW_PASS'); ")

            if [ -z "$HASHED_PASS" ]; then
                echo " Gagal menghasilkan hash password."
                continue
            fi

            SQL_UPDATE="UPDATE ${TABLE_PREFIX}users SET user_pass='$HASHED_PASS' WHERE ID=$SELECTED_USER_ID;"

            if mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -e "$SQL_UPDATE"; then
                echo " User '$SELECTED_USER_LOGIN' , password yang baru: $NEW_PASS"
            else
                echo " Gagal update password untuk user '$SELECTED_USER_LOGIN'."
            fi

            echo "-------------------------------------------------------"
        done

        echo "======================================================="
        site_mark_done "$USERS_DONE_FILE" "$WP_PATH"
    done

    save_state 8
    LAST_STEP=8
else
    echo " Lewati user listing/reset — sudah tercatat di state."
fi

echo
if [ "$LAST_STEP" -lt 9 ]; then
    echo "[8️⃣ ] Apakah ingin melanjutkan proses hardening WordPress?"
    read -p "️ Lanjutkan proses hardening? (y/n): " harden_confirm

    if [[ "$harden_confirm" =~ ^[Yy]$ ]]; then
        for wp_path in "${WP_PATHS[@]}"; do
            if site_is_done "$HARDEN_DONE_FILE" "$wp_path"; then
                echo "→ Lewati hardening (sudah selesai): $wp_path"
                continue
            fi

            echo "️ Memulai hardening untuk: $wp_path"
            upload_dir="$wp_path/wp-content/uploads"
            backup_dir="/home/${USERCPANEL}/uploads_backup"
            htaccess_file="$upload_dir/.htaccess"
            wp_config="$wp_path/wp-config.php"

            read -p " [1] Backup folder uploads ke luar public_html? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                mkdir -p "$backup_dir"
                zip -rq "$backup_dir/uploads_backup.zip" "$upload_dir"
                echo " ✅ Backup selesai: $backup_dir/uploads_backup.zip"
            fi

            read -p " [2] Tambahkan konfig blokir file .php di uploads? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                mkdir -p "$upload_dir"
                echo -e "\nDeny from all\n" > "$htaccess_file"
                echo " ✅ .htaccess ditambahkan."
            fi

            read -p " [3] Nonaktifkan tombol tambah plugin dan theme? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                grep -q "DISALLOW_FILE_MODS" "$wp_config" || \
                    echo "define('DISALLOW_FILE_MODS', true);" >> "$wp_config"
                echo " ✅ Konfigurasi ditambahkan."
            fi

            read -p " [4] Tambahkan proteksi plugin dan theme editor? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                grep -q "DISALLOW_FILE_EDIT" "$wp_config" || \
                    echo "define('DISALLOW_FILE_EDIT', true);" >> "$wp_config"
                echo " ✅ Konfigurasi ditambahkan."
            fi

            read -p " [5] Update SALT WordPress? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [ -f "$wp_config" ]; then
                    echo " Mengambil SALT baru dari WordPress.org..."
                    NEW_SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

                    if [ -n "$NEW_SALT" ]; then
                        cp "$wp_config" "$wp_config.bak"
                        sed -i '/\/\*\*#@\+/,/\/\*\*#@-\*\//d' "$wp_config"
                        sed -i "/define( *['\"]AUTH_KEY/d; /define( *['\"]SECURE_AUTH_KEY/d; /define( *['\"]LOGGED_IN_KEY/d; /define( *['\"]NONCE_KEY/d; /define( *['\"]AUTH_SALT/d; /define( *['\"]SECURE_AUTH_SALT/d; /define( *['\"]LOGGED_IN_SALT/d; /define( *['\"]NONCE_SALT/d" "$wp_config"
                        awk -v salt="$NEW_SALT" '
                            /That\047s all, stop editing!/ {
                                print "/**#@+"
                                print " * Authentication unique keys and salts."
                                print " */"
                                print salt
                                print "/**#@-*/"
                                print ""
                                print $0
                                next
                            }
                            { print }
                        ' "$wp_config" > "$wp_config.tmp" && mv "$wp_config.tmp" "$wp_config"
                        echo " ✅ SALT berhasil diperbarui."
                    else
                        echo " ⚠️ Gagal mengambil SALT baru dari API."
                    fi
                else
                    echo " ⚠️ File wp-config.php tidak ditemukan."
                fi
            fi

            read -p " [6] Ubah permission wp-config.php ke 444? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                chmod 444 "$wp_config"
                echo " ✅ Permission diubah menjadi 444."
            fi

            read -p " [7] Hapus plugin file manager jika ada? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rm -rf "$wp_path/wp-content/plugins/"*file*manager*
                echo " ✅ Plugin file manager dihapus (jika ada)."
            fi

            read -p " [8] Blokir akses xmlrpc.php? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                htaccess_main="$wp_path/.htaccess"
                if ! grep -q "xmlrpc.php" "$htaccess_main" 2>/dev/null; then
                    cat >> "$htaccess_main" <<'XMLRPC_BLOCK'

<Files xmlrpc.php>
Order Allow,Deny
Deny from all
</Files>
XMLRPC_BLOCK
                    echo " ✅ Akses xmlrpc.php diblokir."
                fi
            fi

            read -p " [9] Hapus file PHP/HTML dalam uploads? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [ -d "$upload_dir" ]; then
                    find "$upload_dir" -type f \( -iname "*.php*" -o -iname "*.htm*" \) -delete
                    echo " ✅ File berbahaya dihapus."
                else
                    echo " ⚠️ Folder uploads tidak ditemukan."
                fi
            fi

            read -p " [10] Tambahkan index.php di setiap folder uploads? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [ -d "$upload_dir" ]; then
                    find "$upload_dir" -type d | while read -r folder; do
                        echo "" > "$folder/index.php"
                    done
                    echo " ✅ File index.php ditambahkan."
                else
                    echo " ⚠️ Folder uploads tidak ditemukan."
                fi
            fi

            site_mark_done "$HARDEN_DONE_FILE" "$wp_path"
        done
    else
        echo "⛓️‍ Melewati proses hardening, WordPress Anda rentan terhadap isu keamanan!"
    fi

    save_state 9
    LAST_STEP=9
else
    echo " Lewati hardening — sudah tercatat di state."
fi

echo
clear_state
echo "✅ Sesi selesai. File state resume dibersihkan untuk run berikutnya."
echo " Semua WordPress telah diperbarui"
echo " Silahkan periksa file malware/backdoor diluar struktur web dan segera hapus!"
