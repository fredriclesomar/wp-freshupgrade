#!/bin/bash
# WordPress Maintenance & Hardening
# Author: Fredric Lesomar
# Version: 3.5

MYSQL_DEFAULTS_FILES=()
WEB_UI_INSTALLED=false
WEB_UI_ROOTS=()
WEB_UI_STATUS_FILES=()
WEB_UI_LOG_FILES=()
WEB_UI_AUTO_REMOVE_DELAY=10
WEB_UI_REMOTE_URL="https://raw.githubusercontent.com/fredriclesomar/wp-freshupgrade/master/web/fresh-upgrade.php"
WEB_UI_TEMPLATE_MARKER="WP_FRESHUPGRADE_UI_V3_5"
WEB_UI_CURRENT_STEP="prepare"
WEB_UI_CURRENT_PROGRESS=0
WEB_UI_HTACCESS_BACKUP_DIR=""
WEB_UI_HTML_NAME="fresh-upgrade.php"
WEB_UI_STATUS_NAME="fresh-upgrade-status.json"
WEB_UI_LOG_NAME="fresh-upgrade-progress.log"
WEB_UI_MARKER="FRESH UPGRADE MAINTENANCE"

cleanup() {
    echo " Membersihkan file temporary..."

    [ -f "${ZIP_FILE:-}" ] && rm -f "$ZIP_FILE"
    [ -d "${EXTRACT_DIR:-}" ] && rm -rf "$EXTRACT_DIR"

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
echo -e "\e[1;32mVersi  :\e[0m 3.5"
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
    echo "Fresh Upgrade Web Status UI otomatis di root folder WordPress"
    echo "Status UI mengikuti proses upgrade.sh via fresh-upgrade-status.json"
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
WEB_UI_HTACCESS_BACKUP_DIR="$SESI_LOCK/htaccess_backups"

mkdir -p "$TMP_DIR"
mkdir -p "$PLUG_DIR"
mkdir -p "$BACKUP_ROOT"
mkdir -p "$SESI_LOCK"
mkdir -p "$WEB_UI_HTACCESS_BACKUP_DIR"

rm -rf "$EXTRACT_DIR" 2>/dev/null || true

touch "$CORE_DONE_FILE" 2>/dev/null || true
touch "$PLUGIN_DONE_FILE" 2>/dev/null || true
touch "$THEME_DONE_FILE" 2>/dev/null || true
touch "$USERS_DONE_FILE" 2>/dev/null || true
touch "$HARDEN_DONE_FILE" 2>/dev/null || true

[ -s "$STATE_FILE" ] || echo "0" > "$STATE_FILE"

save_state() {
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
    if ! grep -Fxq "$2" "$1" 2>/dev/null; then
        printf "%s\n" "$2" >> "$1"
    fi
}

site_is_done() {
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

json_escape() {
    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/}
    value=${value//$'\t'/ }
    printf '%s' "$value"
}

write_web_status() {
    local status="${1:-running}"
    local step="${2:-prepare}"
    local progress="${3:-0}"
    local message="${4:-Proses berjalan...}"
    local tmp_file status_file status_dir log_file

    WEB_UI_CURRENT_STEP="$step"
    WEB_UI_CURRENT_PROGRESS="$progress"

    if [ "$WEB_UI_INSTALLED" != true ] || [ "${#WEB_UI_STATUS_FILES[@]}" -eq 0 ]; then
        return 0
    fi

    for status_file in "${WEB_UI_STATUS_FILES[@]}"; do
        [ -n "$status_file" ] || continue
        status_dir=$(dirname "$status_file")
        mkdir -p "$status_dir" 2>/dev/null || continue
        tmp_file="$status_file.tmp"

        cat > "$tmp_file" <<EOF_STATUS
{
  "status": "$(json_escape "$status")",
  "step": "$(json_escape "$step")",
  "progress": $progress,
  "message": "$(json_escape "$message")",
  "updated_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF_STATUS

        chmod 0644 "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$status_file" 2>/dev/null || true
        chmod 0644 "$status_file" 2>/dev/null || true
    done

    for log_file in "${WEB_UI_LOG_FILES[@]}"; do
        [ -n "$log_file" ] || continue
        touch "$log_file" 2>/dev/null || true
        chmod 0644 "$log_file" 2>/dev/null || true
        printf '[%s] [%s] %s%% - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$step" "$progress" "$message" >> "$log_file" 2>/dev/null || true
        chmod 0644 "$log_file" 2>/dev/null || true
    done
}

write_builtin_web_ui_file() {
    local target_file="$1"

    cat > "$target_file" <<'EOF_WEB_UI'
<?php
declare(strict_types=1);

const FRESH_STATUS_NAME = 'fresh-upgrade-status.json';
const FRESH_LOG_NAME = 'fresh-upgrade-progress.log';

function fresh_upgrade_default_status(string $source = 'default'): array {
    return [
        'status' => 'running',
        'step' => 'prepare',
        'progress' => 0,
        'message' => 'Menunggu status backend upgrade.sh...',
        'updated_at' => date('Y-m-d H:i:s'),
        '_source' => $source,
    ];
}

function fresh_upgrade_sanitize_status(array $data, string $source = 'json'): array {
    $status = (string) ($data['status'] ?? 'running');
    $step = (string) ($data['step'] ?? 'prepare');
    $progress = (int) ($data['progress'] ?? 0);
    $message = (string) ($data['message'] ?? 'Proses berjalan...');
    $updatedAt = (string) ($data['updated_at'] ?? date('Y-m-d H:i:s'));

    $allowedStatus = ['running', 'done', 'failed', 'unknown'];
    $allowedSteps = ['prepare', 'download', 'core', 'plugin', 'theme', 'hardening', 'done'];

    if (!in_array($status, $allowedStatus, true)) $status = 'running';
    if (!in_array($step, $allowedSteps, true)) $step = 'prepare';
    if ($progress < 0) $progress = 0;
    if ($progress > 100) $progress = 100;

    return [
        'status' => $status,
        'step' => $step,
        'progress' => $progress,
        'message' => $message,
        'updated_at' => $updatedAt,
        '_source' => $source,
    ];
}

function fresh_upgrade_candidate_dirs(): array {
    $dirs = [];

    $dirs[] = __DIR__;
    $dirs[] = dirname((string)($_SERVER['SCRIPT_FILENAME'] ?? __FILE__));
    $dirs[] = (string)getcwd();

    if (!empty($_SERVER['DOCUMENT_ROOT']) && !empty($_SERVER['SCRIPT_NAME'])) {
        $scriptDir = trim(dirname((string)$_SERVER['SCRIPT_NAME']), '/\\');
        if ($scriptDir !== '' && $scriptDir !== '.') {
            $dirs[] = rtrim((string)$_SERVER['DOCUMENT_ROOT'], '/\\') . DIRECTORY_SEPARATOR . $scriptDir;
        }
    }

    $clean = [];
    foreach ($dirs as $dir) {
        if ($dir === '' || $dir === '.') continue;
        $real = realpath($dir);
        if ($real && is_dir($real)) {
            $clean[$real] = true;
        }
    }

    return array_keys($clean);
}

function fresh_upgrade_read_json_file(string $file): ?array {
    clearstatcache(true, $file);

    if (!is_file($file) || !is_readable($file)) {
        return null;
    }

    $raw = @file_get_contents($file);
    if ($raw === false || trim($raw) === '') {
        return null;
    }

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        return null;
    }

    return fresh_upgrade_sanitize_status($data, 'json');
}

function fresh_upgrade_read_log_file(string $file): ?array {
    clearstatcache(true, $file);

    if (!is_file($file) || !is_readable($file)) {
        return null;
    }

    $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!$lines) {
        return null;
    }

    for ($i = count($lines) - 1; $i >= 0; $i--) {
        $line = trim((string)$lines[$i]);
        if (preg_match('/^\[(.*?)\]\s+\[([^\]]+)\]\s+(\d+)%\s+-\s+(.*)$/u', $line, $m)) {
            return fresh_upgrade_sanitize_status([
                'status' => 'running',
                'step' => $m[2],
                'progress' => (int)$m[3],
                'message' => $m[4],
                'updated_at' => $m[1],
            ], 'log');
        }
    }

    return null;
}

function fresh_upgrade_debug_payload(array $status, array $dirs): array {
    if (!isset($_GET['fresh_debug'])) {
        unset($status['_source']);
        return $status;
    }

    $debug = [];
    foreach ($dirs as $dir) {
        $json = $dir . DIRECTORY_SEPARATOR . FRESH_STATUS_NAME;
        $log = $dir . DIRECTORY_SEPARATOR . FRESH_LOG_NAME;
        $debug[] = [
            'dir' => $dir,
            'json' => $json,
            'json_exists' => is_file($json),
            'json_readable' => is_readable($json),
            'json_perms' => is_file($json) ? substr(sprintf('%o', (int)fileperms($json)), -4) : null,
            'log' => $log,
            'log_exists' => is_file($log),
            'log_readable' => is_readable($log),
            'log_perms' => is_file($log) ? substr(sprintf('%o', (int)fileperms($log)), -4) : null,
        ];
    }

    $status['_debug'] = [
        'version' => '3.5',
        'source' => $status['_source'] ?? 'unknown',
        'script_filename' => (string)($_SERVER['SCRIPT_FILENAME'] ?? ''),
        'script_name' => (string)($_SERVER['SCRIPT_NAME'] ?? ''),
        'request_uri' => (string)($_SERVER['REQUEST_URI'] ?? ''),
        'candidates' => $debug,
    ];

    return $status;
}

function fresh_upgrade_read_status(): array {
    $dirs = fresh_upgrade_candidate_dirs();

    foreach ($dirs as $dir) {
        $status = fresh_upgrade_read_json_file($dir . DIRECTORY_SEPARATOR . FRESH_STATUS_NAME);
        if ($status !== null) {
            return fresh_upgrade_debug_payload($status, $dirs);
        }
    }

    foreach ($dirs as $dir) {
        $status = fresh_upgrade_read_log_file($dir . DIRECTORY_SEPARATOR . FRESH_LOG_NAME);
        if ($status !== null) {
            return fresh_upgrade_debug_payload($status, $dirs);
        }
    }

    return fresh_upgrade_debug_payload(fresh_upgrade_default_status('default'), $dirs);
}

$status = fresh_upgrade_read_status();

if (isset($_GET['fresh_status'])) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
    $publicStatus = $status;
    if (!isset($_GET['fresh_debug'])) {
        unset($publicStatus['_source']);
    }
    echo json_encode($publicStatus, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
?><!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow,noarchive">
  <meta name="referrer" content="no-referrer">
  <meta http-equiv="Cache-Control" content="no-store, no-cache, must-revalidate, max-age=0">
  <meta http-equiv="Pragma" content="no-cache">
  <meta http-equiv="Expires" content="0">
  <title>Fresh Upgrade Progress</title>
  <style>
    :root {
      --bg: #090b17;
      --panel: rgba(20, 22, 36, .92);
      --panel-2: rgba(39, 45, 74, .82);
      --text: #d9d2ff;
      --muted: #a3a4b6;
      --line: rgba(132, 103, 255, .16);
      --accent: #8768ff;
      --accent-2: #1c92ff;
      --success: #29d391;
      --danger: #ff5978;
      --warning: #ffb84d;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
        linear-gradient(var(--line) 1px, transparent 1px),
        linear-gradient(90deg, var(--line) 1px, transparent 1px),
        radial-gradient(circle at top, rgba(91, 81, 255, .22), transparent 34%),
        var(--bg);
      background-size: 64px 64px, 64px 64px, auto, auto;
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      display: grid;
      place-items: center;
      padding: 22px;
    }
    .shell {
      width: min(680px, 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      position: relative;
    }
    .card {
      width: min(500px, 100%);
      border: 1px solid rgba(139, 116, 255, .22);
      background: linear-gradient(180deg, rgba(20, 20, 31, .96), rgba(13, 15, 27, .96));
      box-shadow: 0 30px 80px rgba(0, 0, 0, .45), inset 0 1px rgba(255,255,255,.04);
      border-radius: 0;
      padding: 42px 46px 28px;
      text-align: center;
      position: relative;
      overflow: hidden;
    }
    .orb {
      width: 72px;
      height: 72px;
      margin: -8px auto 28px;
      border-radius: 50%;
      border: 3px solid rgba(139, 116, 255, .78);
      position: relative;
      display: grid;
      place-items: center;
      box-shadow: 0 0 38px rgba(76, 96, 255, .35);
      animation: float 2.8s ease-in-out infinite;
    }
    .orb::before {
      content: "";
      width: 50px;
      height: 50px;
      border-radius: 50%;
      border-right: 3px solid var(--accent-2);
      border-bottom: 3px solid transparent;
      animation: spin 1.1s linear infinite;
      position: absolute;
    }
    .orb span { position: relative; font-size: 22px; filter: drop-shadow(0 0 12px rgba(255,184,77,.45)); }
    .badge {
      display: inline-flex;
      gap: 8px;
      align-items: center;
      border: 1px solid rgba(150, 134, 255, .45);
      color: #c9c1ff;
      border-radius: 999px;
      padding: 5px 14px;
      font-size: 11px;
      font-weight: 800;
      letter-spacing: .08em;
      background: rgba(102, 91, 213, .22);
      text-transform: uppercase;
    }
    .badge i { width: 6px; height: 6px; background: currentColor; display: inline-block; border-radius: 999px; }
    h1 { margin: 22px 0 14px; font-size: clamp(28px, 5vw, 40px); line-height: 1.18; letter-spacing: -.04em; }
    p { margin: 0 auto; color: var(--muted); line-height: 1.65; max-width: 420px; font-size: 15px; }
    .progress-wrap { margin: 36px auto 24px; text-align: left; }
    .track { height: 7px; border-radius: 999px; background: rgba(97, 103, 133, .3); overflow: hidden; }
    .bar {
      width: 0%;
      height: 100%;
      border-radius: inherit;
      background: linear-gradient(90deg, var(--accent), var(--accent-2), var(--accent));
      background-size: 180% 100%;
      transition: width .45s ease;
      animation: gradient 1.8s linear infinite;
    }
    .progress-meta { display: flex; justify-content: space-between; gap: 14px; margin-top: 12px; color: #8f91a8; font-size: 12px; }
    .steps { display: grid; gap: 10px; text-align: left; margin-top: 26px; }
    .step {
      display: flex;
      align-items: center;
      gap: 14px;
      min-height: 42px;
      padding: 12px 16px;
      border-radius: 11px;
      background: rgba(42, 47, 67, .48);
      color: rgba(218, 219, 232, .65);
      font-size: 13px;
      transition: transform .25s ease, background .25s ease, color .25s ease;
    }
    .step .icon { width: 19px; text-align: center; opacity: .9; }
    .step.active { background: rgba(69, 78, 132, .62); color: #fff; transform: translateX(2px); box-shadow: inset 3px 0 0 var(--accent); }
    .step.done { color: rgba(230, 255, 245, .84); background: rgba(41, 211, 145, .12); }
    .step.failed { color: #ffe1e8; background: rgba(255, 89, 120, .16); box-shadow: inset 3px 0 0 var(--danger); }
    .debug { margin-top: 12px; min-height: 14px; font-size: 10px; color: rgba(163,164,182,.52); word-break: break-all; }
    .footer { margin-top: 30px; font-size: 11px; color: rgba(163,164,182,.62); }
    .footer b { color: #9c85ff; }
    @keyframes spin { to { transform: rotate(360deg); } }
    @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-5px); } }
    @keyframes gradient { 0% { background-position: 0% 50%; } 100% { background-position: 180% 50%; } }
    @media (max-width: 560px) { .card { padding: 34px 22px 22px; } .shell { min-height: auto; } }
  </style>
</head>
<body>
  <main class="shell">
    <section class="card">
      <div class="orb"><span>⚡</span></div>
      <div class="badge"><i></i> Maintenance Mode</div>
      <h1 id="title">Fresh Upgrade<br>Sedang Berlangsung</h1>
      <p id="description">Website sedang dalam proses pembaruan WordPress. Harap bersabar, kami akan segera kembali.</p>
      <div class="progress-wrap">
        <div class="track"><div id="bar" class="bar"></div></div>
        <div class="progress-meta"><span id="message">Memuat status...</span><span id="percent">0%</span></div>
      </div>
      <div class="steps">
        <div class="step" data-step="download"><span class="icon">📦</span><span>Mengunduh WordPress terbaru</span></div>
        <div class="step" data-step="core"><span class="icon">🔄</span><span>Memperbarui core WordPress</span></div>
        <div class="step" data-step="plugin"><span class="icon">🔌</span><span>Memperbarui plugin</span></div>
        <div class="step" data-step="theme"><span class="icon">🎨</span><span>Memperbarui theme</span></div>
        <div class="step" data-step="hardening"><span class="icon">🛡️</span><span>Hardening & keamanan</span></div>
      </div>
      <div id="debug" class="debug"></div>
      <div class="footer">Upgrade otomatis oleh <b>Fredric Lesomar</b> — v3.5</div>
    </section>
  </main>
  <script>
    window.__WP_FRESHUPGRADE_UI_VERSION__ = '3.5';
    window.FRESH_UPGRADE_INITIAL_STATUS = <?php echo json_encode($status, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES); ?>;

    const steps = ['download', 'core', 'plugin', 'theme', 'hardening'];
    const bar = document.getElementById('bar');
    const percent = document.getElementById('percent');
    const message = document.getElementById('message');
    const title = document.getElementById('title');
    const desc = document.getElementById('description');
    const debug = document.getElementById('debug');
    let doneReloadScheduled = false;
    let lastKnownDone = false;
    const finishedRefreshMessage = 'Fresh Upgrade telah selesai, silahkan refresh web Anda.';

    function statusUrl() {
      const url = new URL(window.location.href);
      url.searchParams.set('fresh_status', '1');
      url.searchParams.set('ts', String(Date.now()));
      return url.toString();
    }

    async function loadStatus() {
      const res = await fetch(statusUrl(), {
        cache: 'no-store',
        headers: { 'Accept': 'application/json' }
      });

      const text = await res.text();
      if (!res.ok) {
        throw new Error('HTTP ' + res.status + ': ' + text.slice(0, 80));
      }

      const data = JSON.parse(text);
      if (!data || typeof data !== 'object' || typeof data.progress === 'undefined') {
        throw new Error('Payload status tidak valid');
      }
      return data;
    }

    function setStep(activeStep, status) {
      document.querySelectorAll('[data-step]').forEach(el => {
        const step = el.getAttribute('data-step');
        const stepIndex = steps.indexOf(step);
        const activeIndex = steps.indexOf(activeStep);
        el.classList.remove('active', 'done', 'failed');
        if (status === 'failed' && step === activeStep) el.classList.add('failed');
        else if (status === 'done' || (activeIndex >= 0 && stepIndex < activeIndex)) el.classList.add('done');
        else if (step === activeStep) el.classList.add('active');
      });
    }

    function applyStatus(data) {
      const progress = Math.max(0, Math.min(100, Number(data.progress || 0)));
      bar.style.width = progress + '%';
      percent.textContent = progress + '%';
      message.textContent = data.message || 'Proses berjalan...';
      setStep(data.step || 'download', data.status || 'running');
      if (debug) debug.textContent = data.updated_at ? 'Last update: ' + data.updated_at : '';

      if (data.status === 'done') {
        lastKnownDone = true;
        title.innerHTML = 'Fresh Upgrade<br>Selesai';
        desc.textContent = 'Pembaruan WordPress telah selesai. Silahkan refresh web Anda.';
        message.textContent = finishedRefreshMessage;
        if (debug) debug.textContent = finishedRefreshMessage;
        if (!doneReloadScheduled) {
          doneReloadScheduled = true;
          setTimeout(() => window.location.reload(), 12000);
        }
      } else if (data.status === 'failed') {
        title.innerHTML = 'Fresh Upgrade<br>Perlu Dicek';
        desc.textContent = 'Proses berhenti atau gagal. Silakan cek terminal SSH untuk detail.';
      } else {
        title.innerHTML = 'Fresh Upgrade<br>Sedang Berlangsung';
        desc.textContent = 'Website sedang dalam proses pembaruan WordPress. Harap bersabar, kami akan segera kembali.';
      }
    }

    async function refresh() {
      try {
        const data = await loadStatus();
        applyStatus(data);
      } catch (e) {
        const errorMessage = e && e.message ? e.message : String(e || '');

        if (lastKnownDone || /JSON\.parse|unexpected character|Unexpected token|Payload status tidak valid/i.test(errorMessage)) {
          lastKnownDone = true;
          bar.style.width = '100%';
          percent.textContent = '100%';
          setStep('hardening', 'done');
          title.innerHTML = 'Fresh Upgrade<br>Selesai';
          desc.textContent = 'Pembaruan WordPress telah selesai. Silahkan refresh web Anda.';
          message.textContent = finishedRefreshMessage;
          if (debug) debug.textContent = finishedRefreshMessage;
          return;
        }

        if (debug) debug.textContent = 'Status API error: ' + errorMessage;
        if (!window.FRESH_UPGRADE_INITIAL_STATUS) {
          message.textContent = 'Menunggu status backend upgrade.sh...';
        }
      }
    }

    applyStatus(window.FRESH_UPGRADE_INITIAL_STATUS || { progress: 0, step: 'prepare', status: 'running', message: 'Menunggu status backend upgrade.sh...' });
    refresh();
    setInterval(refresh, 1500);
  </script>
</body>
</html>
EOF_WEB_UI
}

web_ui_safe_id() {
    local value="$1"
    value="${value#/}"
    value="${value//\//__}"
    value=$(printf '%s' "$value" | tr -c 'A-Za-z0-9._-' '_')
    printf '%s' "$value"
}

web_ui_backup_file_for_path() {
    local wp_path="$1"
    printf '%s/%s.htaccess' "$WEB_UI_HTACCESS_BACKUP_DIR" "$(web_ui_safe_id "$wp_path")"
}

web_ui_meta_file_for_path() {
    local wp_path="$1"
    printf '%s/%s.meta' "$WEB_UI_HTACCESS_BACKUP_DIR" "$(web_ui_safe_id "$wp_path")"
}

write_web_ui_htaccess() {
    local wp_path="$1"
    local htaccess="$wp_path/.htaccess"

    cat > "$htaccess" <<EOF_HTACCESS
# BEGIN FRESH UPGRADE MAINTENANCE
# Temporary file generated by wp-freshupgrade. Original .htaccess will be restored after successful upgrade.
Options -Indexes
<IfModule mod_headers.c>
Header set Cache-Control "no-store, no-cache, must-revalidate, max-age=0"
Header set Pragma "no-cache"
Header set Expires "0"
Header set X-Robots-Tag "noindex, nofollow, noarchive"
</IfModule>
<IfModule mod_rewrite.c>
RewriteEngine On

RewriteRule ^${WEB_UI_HTML_NAME}$ - [L]
RewriteCond %{QUERY_STRING} (^|&)fresh_status=1(&|$)
RewriteRule ^.*$ ${WEB_UI_HTML_NAME} [L,QSA]
RewriteRule (^|.*/)${WEB_UI_STATUS_NAME}$ ${WEB_UI_HTML_NAME}?fresh_status=1 [L,QSA]
RewriteRule (^|.*/)${WEB_UI_LOG_NAME}$ - [F,L]

RewriteRule ^.*$ ${WEB_UI_HTML_NAME} [L]
</IfModule>
# END FRESH UPGRADE MAINTENANCE
EOF_HTACCESS
}

install_web_ui_for_site() {
    local wp_path="$1"
    local html_file="$wp_path/$WEB_UI_HTML_NAME"
    local status_file="$wp_path/$WEB_UI_STATUS_NAME"
    local log_file="$wp_path/$WEB_UI_LOG_NAME"
    local htaccess="$wp_path/.htaccess"
    local backup_file meta_file

    [ -d "$wp_path" ] || return 1

    backup_file=$(web_ui_backup_file_for_path "$wp_path")
    meta_file=$(web_ui_meta_file_for_path "$wp_path")

    mkdir -p "$WEB_UI_HTACCESS_BACKUP_DIR" 2>/dev/null || true

    if [ -f "$htaccess" ] && grep -q "BEGIN $WEB_UI_MARKER" "$htaccess" 2>/dev/null; then
        echo "ℹ️ .htaccess maintenance sudah aktif di: $wp_path"
        echo "↻ Memperbarui rules .htaccess maintenance ke format v3.5 tanpa menimpa backup asli."
        write_web_ui_htaccess "$wp_path"
    else
        if [ -f "$htaccess" ]; then
            cp -p "$htaccess" "$backup_file" 2>/dev/null || cp "$htaccess" "$backup_file"
            printf 'exists
%s
' "$wp_path" > "$meta_file"
        else
            rm -f "$backup_file" 2>/dev/null || true
            printf 'missing
%s
' "$wp_path" > "$meta_file"
        fi
        write_web_ui_htaccess "$wp_path"
    fi

    if command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 5 --max-time 15 "$WEB_UI_REMOTE_URL" -o "$html_file"; then
        if grep -q "$WEB_UI_TEMPLATE_MARKER" "$html_file" 2>/dev/null; then
            echo "✅ Fresh Upgrade Web UI v3.5 berhasil diunduh dari repo untuk: $wp_path"
        else
            echo "⚠️ Template Web UI di repo belum v3.5/stale. Menggunakan template bawaan upgrade.sh untuk: $wp_path"
            write_builtin_web_ui_file "$html_file"
        fi
    else
        echo "⚠️ Gagal download Web UI dari repo. Menggunakan template bawaan upgrade.sh untuk: $wp_path"
        write_builtin_web_ui_file "$html_file"
    fi
    
    sed -i "s/status\.json/${WEB_UI_STATUS_NAME}/g; s/— v3\.[0-9]/— v3.5/g; s/v3\.[0-9]/v3.5/g" "$html_file" 2>/dev/null || true

    chmod 0644 "$html_file" "$htaccess" 2>/dev/null || true
    : > "$status_file" 2>/dev/null || true
    : > "$log_file" 2>/dev/null || true
    chmod 0644 "$status_file" "$log_file" 2>/dev/null || true

    WEB_UI_ROOTS+=("$wp_path")
    WEB_UI_STATUS_FILES+=("$status_file")
    WEB_UI_LOG_FILES+=("$log_file")

    echo "🌐 Maintenance UI aktif di root WordPress: $wp_path"
    echo "   File: $html_file"
}

install_web_ui() {
    local wp_path

    WEB_UI_ROOTS=()
    WEB_UI_STATUS_FILES=()
    WEB_UI_LOG_FILES=()

    for wp_path in "$@"; do
        install_web_ui_for_site "$wp_path" || true
    done

    if [ "${#WEB_UI_ROOTS[@]}" -gt 0 ]; then
        WEB_UI_INSTALLED=true
        write_web_status "running" "prepare" 3 "Menyiapkan Fresh Upgrade..."
        echo "✅ .htaccess maintenance aktif. Domain diarahkan ke $WEB_UI_HTML_NAME sampai proses selesai."
    else
        WEB_UI_INSTALLED=false
        echo "⚠️ Fresh Upgrade Web UI tidak aktif karena tidak ada root WordPress yang berhasil dipasang UI."
    fi
}

temporarily_restore_original_htaccess_for_backup() {
    local wp_path="$1"
    local htaccess="$wp_path/.htaccess"
    local backup_file meta_file state

    backup_file=$(web_ui_backup_file_for_path "$wp_path")
    meta_file=$(web_ui_meta_file_for_path "$wp_path")

    [ -f "$meta_file" ] || return 0
    state=$(head -n 1 "$meta_file" 2>/dev/null || echo "")

    if [ "$state" = "exists" ] && [ -f "$backup_file" ]; then
        cp -p "$backup_file" "$htaccess" 2>/dev/null || cp "$backup_file" "$htaccess"
    elif [ "$state" = "missing" ]; then
        rm -f "$htaccess" 2>/dev/null || true
    fi
}

reactivate_web_ui_htaccess_after_backup() {
    local wp_path="$1"
    [ "$WEB_UI_INSTALLED" = true ] || return 0
    write_web_ui_htaccess "$wp_path"
}

restore_web_ui_for_site() {
    local wp_path="$1"
    local htaccess="$wp_path/.htaccess"
    local html_file="$wp_path/$WEB_UI_HTML_NAME"
    local status_file="$wp_path/$WEB_UI_STATUS_NAME"
    local log_file="$wp_path/$WEB_UI_LOG_NAME"
    local backup_file meta_file state

    backup_file=$(web_ui_backup_file_for_path "$wp_path")
    meta_file=$(web_ui_meta_file_for_path "$wp_path")

    if [ -f "$meta_file" ]; then
        state=$(head -n 1 "$meta_file" 2>/dev/null || echo "")
        if [ "$state" = "exists" ] && [ -f "$backup_file" ]; then
            cp -p "$backup_file" "$htaccess" 2>/dev/null || cp "$backup_file" "$htaccess"
            echo "↩️ .htaccess asli dikembalikan: $wp_path"
        elif [ "$state" = "missing" ]; then
            rm -f "$htaccess" 2>/dev/null || true
            echo "↩️ .htaccess maintenance dihapus karena sebelumnya tidak ada .htaccess: $wp_path"
        else
            echo "⚠️ Metadata backup .htaccess tidak valid untuk: $wp_path"
        fi
        rm -f "$backup_file" "$meta_file" 2>/dev/null || true
    else
        if [ -f "$htaccess" ] && grep -q "BEGIN $WEB_UI_MARKER" "$htaccess" 2>/dev/null; then
            echo "⚠️ Tidak menemukan backup .htaccess untuk restore otomatis: $wp_path"
        fi
    fi

    rm -f "$html_file" "$status_file" "$log_file" "$wp_path/fresh-upgrade.html" 2>/dev/null || true
    echo "🧹 Fresh Upgrade Web UI dihapus dari root WordPress: $wp_path"
}

remove_web_ui() {
    local wp_path
    for wp_path in "${WEB_UI_ROOTS[@]}"; do
        restore_web_ui_for_site "$wp_path"
    done
    WEB_UI_INSTALLED=false
}

cleanup_lock() {
    local exit_code=$?

    if [ "$WEB_UI_INSTALLED" = true ]; then
        if [ "$exit_code" -eq 130 ]; then
            write_web_status "failed" "prepare" 0 "Fresh Upgrade dihentikan manual dari SSH."
        elif [ "$exit_code" -eq 143 ]; then
            write_web_status "failed" "prepare" 0 "Fresh Upgrade dihentikan oleh sistem."
        elif [ "$exit_code" -ne 0 ]; then
            write_web_status "failed" "${WEB_UI_CURRENT_STEP:-prepare}" "${WEB_UI_CURRENT_PROGRESS:-0}" "Fresh Upgrade berhenti sebelum selesai. Cek terminal SSH."
        fi
    fi

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

if [ ! -d "$BASE_DIR" ]; then
    echo " Direktori $BASE_DIR tidak ditemukan."
    exit 1
fi

echo "[1️⃣ ] Mendeteksi instalasi WordPress di $BASE_DIR..."
WP_PATHS=()
MULTISITE_PATHS=()

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

install_web_ui "${WP_PATHS[@]}"
write_web_status "running" "download" 10 "Instalasi WordPress ditemukan. Menyiapkan download core terbaru..."

if [ "$LAST_STEP" -lt 1 ]; then
    save_state 1
    LAST_STEP=1
fi

echo
if [ "$LAST_STEP" -lt 2 ]; then
    write_web_status "running" "download" 15 "Mengunduh WordPress versi terbaru..."
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
    write_web_status "running" "core" 28 "Reset permission file dan folder..."
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
    write_web_status "running" "core" 38 "Membersihkan core WordPress lama..."
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
    write_web_status "running" "core" 48 "Mengekstrak dan memasang core WordPress terbaru..."
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
        temporarily_restore_original_htaccess_for_backup "$wp_path"
        if ! tar -zcf "$backup_file"             --exclude="$(basename "$wp_path")/$WEB_UI_HTML_NAME"             --exclude="$(basename "$wp_path")/fresh-upgrade.html"             --exclude="$(basename "$wp_path")/$WEB_UI_STATUS_NAME"             --exclude="$(basename "$wp_path")/$WEB_UI_LOG_NAME"             -C "$(dirname "$wp_path")" "$(basename "$wp_path")"; then
            reactivate_web_ui_htaccess_after_backup "$wp_path"
            echo " Gagal membuat backup, proses dibatalkan."
            exit 1
        fi
        reactivate_web_ui_htaccess_after_backup "$wp_path"

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
    write_web_status "running" "plugin" 64 "Memperbarui plugin dari WordPress.org..."
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
    write_web_status "running" "theme" 78 "Memperbarui theme dari WordPress.org..."
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

rm -rf "$TMP_DIR" 2>/dev/null || true
mkdir -p "$TMP_DIR"

echo
if [ "$LAST_STEP" -lt 8 ]; then
    write_web_status "running" "hardening" 86 "Menampilkan user WordPress. Menunggu input SSH bila diperlukan..."
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
    write_web_status "running" "hardening" 92 "Menunggu keputusan hardening dari SSH..."
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
write_web_status "done" "hardening" 100 "Fresh Upgrade selesai. Membersihkan halaman status..."
sleep "$WEB_UI_AUTO_REMOVE_DELAY"
remove_web_ui
clear_state
echo "✅ Sesi selesai. File state resume dibersihkan untuk run berikutnya."
echo " Semua WordPress telah diperbarui"
echo " Silahkan periksa file malware/backdoor diluar struktur web dan segera hapus!"
