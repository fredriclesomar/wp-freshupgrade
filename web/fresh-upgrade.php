<?php
// WP_FRESHUPGRADE_UI_V3_3
declare(strict_types=1);

$statusFile = __DIR__ . '/fresh-upgrade-status.json';

function fresh_upgrade_default_status(): array {
    return [
        'status' => 'running',
        'step' => 'prepare',
        'progress' => 0,
        'message' => 'Menunggu status backend upgrade.sh...',
        'updated_at' => date('Y-m-d H:i:s'),
    ];
}

function fresh_upgrade_read_status(string $statusFile): array {
    if (!is_file($statusFile) || !is_readable($statusFile)) {
        return fresh_upgrade_default_status();
    }

    $raw = (string) file_get_contents($statusFile);
    $data = json_decode($raw, true);

    if (!is_array($data)) {
        return fresh_upgrade_default_status();
    }

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
    ];
}

$status = fresh_upgrade_read_status($statusFile);

if (isset($_GET['fresh_status'])) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
    echo json_encode($status, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
?>
<!doctype html>
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
      <div class="footer">Upgrade otomatis oleh <b>Fredric Lesomar</b> — v3.3</div>
    </section>
  </main>
  <script>
    window.__WP_FRESHUPGRADE_UI_VERSION__ = '3.3';
    window.FRESH_UPGRADE_INITIAL_STATUS = <?php echo json_encode($status, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES); ?>;

    const steps = ['download', 'core', 'plugin', 'theme', 'hardening'];
    const bar = document.getElementById('bar');
    const percent = document.getElementById('percent');
    const message = document.getElementById('message');
    const title = document.getElementById('title');
    const desc = document.getElementById('description');
    const debug = document.getElementById('debug');
    let doneReloadScheduled = false;

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
        title.innerHTML = 'Fresh Upgrade<br>Selesai';
        desc.textContent = 'Pembaruan WordPress telah selesai. Website akan kembali normal otomatis.';
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
        if (debug) debug.textContent = 'Status API error: ' + (e && e.message ? e.message : e);
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