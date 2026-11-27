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
    tile_sched: 'GS101 Sched / CPU',
    tile_iogpu: 'UFS I/O & Mali GPU',
    quick_actions: 'Aksi Cepat',
    quick_actions_desc: 'Jalankan langsung di perangkat tanpa menunggu reboot.',
    qa_compact_title: 'Compact zRAM + Reinit LMKD',
    qa_compact_sub: 'Padatkan halaman zRAM & segarkan daemon LMKD',
    qa_recomp_title: 'Recompile Aplikasi (speed-profile)',
    qa_recomp_sub: "Paksa turun dari 'everything' ke 'speed-profile' (-f)",
    qa_apply_title: 'Terapkan Tuning Aktif',
    qa_apply_sub: 'Sinkronkan VM, MGLRU, LMKD & zRAM (aman OOM)',
    qa_diag_title: 'Tangkap Log Diagnostik (15s)',
    qa_diag_sub: 'Rekam logcat, dmesg, thermal, PSI & ekspor ke Download',
    btn_run: 'Run',
    btn_execute: 'Execute',
    btn_capture: 'Capture',
    preset_title: 'Profil Optimasi Pixel 6',
    preset_desc: 'Pilih baseline cepat lalu sesuaikan parameter di bawah.',
    zram_desc: 'Ukuran dan kompresor /dev/block/zram0 (writeback-safe).',
    zram_size_label: 'Ukuran zRAM',
    zram_size_sub: 'Pixel 6 (8 GB) optimal di 4096 MB – 5120 MB',
    zram_algo_label: 'Algoritma Kompresi',
    zram_algo_sub: 'lz77eh offload HW GS101 (hemat CPU/baterai); zstd paling padat',
    mmd_sync_title: 'Android 17 mmd zRAM Boot Sync',
    mmd_sync_sub: 'Sinkronkan mmd.zram.size & comp_algorithm sejak early-boot',
    zram_rt_resize_title: 'Izinkan Resize zRAM Runtime (swapoff)',
    zram_rt_resize_sub: 'Matikan untuk mencegah freeze pasca-boot jika ukuran zram0 berbeda',
    art_desc: 'Kontrol kompilasi aplikasi dan ukuran mmap odex/vdex.',
    art_filter_sub: 'speed-profile menghemat RAM mmap dibanding everything',
    art_madvise_sub: 'Batas prefetch mmap file bytecode (default aman 64 MB)',
    art_boot_props_title: 'Override Boot Framework Filter',
    art_boot_props_sub: 'Set dalvik.vm.*dex2oat-filter di system.prop (berisiko memicu odrefresh saat boot)',
    lmkd_desc: 'Tuning PSI agar app cached dibersihkan sebelum zRAM penuh.',
    vm_desc: 'Parameter sysctl memori kernel Linux 6.1 GS101.',
    swappiness_sub: 'Prioritas kompresi halaman anon ke zRAM',
    wm_sub: 'Headroom kswapd sebelum RAM benar-benar sesak',
    thp_sub: 'never paling hemat RAM; madvise seimbang (defrag=defer+madvise)',
    sched_title: 'GS101 Scheduler & CPU',
    sched_desc: 'Tuning vendor_sched uclamp & governor sched_pixel tanpa membuka core background.',
    sched_prof_label: 'Profil vendor_sched',
    sched_prof_sub: 'balanced membuka sf/sys; ptune membuka semua grup uclamp',
    cpu_rate_label: 'Respon sched_pixel CPUFreq',
    cpu_rate_sub: 'Atur up/down_rate_limit_us & response_time_ms tiap cluster',
    iogpu_title: 'UFS Storage I/O & Mali-G78 GPU',
    iogpu_desc: 'Optimasi antrean blok UFS 3.1 (/sys/block/sd*) dan GPU Mali GS101.',
    ra_sub: 'Turunkan dari 512 KB stok untuk menghemat page-cache RAM',
    nr_sub: 'Kedalaman antrean I/O UFS 3.1 (default optimal 128)',
    sf_title: 'SurfaceFlinger & Grafis',
    sf_desc: 'Manajemen slot buffer grafis & sinkronisasi HWC (efek penuh setelah reboot).',
    sf_mode_label: 'Mode SurfaceFlinger',
    sf_mode_sub: 'off paling aman saat boot; ram_safe aktifkan clear_slots; ptune +6 FB & ADPF 1KHz',
    watchdog_title: 'Sysfs Drift Guard (Watchdog)',
    watchdog_desc: 'Penjaga ringan (shell murni, cek tiap 300s) agar sysctl & GPU/IO tidak di-reset sistem.',
    watchdog_toggle: 'Aktifkan Drift Guard (300s)',
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
    diag_title: 'Forensic Diagnostic Capture',
    diag_desc: 'Rekam snapshot lengkap 13 seksi (boot, logcat, dmesg, thermal, PSI, CPUFreq, zRAM) untuk dianalisis & disempurnakan.',
    diag_dur_label: 'Durasi Sampling Live',
    diag_dur_sub: 'Gunakan 30s sambil membuka aplikasi yang terasa lambat',
    diag_boot_title: 'Auto-Capture Setiap Boot',
    diag_boot_sub: 'Simpan laporan otomatis pasca-boot (--tag=boot) ke /sdcard/Download/Caventus-Logs/',
    btn_run_diag: 'Rekam & Ekspor Log Lengkap',
    btn_view_diag: 'Lihat Terakhir',
    btn_clear_diag: 'Bersihkan',
    theme_title: 'Tema Material 3 Expressive',
    theme_desc: 'Palet warna tonal terinspirasi dari Specter.',
    theme_mode_label: 'Mode Tampilan',
    theme_accent_label: 'Warna Aksen',
    theme_accent_sub: '9 palet tonal dinamis',
    lang_label: 'Bahasa / Language',
    module_mgmt: 'Manajemen Modul',
    reset_title: 'Reset ke Default Pixel 6 (oriole)',
    reset_sub: 'Kembalikan profil Oriole Safe & Cool (4 GB lz77eh, sched stock, anti-odrefresh)',
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
    tile_sched: 'GS101 Sched / CPU',
    tile_iogpu: 'UFS I/O & Mali GPU',
    quick_actions: 'Quick Actions',
    quick_actions_desc: 'Run directly on the device without rebooting.',
    qa_compact_title: 'Compact zRAM + Reinit LMKD',
    qa_compact_sub: 'Compact zRAM pages & reload LMKD daemon',
    qa_recomp_title: 'Recompile Apps (speed-profile)',
    qa_recomp_sub: "Force downgrade from 'everything' to 'speed-profile' (-f)",
    qa_apply_title: 'Apply Active Tuning',
    qa_apply_sub: 'Sync VM, MGLRU, LMKD & zRAM (OOM-guarded)',
    qa_diag_title: 'Capture Diagnostic Logs (15s)',
    qa_diag_sub: 'Record logcat, dmesg, thermal, PSI & export to Download',
    btn_run: 'Run',
    btn_execute: 'Execute',
    btn_capture: 'Capture',
    preset_title: 'Pixel 6 Optimization Profiles',
    preset_desc: 'Pick a quick baseline then fine-tune parameters below.',
    zram_desc: 'Size and compressor for /dev/block/zram0 (writeback-safe).',
    zram_size_label: 'zRAM Size',
    zram_size_sub: 'Pixel 6 (8 GB) sweet spot is 4096 MB – 5120 MB',
    zram_algo_label: 'Compression Algorithm',
    zram_algo_sub: 'lz77eh uses GS101 HW offload (lowest CPU/battery); zstd is densest',
    mmd_sync_title: 'Android 17 mmd zRAM Boot Sync',
    mmd_sync_sub: 'Sync mmd.zram.size & comp_algorithm during early boot',
    zram_rt_resize_title: 'Allow Runtime zRAM Resize (swapoff)',
    zram_rt_resize_sub: 'Keep OFF to prevent post-boot freeze if zram0 size differs',
    art_desc: 'Control app compilation filter and odex/vdex mmap limit.',
    art_filter_sub: 'speed-profile saves RAM mmap compared to everything',
    art_madvise_sub: 'Bytecode mmap prefetch limit (safe default 64 MB)',
    art_boot_props_title: 'Override Boot Framework Filter',
    art_boot_props_sub: 'Write dalvik.vm.*dex2oat-filter to system.prop (may trigger odrefresh on boot)',
    lmkd_desc: 'PSI tuning to trim cached apps before zRAM saturates.',
    vm_desc: 'Linux 6.1 GS101 kernel memory sysctl parameters.',
    swappiness_sub: 'Tendency to compress anonymous pages into zRAM',
    wm_sub: 'kswapd headroom before memory pressure stalls UI',
    thp_sub: 'never saves most RAM; madvise is balanced (defrag=defer+madvise)',
    sched_title: 'GS101 Scheduler & CPU',
    sched_desc: 'Tune vendor_sched uclamp & sched_pixel without unlocking background cores.',
    sched_prof_label: 'vendor_sched Profile',
    sched_prof_sub: 'balanced unlocks sf/sys; ptune unlocks all uclamp groups',
    cpu_rate_label: 'sched_pixel CPUFreq Response',
    cpu_rate_sub: 'Configure up/down_rate_limit_us & response_time_ms per cluster',
    iogpu_title: 'UFS Storage I/O & Mali-G78 GPU',
    iogpu_desc: 'Optimize UFS 3.1 block queues (/sys/block/sd*) & GS101 Mali GPU.',
    ra_sub: 'Lower from 512 KB stock to reduce page-cache RAM overhead',
    nr_sub: 'UFS 3.1 I/O queue depth (optimal default 128)',
    sf_title: 'SurfaceFlinger & Display Graphics',
    sf_desc: 'Graphics buffer slot cleanup & HWC sync (full effect after reboot).',
    sf_mode_label: 'SurfaceFlinger Mode',
    sf_mode_sub: 'off is boot-safe default; ram_safe enables clear_slots; ptune +6 FB & 1KHz ADPF',
    watchdog_title: 'Sysfs Drift Guard (Watchdog)',
    watchdog_desc: 'Lightweight pure-shell guard (300s interval) to prevent sysctl/GPU/IO reset.',
    watchdog_toggle: 'Enable Drift Guard (300s)',
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
    diag_title: 'Forensic Diagnostic Capture',
    diag_desc: 'Record 13-section snapshot (boot trace, logcat, dmesg, thermal, PSI, CPUFreq, zRAM) for deep root-cause analysis.',
    diag_dur_label: 'Live Sampling Duration',
    diag_dur_sub: 'Use 30s while launching apps that feel slow',
    diag_boot_title: 'Auto-Capture On Every Boot',
    diag_boot_sub: 'Save automatic post-boot report (--tag=boot) to /sdcard/Download/Caventus-Logs/',
    btn_run_diag: 'Capture & Export Full Logs',
    btn_view_diag: 'View Latest',
    btn_clear_diag: 'Clear Archives',
    theme_title: 'Material 3 Expressive Theme',
    theme_desc: 'Tonal color palettes inspired by Specter.',
    theme_mode_label: 'Appearance Mode',
    theme_accent_label: 'Accent Color',
    theme_accent_sub: '9 dynamic tonal palettes',
    lang_label: 'Bahasa / Language',
    module_mgmt: 'Module Management',
    reset_title: 'Reset to Pixel 6 (oriole) Defaults',
    reset_sub: 'Restore Oriole Safe & Cool defaults (4 GB lz77eh, stock sched, anti-odrefresh)',
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
let selectedDiagDuration = '15';
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
  if (pageId === 'tools') {
    refreshLogs();
    refreshDiagList();
  }
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
  $('tile-mglru').textContent = `mglru: ${data.vm.mglru_enabled} · thp: ${data.thp?.enabled || 'never'}`;

  if ($('tile-sched')) {
    $('tile-sched').textContent = `${data.sched?.profile || 'balanced'} · ${data.cpufreq?.profile || 'responsive'}`;
    $('tile-cpu-resp').textContent = `p0_resp: ${data.cpufreq?.p0_resp_ms || '—'}ms · ramp: ${data.sched?.adpf_rampup || '—'}`;
  }
  if ($('tile-io')) {
    $('tile-io').textContent = `${data.io?.scheduler || 'mq-deadline'} · ${data.io?.read_ahead_kb || '128'}KB`;
    $('tile-gpu').textContent = `mali: ${data.gpu?.power_policy || 'adaptive'} · ${data.gpu?.dvfs_period_ms || '20'}ms`;
  }
  if ($('watchdog-badge')) {
    const wdRun = Boolean(data.watchdog_running);
    $('watchdog-badge').textContent = currentLang === 'id'
      ? `Status: ${wdRun ? 'berjalan (interval 300s)' : 'berhenti'}`
      : `Status: ${wdRun ? 'running (300s interval)' : 'stopped'}`;
  }

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
    ['IO_READ_AHEAD_KB', v => `${v} KB`],
    ['IO_NR_REQUESTS', v => `${v}`],
    ['GPU_DVFS_PERIOD_MS', v => `${v} ms`],
  ];
  sliders.forEach(([key, fmt]) => {
    const input = $(`cfg-${key}`);
    const badge = $(`val-${key}`);
    if (input && draftConfig[key] !== undefined) {
      input.value = draftConfig[key];
      if (badge) badge.textContent = fmt(draftConfig[key]);
    }
  });

  if ($('cfg-MMD_ZRAM_SYNC')) {
    $('cfg-MMD_ZRAM_SYNC').checked = Number(draftConfig.MMD_ZRAM_SYNC) === 1;
  }
  if ($('cfg-ZRAM_RUNTIME_RESIZE')) {
    $('cfg-ZRAM_RUNTIME_RESIZE').checked = Number(draftConfig.ZRAM_RUNTIME_RESIZE) === 1;
  }
  if ($('cfg-ART_BOOT_PROPS')) {
    $('cfg-ART_BOOT_PROPS').checked = Number(draftConfig.ART_BOOT_PROPS) === 1;
  }
  if ($('cfg-AUTO_BOOT_DIAG')) {
    $('cfg-AUTO_BOOT_DIAG').checked = Number(draftConfig.AUTO_BOOT_DIAG) === 1;
  }
  if ($('cfg-LMKD_USE_PSI')) {
    $('cfg-LMKD_USE_PSI').checked = String(draftConfig.LMKD_USE_PSI) === 'true';
  }
  if ($('cfg-MGLRU_ENABLED')) {
    $('cfg-MGLRU_ENABLED').checked = Number(draftConfig.MGLRU_ENABLED) === 1;
  }
  if ($('cfg-WATCHDOG_ENABLED')) {
    $('cfg-WATCHDOG_ENABLED').checked = Number(draftConfig.WATCHDOG_ENABLED) === 1;
  }

  setChipSelection('chips-ZRAM_ALGO', draftConfig.ZRAM_ALGO);
  setChipSelection('chips-THP_MODE', draftConfig.THP_MODE);
  setChipSelection('chips-SCHED_PROFILE', draftConfig.SCHED_PROFILE);
  setChipSelection('chips-CPU_RATE_PROFILE', draftConfig.CPU_RATE_PROFILE);
  setChipSelection('chips-IO_SCHEDULER', draftConfig.IO_SCHEDULER);
  setChipSelection('chips-GPU_POWER_POLICY', draftConfig.GPU_POWER_POLICY);
  setChipSelection('chips-SF_TUNING_MODE', draftConfig.SF_TUNING_MODE);
  setChipSelection('chips-ART_DEX2OAT_FILTER', draftConfig.ART_DEX2OAT_FILTER);
  setChipSelection('chips-RECOMPILE_SCOPE', draftConfig.RECOMPILE_SCOPE);
  setChipSelection('chips-ACTION_MODE', draftConfig.ACTION_MODE);
  setChipSelection('chips-DIAG_DURATION', selectedDiagDuration);
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
  const bootPropChanged =
    String(draftConfig.SF_TUNING_MODE) !== String(savedConfig.SF_TUNING_MODE) ||
    String(draftConfig.MMD_ZRAM_SYNC) !== String(savedConfig.MMD_ZRAM_SYNC) ||
    String(draftConfig.ART_BOOT_PROPS) !== String(savedConfig.ART_BOOT_PROPS);

  await refreshTelemetry();
  if (zramChanged && ((applyRes.stdout || '').includes('DEFERRED') || (applyRes.stdout || '').includes('SKIPPED'))) {
    showSnackbar(
      currentLang === 'id'
        ? 'Disimpan! Reboot disarankan untuk menerapkan zRAM mmd saat boot.'
        : 'Saved! Reboot recommended for boot-time mmd zRAM setup.'
    );
  } else if (bootPropChanged) {
    showSnackbar(
      currentLang === 'id'
        ? 'Disimpan & diterapkan! Reboot disarankan untuk properti boot.'
        : 'Saved & applied! Reboot recommended for boot properties.'
    );
  } else {
    showSnackbar(currentLang === 'id' ? 'Pengaturan disimpan & diterapkan' : 'Settings saved & applied');
  }
}

function runRecompileStream() {
  const modal = $('recompile-modal');
  const titleEl = $('recomp-modal-title');
  const term = $('recomp-terminal');
  const pill = $('recomp-progress-pill');
  const bar = $('recomp-progress-bar');
  const closeBtn = $('btn-close-recomp');

  const filter = draftConfig.ART_DEX2OAT_FILTER || 'speed-profile';
  const scope = draftConfig.RECOMPILE_SCOPE || 'all';
  const useReset = $('opt-recompile-reset')?.checked;

  const args = ['recompile', `--filter=${filter}`, `--scope=${scope}`];
  if (useReset) args.push('--reset');

  titleEl.textContent = `ART Recompile (${filter})`;
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

function runDiagCapture(durationSec = selectedDiagDuration) {
  const modal = $('recompile-modal');
  const titleEl = $('recomp-modal-title');
  const term = $('recomp-terminal');
  const pill = $('recomp-progress-pill');
  const bar = $('recomp-progress-bar');
  const closeBtn = $('btn-close-recomp');

  const dur = String(durationSec || '15');
  const args = ['diag-capture', `--duration=${dur}`, '--interval=3', '--export=1', `--tag=webui_${dur}s`];

  titleEl.textContent = currentLang === 'id' ? `Forensic Diagnostic Capture (${dur}s)` : `Forensic Diagnostic Capture (${dur}s)`;
  term.textContent = `> caventus-ctl.sh ${args.join(' ')}\n`;
  pill.textContent = '0 / 13';
  bar.style.width = '0%';
  closeBtn.disabled = true;
  modal.classList.add('open');

  let exportPath = '';
  const appendLine = line => {
    if (!line) return;
    const st = line.match(/^STAGE=(\d+)\/(\d+)\s*(.*)$/);
    if (st) {
      const cur = Number(st[1]);
      const tot = Number(st[2]);
      pill.textContent = `${cur} / ${tot}`;
      bar.style.width = `${tot > 0 ? Math.round((cur / tot) * 100) : 0}%`;
    }
    if (line.startsWith('SAVED_EXPORT=')) {
      exportPath = line.slice(13).trim();
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
      pill.textContent = '13 / 13';
      showSnackbar(
        exportPath
          ? (currentLang === 'id' ? `Diekspor: ${exportPath}` : `Exported: ${exportPath}`)
          : (currentLang === 'id' ? 'Diagnostik selesai' : 'Diagnostic capture completed')
      );
      refreshDiagList();
    } else {
      showSnackbar(`Diagnostic exited with code ${code}`);
    }
  });
  child.on('error', err => {
    closeBtn.disabled = false;
    appendLine(`[ERROR] ${err.message}`);
  });
}

async function viewLastDiag() {
  const modal = $('recompile-modal');
  const titleEl = $('recomp-modal-title');
  const term = $('recomp-terminal');
  const pill = $('recomp-progress-pill');
  const bar = $('recomp-progress-bar');
  const closeBtn = $('btn-close-recomp');

  titleEl.textContent = currentLang === 'id' ? 'Laporan Diagnostik Terakhir' : 'Latest Diagnostic Report';
  pill.textContent = 'tail 250';
  bar.style.width = '100%';
  closeBtn.disabled = false;
  term.textContent = 'Loading...';
  modal.classList.add('open');

  const res = await callCtl(['diag-read', '--tail=250']);
  term.textContent = res.stdout || res.stderr || 'No diagnostic logs yet.';
  term.scrollTop = term.scrollHeight;
}

async function refreshDiagList() {
  const el = $('diag-list-terminal');
  if (!el) return;
  const res = await callCtl(['diag-list']);
  const txt = (res.stdout || '').trim();
  if (!txt || txt === 'NONE|0KB') {
    el.textContent = currentLang === 'id'
      ? 'Belum ada arsip diagnostik.\nEkspor akan tersimpan di /sdcard/Download/Caventus-Logs/'
      : 'No diagnostic archives yet.\nExports will save to /sdcard/Download/Caventus-Logs/';
  } else {
    el.textContent = txt.split('\n').map(l => `• ${l.replace('|', ' — ')}`).join('\n');
  }
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
  $('qa-diag')?.addEventListener('click', () => runDiagCapture('15'));

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
    IO_READ_AHEAD_KB: v => `${v} KB`,
    IO_NR_REQUESTS: v => `${v}`,
    GPU_DVFS_PERIOD_MS: v => `${v} ms`,
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
  $('cfg-MMD_ZRAM_SYNC')?.addEventListener('change', e => {
    draftConfig.MMD_ZRAM_SYNC = e.target.checked ? 1 : 0;
    updateSaveDock();
  });
  $('cfg-ZRAM_RUNTIME_RESIZE')?.addEventListener('change', e => {
    draftConfig.ZRAM_RUNTIME_RESIZE = e.target.checked ? 1 : 0;
    updateSaveDock();
  });
  $('cfg-ART_BOOT_PROPS')?.addEventListener('change', e => {
    draftConfig.ART_BOOT_PROPS = e.target.checked ? 1 : 0;
    updateSaveDock();
  });
  $('cfg-AUTO_BOOT_DIAG')?.addEventListener('change', e => {
    draftConfig.AUTO_BOOT_DIAG = e.target.checked ? 1 : 0;
    updateSaveDock();
  });
  $('cfg-LMKD_USE_PSI')?.addEventListener('change', e => {
    draftConfig.LMKD_USE_PSI = e.target.checked ? 'true' : 'false';
    updateSaveDock();
  });
  $('cfg-MGLRU_ENABLED')?.addEventListener('change', e => {
    draftConfig.MGLRU_ENABLED = e.target.checked ? 1 : 0;
    updateSaveDock();
  });
  $('cfg-WATCHDOG_ENABLED')?.addEventListener('change', e => {
    draftConfig.WATCHDOG_ENABLED = e.target.checked ? 1 : 0;
    updateSaveDock();
  });

  // Chip groups bound to config keys
  [
    'ZRAM_ALGO',
    'THP_MODE',
    'SCHED_PROFILE',
    'CPU_RATE_PROFILE',
    'IO_SCHEDULER',
    'GPU_POWER_POLICY',
    'SF_TUNING_MODE',
    'ART_DEX2OAT_FILTER',
    'RECOMPILE_SCOPE',
    'ACTION_MODE',
  ].forEach(key => {
    document.querySelectorAll(`#chips-${key} .m3-chip`).forEach(btn => {
      btn.addEventListener('click', () => {
        draftConfig[key] = btn.dataset.val;
        setChipSelection(`chips-${key}`, btn.dataset.val);
        updateSaveDock();
      });
    });
  });

  document.querySelectorAll('#chips-DIAG_DURATION .m3-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      selectedDiagDuration = btn.dataset.val;
      setChipSelection('chips-DIAG_DURATION', selectedDiagDuration);
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
  $('btn-run-diag')?.addEventListener('click', () => runDiagCapture(selectedDiagDuration));
  $('btn-view-diag')?.addEventListener('click', viewLastDiag);
  $('btn-clear-diag')?.addEventListener('click', async () => {
    await callCtl(['diag-clear']);
    refreshDiagList();
    showSnackbar(currentLang === 'id' ? 'Arsip diagnostik dibersihkan' : 'Diagnostic archives cleared');
  });
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
