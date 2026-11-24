import { ACCENT_SWATCHES, TUNING_PRESETS } from './presets.js';
import { applyTheme, getThemeState, initTheme } from './theme.js';
import { callCtl, isKsuEnvironment, nativeToast, spawnCtl } from './bridge.js';

const I18N = {
  id: {
    hero_eyebrow: 'MEMORI PERANGKAT',
    ram_pressure: 'Pemakaian RAM Fisik',
    zram_usage: 'Swap zRAM Terpakai',
    tile_ratio: 'Rasio Kompresi zRAM',
    tile_art: 'ART dex2oat Filter',
    tile_lmkd: 'LMKD PSI / Thrash',
    tile_vm: 'VM Swappiness / MGLRU',
    quick_actions: 'Aksi Cepat',
    quick_actions_desc: 'Jalankan langsung di perangkat tanpa menunggu reboot.',
    qa_compact_title: 'Compact zRAM + Reinit LMKD',
    qa_compact_sub: 'Padatkan halaman zRAM & segarkan daemon LMKD',
    qa_recomp_title: 'Recompile Aplikasi (speed-profile)',
    qa_recomp_sub: "Paksa turun dari 'everything' ke 'speed-profile' (-f)",
    qa_apply_title: 'Terapkan Tuning Aktif',
    qa_apply_sub: 'Sinkronkan VM, MGLRU, LMKD & zRAM (aman OOM)',
    btn_run: 'Run',
    btn_execute: 'Execute',
    preset_title: 'Profil Optimasi Pixel 6',
    preset_desc: 'Pilih baseline cepat lalu sesuaikan parameter di bawah.',
    zram_desc: 'Ukuran dan kompresor /dev/block/zram0 (writeback-safe).',
    zram_size_label: 'Ukuran zRAM',
    zram_size_sub: 'Pixel 6 (8 GB) optimal di 4096 MB – 5120 MB',
    zram_algo_label: 'Algoritma Kompresi',
    zram_algo_sub: 'zstd paling padat; lz4/lz77eh paling ringan CPU',
    art_desc: 'Kontrol kompilasi aplikasi dan ukuran mmap odex/vdex.',
    art_filter_sub: 'speed-profile menghemat RAM mmap dibanding everything',
    art_madvise_sub: 'Batas prefetch mmap file bytecode (default stok 100 MB)',
    lmkd_desc: 'Tuning PSI agar app cached dibersihkan sebelum zRAM penuh.',
    vm_desc: 'Parameter sysctl memori kernel Linux 6.1 GS101.',
    swappiness_sub: 'Prioritas kompresi halaman anon ke zRAM',
    wm_sub: 'Headroom kswapd sebelum RAM benar-benar sesak',
    recomp_studio: 'ART Recompile Studio',
    recomp_studio_desc: "Paksa aplikasi yang terlanjur dikompilasi 'everything' agar beralih ke 'speed-profile' (-f) dengan progres live.",
    recomp_scope_title: 'Cakupan Paket',
    recomp_scope_sub: 'Semua paket atau aplikasi pengguna saja (-3)',
    scope_all: 'Semua Paket',
    scope_user: 'Aplikasi User (-3)',
    recomp_reset_title: 'Reset ART Sebelum Compile (--reset)',
    recomp_reset_sub: 'Hapus sisa .odex/.art lama lebih agresif sebelum -m speed-profile -f',
    btn_run_recompile: 'Jalankan Recompile Sekarang',
    action_mode_title: 'Tombol Run / Action di KernelSU Manager',
    action_mode_desc: 'Atur apa yang dijalankan saat menekan tombol Action (Run/Execute) pada kartu modul Caventus di KernelSU.',
    logs_title: 'Log Runtime Caventus',
    btn_refresh_logs: 'Muat Ulang Log',
    btn_clear_logs: 'Hapus Log',
    theme_title: 'Tema Material 3 Expressive',
    theme_desc: 'Palet warna tonal terinspirasi dari Specter.',
    theme_mode_label: 'Mode Tampilan',
    theme_accent_label: 'Warna Aksen',
    theme_accent_sub: '9 palet tonal dinamis',
    lang_label: 'Bahasa / Language',
    module_mgmt: 'Manajemen Modul',
    reset_title: 'Reset ke Default Pixel 6 (oriole)',
    reset_sub: 'Kembalikan zRAM 4 GB zstd, speed-profile & PSI LMKD standar',
    unsaved_changes: 'Perubahan belum disimpan',
    btn_discard: 'Batal',
    btn_save_apply: 'Simpan & Terapkan',
    nav_home: 'Home',
    nav_tuning: 'Tuning',
    nav_tools: 'Tools',
    nav_settings: 'Settings',
    btn_copy: 'Salin Output',
    btn_close: 'Tutup',
  },
  en: {
    hero_eyebrow: 'DEVICE MEMORY',
    ram_pressure: 'Physical RAM Used',
    zram_usage: 'zRAM Swap Used',
    tile_ratio: 'zRAM Compression Ratio',
    tile_art: 'ART dex2oat Filter',
    tile_lmkd: 'LMKD PSI / Thrash',
    tile_vm: 'VM Swappiness / MGLRU',
    quick_actions: 'Quick Actions',
    quick_actions_desc: 'Run directly on the device without rebooting.',
    qa_compact_title: 'Compact zRAM + Reinit LMKD',
    qa_compact_sub: 'Compact zRAM pages & reload LMKD daemon',
    qa_recomp_title: 'Recompile Apps (speed-profile)',
    qa_recomp_sub: "Force downgrade from 'everything' to 'speed-profile' (-f)",
    qa_apply_title: 'Apply Active Tuning',
    qa_apply_sub: 'Sync VM, MGLRU, LMKD & zRAM (OOM-guarded)',
    btn_run: 'Run',
    btn_execute: 'Execute',
    preset_title: 'Pixel 6 Optimization Profiles',
    preset_desc: 'Pick a quick baseline then fine-tune parameters below.',
    zram_desc: 'Size and compressor for /dev/block/zram0 (writeback-safe).',
    zram_size_label: 'zRAM Size',
    zram_size_sub: 'Pixel 6 (8 GB) sweet spot is 4096 MB – 5120 MB',
    zram_algo_label: 'Compression Algorithm',
    zram_algo_sub: 'zstd gives highest density; lz4/lz77eh uses least CPU',
    art_desc: 'Control app compilation filter and odex/vdex mmap limit.',
    art_filter_sub: 'speed-profile saves RAM mmap compared to everything',
    art_madvise_sub: 'Bytecode mmap prefetch limit (stock default 100 MB)',
    lmkd_desc: 'PSI tuning to trim cached apps before zRAM saturates.',
    vm_desc: 'Linux 6.1 GS101 kernel memory sysctl parameters.',
    swappiness_sub: 'Tendency to compress anonymous pages into zRAM',
    wm_sub: 'kswapd headroom before memory pressure stalls UI',
    recomp_studio: 'ART Recompile Studio',
    recomp_studio_desc: "Force apps previously compiled with 'everything' down to 'speed-profile' (-f) with live progress.",
    recomp_scope_title: 'Package Scope',
    recomp_scope_sub: 'All packages or third-party user apps only (-3)',
    scope_all: 'All Packages',
    scope_user: 'User Apps (-3)',
    recomp_reset_title: 'Reset ART Before Compile (--reset)',
    recomp_reset_sub: 'Clear old .odex/.art artifacts before -m speed-profile -f',
    btn_run_recompile: 'Run Recompile Now',
    action_mode_title: 'KernelSU Manager Run / Action Button',
    action_mode_desc: 'Choose what runs when tapping Action (Run/Execute) on Caventus in KernelSU Manager.',
    logs_title: 'Caventus Runtime Logs',
    btn_refresh_logs: 'Refresh Logs',
    btn_clear_logs: 'Clear Logs',
    theme_title: 'Material 3 Expressive Theme',
    theme_desc: 'Tonal color palettes inspired by Specter.',
    theme_mode_label: 'Appearance Mode',
    theme_accent_label: 'Accent Color',
    theme_accent_sub: '9 dynamic tonal palettes',
    lang_label: 'Bahasa / Language',
    module_mgmt: 'Module Management',
    reset_title: 'Reset to Pixel 6 (oriole) Defaults',
    reset_sub: 'Restore 4 GB zstd zRAM, speed-profile & PSI LMKD defaults',
    unsaved_changes: 'Unsaved changes',
    btn_discard: 'Discard',
    btn_save_apply: 'Save & Apply',
    nav_home: 'Home',
    nav_tuning: 'Tuning',
    nav_tools: 'Tools',
    nav_settings: 'Settings',
    btn_copy: 'Copy Output',
    btn_close: 'Close',
  },
};

let currentLang = localStorage.getItem('caventus_lang') || 'id';
let liveState = null;
let savedConfig = {};
let draftConfig = {};
let snackTimer = null;

function $(id) {
  return document.getElementById(id);
}

function showSnackbar(msg) {
  const el = $('snackbar');
  el.textContent = msg;
  el.classList.add('visible');
  clearTimeout(snackTimer);
  snackTimer = setTimeout(() => el.classList.remove('visible'), 3200);
  nativeToast(msg);
}

function applyLanguage(lang) {
  currentLang = I18N[lang] ? lang : 'id';
  localStorage.setItem('caventus_lang', currentLang);
  const dict = I18N[currentLang];
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (dict[key]) el.textContent = dict[key];
  });
  document.querySelectorAll('#lang-chips .m3-chip').forEach(btn => {
    btn.classList.toggle('selected', btn.dataset.lang === currentLang);
  });
}

function updateNavIndicator() {
  const activeTab = document.querySelector('.nav-tab--active');
  const indicator = $('nav-indicator');
  if (!activeTab || !indicator) return;
  indicator.style.left = `${activeTab.offsetLeft}px`;
  indicator.style.width = `${activeTab.offsetWidth}px`;
}

function switchPage(pageId) {
  document.querySelectorAll('.page').forEach(p => {
    p.classList.toggle('active', p.id === `page-${pageId}`);
  });
  document.querySelectorAll('.nav-tab').forEach(t => {
    t.classList.toggle('nav-tab--active', t.dataset.page === pageId);
  });
  requestAnimationFrame(updateNavIndicator);
  if (pageId === 'tools') refreshLogs();
}

function renderTelemetry(data) {
  liveState = data;
  const pill = $('device-pill');
  if (!isKsuEnvironment()) {
    pill.textContent = `${data.device} · Preview`;
    pill.classList.add('device-pill--preview');
  } else {
    pill.textContent = `${data.device} · A${data.android}`;
    pill.classList.remove('device-pill--preview');
  }

  const totalMb = Math.round((data.ram.total_kb || 0) / 1024);
  const availMb = Math.round((data.ram.available_kb || 0) / 1024);
  const usedMb = Math.max(0, totalMb - availMb);
  const ramPct = totalMb > 0 ? Math.min(100, Math.round((usedMb / totalMb) * 100)) : 0;

  $('hero-avail').innerHTML = `${availMb} MB <span style="font-size:0.9rem;font-weight:500;opacity:0.8">Avail</span>`;
  $('hero-sub').textContent = `MemTotal ${totalMb} MB · Kernel ${data.kernel}`;
  $('ram-meter-text').textContent = `${usedMb} / ${totalMb} MB (${ramPct}%)`;
  $('ram-meter-fill').style.width = `${ramPct}%`;

  const zTotalMb = Math.round((data.zram.disksize_bytes || 0) / 1048576);
  const zUsedMb = Math.round((data.ram.swap_used_kb || 0) / 1024);
  const zPct = zTotalMb > 0 ? Math.min(100, Math.round((zUsedMb / zTotalMb) * 100)) : 0;
  $('zram-meter-text').textContent = `${zUsedMb} / ${zTotalMb} MB (${zPct}%)`;
  $('zram-meter-fill').style.width = `${zPct}%`;

  const activeAlgo = data.zram.active_algo || '—';
  const chip = $('hero-status-chip');
  chip.textContent = `${activeAlgo} · ${Math.round(zTotalMb / 1024 * 10) / 10} GB`;
  chip.classList.toggle('status-chip--warn', zPct > 85);

  const orig = Number(data.zram.orig_data_bytes || 0);
  const compr = Number(data.zram.compr_data_bytes || 0);
  const ratio = compr > 0 ? `${(orig / compr).toFixed(2)}x` : '—';
  $('tile-ratio').textContent = ratio;
  $('tile-algo').textContent = `algo: ${activeAlgo}`;

  $('tile-art').textContent = data.art.dex2oat_filter || '—';
  const madvMb = Math.round(Number(data.art.madvise_odex_bytes || 0) / 1048576);
  $('tile-madvise').textContent = `madvise: ${madvMb} MB`;

  $('tile-lmkd').textContent = `${data.lmkd.psi_partial_ms}ms / ${data.lmkd.thrashing_limit}`;
  $('tile-swaplow').textContent = `swap_low: ${data.lmkd.swap_free_low_pct}%`;

  $('tile-vm').textContent = `swap ${data.vm.swappiness} · wm ${data.vm.watermark_scale_factor}`;
  $('tile-mglru').textContent = `mglru: ${data.vm.mglru_enabled}`;

  savedConfig = { ...data.config };
  draftConfig = { ...data.config };
  syncControlsFromDraft();
  updateSaveDock();
}

function setChipSelection(groupId, val) {
  document.querySelectorAll(`#${groupId} .m3-chip`).forEach(btn => {
    btn.classList.toggle('selected', btn.dataset.val === String(val));
  });
}

function syncControlsFromDraft() {
  const sliders = [
    ['ZRAM_SIZE_MB', v => `${v} MB`],
    ['ART_MADVISE_MB', v => `${v} MB`],
    ['LMKD_PSI_PARTIAL_MS', v => `${v} ms`],
    ['LMKD_THRASHING_LIMIT', v => `${v}`],
    ['LMKD_SWAP_FREE_LOW_PCT', v => `${v}%`],
    ['VM_SWAPPINESS', v => `${v}`],
    ['VM_WATERMARK_SCALE_FACTOR', v => `${v}`],
    ['VM_VFS_CACHE_PRESSURE', v => `${v}`],
  ];
  sliders.forEach(([key, fmt]) => {
    const input = $(`cfg-${key}`);
    const badge = $(`val-${key}`);
    if (input && draftConfig[key] !== undefined) {
      input.value = draftConfig[key];
      if (badge) badge.textContent = fmt(draftConfig[key]);
    }
  });

  if ($('cfg-LMKD_USE_PSI')) {
    $('cfg-LMKD_USE_PSI').checked = String(draftConfig.LMKD_USE_PSI) === 'true';
  }
  if ($('cfg-MGLRU_ENABLED')) {
    $('cfg-MGLRU_ENABLED').checked = Number(draftConfig.MGLRU_ENABLED) === 1;
  }

  setChipSelection('chips-ZRAM_ALGO', draftConfig.ZRAM_ALGO);
  setChipSelection('chips-ART_DEX2OAT_FILTER', draftConfig.ART_DEX2OAT_FILTER);
  setChipSelection('chips-RECOMPILE_SCOPE', draftConfig.RECOMPILE_SCOPE);
  setChipSelection('chips-ACTION_MODE', draftConfig.ACTION_MODE);
}

function getChangedPairs() {
  const pairs = [];
  Object.keys(draftConfig).forEach(k => {
    if (String(draftConfig[k]) !== String(savedConfig[k])) {
      pairs.push(`${k}=${draftConfig[k]}`);
    }
  });
  return pairs;
}

function updateSaveDock() {
  const changed = getChangedPairs();
  const dock = $('save-dock');
  dock.classList.toggle('visible', changed.length > 0);
  if (changed.length > 0) {
    $('save-dock-text').textContent =
      currentLang === 'id' ? `${changed.length} perubahan belum disimpan` : `${changed.length} unsaved changes`;
  }
}

async function refreshTelemetry() {
  const btn = $('btn-refresh');
  btn.classList.add('spinning');
  try {
    const res = await callCtl(['status-json']);
    if (res.code === 0 && res.stdout) {
      renderTelemetry(JSON.parse(res.stdout.trim()));
    } else {
      showSnackbar(res.stderr || 'Failed to read status');
    }
  } catch (err) {
    showSnackbar(`Status error: ${err.message}`);
  } finally {
    btn.classList.remove('spinning');
  }
}

async function saveAndApplyConfig() {
  const pairs = getChangedPairs();
  if (!pairs.length) return;
  const saveRes = await callCtl(['save-config', ...pairs]);
  if (saveRes.code !== 0) {
    showSnackbar(saveRes.stderr || 'Save failed');
    return;
  }
  const applyRes = await callCtl(['apply']);
  const zramChanged =
    String(draftConfig.ZRAM_SIZE_MB) !== String(savedConfig.ZRAM_SIZE_MB) ||
    String(draftConfig.ZRAM_ALGO) !== String(savedConfig.ZRAM_ALGO);

  await refreshTelemetry();
  if (zramChanged && (applyRes.stdout || '').includes('DEFERRED')) {
    showSnackbar(
      currentLang === 'id'
        ? 'Disimpan! Reboot diperlukan untuk resize zRAM secara aman.'
        : 'Saved! Reboot required to resize zRAM safely.'
    );
  } else {
    showSnackbar(currentLang === 'id' ? 'Pengaturan disimpan & diterapkan' : 'Settings saved & applied');
  }
}

function runRecompileStream() {
  const modal = $('recompile-modal');
  const term = $('recomp-terminal');
  const pill = $('recomp-progress-pill');
  const bar = $('recomp-progress-bar');
  const closeBtn = $('btn-close-recomp');

  const filter = draftConfig.ART_DEX2OAT_FILTER || 'speed-profile';
  const scope = draftConfig.RECOMPILE_SCOPE || 'all';
  const useReset = $('opt-recompile-reset')?.checked;

  const args = ['recompile', `--filter=${filter}`, `--scope=${scope}`];
  if (useReset) args.push('--reset');

  term.textContent = `> caventus-ctl.sh ${args.join(' ')}\n`;
  pill.textContent = '0 / ?';
  bar.style.width = '0%';
  closeBtn.disabled = true;
  modal.classList.add('open');

  let total = 0;
  const appendLine = line => {
    if (!line) return;
    if (line.startsWith('TOTAL=')) {
      total = Number(line.slice(6)) || 0;
      pill.textContent = `0 / ${total}`;
      return;
    }
    const m = line.match(/^\[(\d+)\/(\d+)\]/);
    if (m) {
      const cur = Number(m[1]);
      const tot = Number(m[2]);
      pill.textContent = `${cur} / ${tot}`;
      bar.style.width = `${tot > 0 ? Math.round((cur / tot) * 100) : 0}%`;
    }
    term.textContent += `${line}\n`;
    term.scrollTop = term.scrollHeight;
  };

  const child = spawnCtl(args);
  child.stdout.on('data', appendLine);
  child.stderr.on('data', errLine => appendLine(`[ERR] ${errLine}`));
  child.on('exit', code => {
    closeBtn.disabled = false;
    if (code === 0) {
      bar.style.width = '100%';
      showSnackbar(currentLang === 'id' ? 'ART recompile selesai' : 'ART recompile completed');
    } else {
      showSnackbar(`Recompile exited with code ${code}`);
    }
    refreshTelemetry();
  });
  child.on('error', err => {
    closeBtn.disabled = false;
    appendLine(`[ERROR] ${err.message}`);
  });
}

async function refreshLogs() {
  const res = await callCtl(['logs', '120']);
  $('log-terminal').textContent = res.stdout || res.stderr || 'No logs yet.';
}

function wireControls() {
  // Top bar scroll elevation
  window.addEventListener('scroll', () => {
    $('top-bar').classList.toggle('app-top-bar--scrolled', window.scrollY > 8);
  }, { passive: true });

  // Bottom nav tabs
  document.querySelectorAll('.nav-tab').forEach(tab => {
    tab.addEventListener('click', () => switchPage(tab.dataset.page));
  });
  window.addEventListener('resize', updateNavIndicator);

  // Refresh
  $('btn-refresh').addEventListener('click', refreshTelemetry);

  // Quick Actions
  $('qa-compact').addEventListener('click', async () => {
    const res = await callCtl(['compact']);
    showSnackbar(res.stdout.trim() || 'Compact complete');
    refreshTelemetry();
  });
  $('qa-recompile').addEventListener('click', runRecompileStream);
  $('qa-apply').addEventListener('click', async () => {
    await callCtl(['apply']);
    showSnackbar(currentLang === 'id' ? 'Tuning diterapkan' : 'Tuning applied');
    refreshTelemetry();
  });

  // Tuning Presets
  document.querySelectorAll('#preset-chips .m3-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      const preset = TUNING_PRESETS[btn.dataset.preset];
      if (!preset) return;
      document.querySelectorAll('#preset-chips .m3-chip').forEach(b => b.classList.remove('selected'));
      btn.classList.add('selected');
      Object.assign(draftConfig, preset);
      syncControlsFromDraft();
      updateSaveDock();
    });
  });

  // Range sliders
  const sliderFormats = {
    ZRAM_SIZE_MB: v => `${v} MB`,
    ART_MADVISE_MB: v => `${v} MB`,
    LMKD_PSI_PARTIAL_MS: v => `${v} ms`,
    LMKD_THRASHING_LIMIT: v => `${v}`,
    LMKD_SWAP_FREE_LOW_PCT: v => `${v}%`,
    VM_SWAPPINESS: v => `${v}`,
    VM_WATERMARK_SCALE_FACTOR: v => `${v}`,
    VM_VFS_CACHE_PRESSURE: v => `${v}`,
  };
  Object.entries(sliderFormats).forEach(([key, fmt]) => {
    const input = $(`cfg-${key}`);
    if (!input) return;
    input.addEventListener('input', () => {
      draftConfig[key] = Number(input.value);
      $(`val-${key}`).textContent = fmt(input.value);
      updateSaveDock();
    });
  });

  // Switches
  $('cfg-LMKD_USE_PSI')?.addEventListener('change', e => {
    draftConfig.LMKD_USE_PSI = e.target.checked ? 'true' : 'false';
    updateSaveDock();
  });
  $('cfg-MGLRU_ENABLED')?.addEventListener('change', e => {
    draftConfig.MGLRU_ENABLED = e.target.checked ? 1 : 0;
    updateSaveDock();
  });

  // Chip groups bound to config keys
  ['ZRAM_ALGO', 'ART_DEX2OAT_FILTER', 'RECOMPILE_SCOPE', 'ACTION_MODE'].forEach(key => {
    document.querySelectorAll(`#chips-${key} .m3-chip`).forEach(btn => {
      btn.addEventListener('click', () => {
        draftConfig[key] = btn.dataset.val;
        setChipSelection(`chips-${key}`, btn.dataset.val);
        updateSaveDock();
      });
    });
  });

  // Save Dock
  $('btn-discard').addEventListener('click', () => {
    draftConfig = { ...savedConfig };
    syncControlsFromDraft();
    updateSaveDock();
  });
  $('btn-save-apply').addEventListener('click', saveAndApplyConfig);

  // Tools
  $('btn-run-recompile').addEventListener('click', runRecompileStream);
  $('btn-refresh-logs').addEventListener('click', refreshLogs);
  $('btn-clear-logs').addEventListener('click', async () => {
    await callCtl(['clear-logs']);
    refreshLogs();
    showSnackbar(currentLang === 'id' ? 'Log dibersihkan' : 'Logs cleared');
  });

  // Recompile Modal buttons
  $('btn-close-recomp').addEventListener('click', () => $('recompile-modal').classList.remove('open'));
  $('btn-copy-recomp').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText($('recomp-terminal').textContent);
      showSnackbar(currentLang === 'id' ? 'Output disalin' : 'Output copied');
    } catch {
      showSnackbar('Clipboard unavailable');
    }
  });

  // Theme mode & accents
  const syncThemeUi = () => {
    const st = getThemeState();
    document.querySelectorAll('#theme-mode-chips .m3-chip').forEach(b => {
      b.classList.toggle('selected', b.dataset.mode === st.mode);
    });
    document.querySelectorAll('#accent-swatches .swatch-btn').forEach(b => {
      b.classList.toggle('selected', b.dataset.accent === st.accent);
    });
  };

  const swGrid = $('accent-swatches');
  Object.entries(ACCENT_SWATCHES).forEach(([name, hex]) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'swatch-btn';
    b.dataset.accent = name;
    b.style.background = hex;
    b.title = name;
    b.addEventListener('click', () => {
      applyTheme(getThemeState().mode, name);
      syncThemeUi();
    });
    swGrid.appendChild(b);
  });

  document.querySelectorAll('#theme-mode-chips .m3-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      applyTheme(btn.dataset.mode, getThemeState().accent);
      syncThemeUi();
    });
  });
  syncThemeUi();

  // Language
  document.querySelectorAll('#lang-chips .m3-chip').forEach(btn => {
    btn.addEventListener('click', () => applyLanguage(btn.dataset.lang));
  });

  // Reset defaults
  $('btn-reset-defaults').addEventListener('click', async () => {
    await callCtl(['reset-defaults']);
    await refreshTelemetry();
    showSnackbar(currentLang === 'id' ? 'Konfigurasi direset ke default' : 'Reset to defaults');
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  initTheme();
  applyLanguage(currentLang);
  wireControls();
  requestAnimationFrame(updateNavIndicator);
  await refreshTelemetry();
});
