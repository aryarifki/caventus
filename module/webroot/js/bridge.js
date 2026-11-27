// KernelSU WebUI Bridge (window.ksu.exec / window.ksu.spawn) with browser preview mock

const DEFAULT_MODDIR = '/data/adb/modules/caventus_oriole_ram';
const EXEC_TIMEOUT_MS = 30000;
const SPAWN_TIMEOUT_MS = 600000;

let mockState = {
  device: 'oriole',
  android: '17',
  build: 'CP3A.261005.002.A1',
  kernel: '6.1.176-android14-Wild',
  uptime: 'up 1 day, 12:46, load average: 2.10, 2.65, 3.12',
  ram: {
    total_kb: 7783264,
    free_kb: 245120,
    available_kb: 1843200,
    cached_kb: 1624656,
    swap_total_kb: 6291452,
    swap_free_kb: 3191452,
    swap_used_kb: 3100000,
  },
  zram: {
    disksize_bytes: 6442450944,
    active_algo: 'lz77eh',
    avail_algos: 'zstd lz4 lzo-rle lzo [lz77eh]',
    backing_dev: '/dev/block/loop17',
    orig_data_bytes: 2407526400,
    compr_data_bytes: 859830857,
    mem_used_bytes: 880120000,
  },
  vm: {
    swappiness: '70',
    vfs_cache_pressure: '100',
    watermark_scale_factor: '55',
    dirty_background_ratio: '10',
    dirty_ratio: '20',
    page_cluster: '0',
    mglru_enabled: '0x0003',
    mglru_min_ttl_ms: '1000',
  },
  thp: {
    enabled: 'never',
    shmem_enabled: 'never',
  },
  sched: {
    profile: 'stock',
    latency_ns: '8000000',
    adpf_rampup: '4',
    ta_uclamp_min: '1',
    bg_uclamp_max: '512',
  },
  cpufreq: {
    profile: 'stock',
    p0_up_us: '500',
    p0_down_us: '5000',
    p0_resp_ms: '8',
  },
  io: {
    scheduler: 'mq-deadline',
    read_ahead_kb: '256',
    nr_requests: '128',
  },
  gpu: {
    power_policy: 'adaptive',
    governor: 'quickstep',
    dvfs_period_ms: '20',
    min_freq: '151000',
    max_freq: '848000',
  },
  sf: {
    mode: 'off',
    clear_slots: 'stock',
    max_fb_buffers: '',
  },
  lmkd: {
    use_psi: 'true',
    psi_partial_ms: '70',
    psi_complete_ms: '500',
    thrashing_limit: '50',
    swap_free_low_pct: '15',
    swap_util_max: '90',
  },
  art: {
    dex2oat_filter: 'speed-profile',
    image_filter: 'stock',
    madvise_odex_bytes: '67108864',
  },
  recompile_running: false,
  watchdog_running: false,
  config: {
    CONFIG_SCHEMA_VERSION: 2,
    ZRAM_SIZE_MB: 6144,
    ZRAM_ALGO: 'lz77eh',
    MMD_ZRAM_SYNC: 1,
    ZRAM_RUNTIME_RESIZE: 0,
    SWAPOFF_HEADROOM_PCT: 80,
    VM_SWAPPINESS: 70,
    VM_VFS_CACHE_PRESSURE: 100,
    VM_WATERMARK_SCALE_FACTOR: 55,
    VM_DIRTY_BACKGROUND_RATIO: 10,
    VM_DIRTY_RATIO: 20,
    VM_PAGE_CLUSTER: 0,
    VM_STAT_INTERVAL: 10,
    MGLRU_ENABLED: 1,
    MGLRU_MIN_TTL_MS: 1000,
    THP_MODE: 'never',
    SCHED_PROFILE: 'stock',
    CPU_RATE_PROFILE: 'stock',
    IO_SCHEDULER: 'mq-deadline',
    IO_READ_AHEAD_KB: 256,
    IO_NR_REQUESTS: 128,
    GPU_POWER_POLICY: 'adaptive',
    GPU_DVFS_PERIOD_MS: 20,
    SF_TUNING_MODE: 'off',
    WATCHDOG_ENABLED: 0,
    ART_DEX2OAT_FILTER: 'speed-profile',
    ART_MADVISE_MB: 64,
    ART_BOOT_PROPS: 0,
    LMKD_USE_PSI: 'true',
    LMKD_PSI_PARTIAL_MS: 70,
    LMKD_PSI_COMPLETE_MS: 500,
    LMKD_THRASHING_LIMIT: 50,
    LMKD_THRASHING_DECAY: 10,
    LMKD_SWAP_FREE_LOW_PCT: 15,
    LMKD_SWAP_UTIL_MAX: 90,
    LMKD_KILL_HEAVIEST: 'true',
    LMKD_KILL_TIMEOUT_MS: 150,
    LMKD_DOWNGRADE_PRESSURE: 80,
    AUTO_BOOT_DIAG: 1,
    ACTION_MODE: 'both',
    RECOMPILE_SCOPE: 'all',
  },
};

let mockLogs = [
  '[2026-11-28 04:55:02] SKIPPED runtime zram0 swapoff (ZRAM_RUNTIME_RESIZE=0): live=3221225472B/lz77eh vs target=4294967296B/lz77eh',
  '[2026-11-28 04:55:02] VM sysctls applied (swappiness=70, watermark_scale=55, dirty=10/20, mglru=1).',
  '[2026-11-28 04:55:02] LMKD reinitialized (use_psi=true, partial_ms=70, thrash=80, swap_low=10%).',
  '[2026-11-28 04:55:03] Caventus apply finished in 1s.',
];

export function isKsuEnvironment() {
  return typeof window !== 'undefined' && typeof window.ksu?.exec === 'function';
}

export function getModuleDir() {
  return DEFAULT_MODDIR.replace('/modules_update/', '/modules/');
}

export function getCtlPath() {
  return `${getModuleDir()}/bin/caventus-ctl.sh`;
}

export function shellEscape(str) {
  return `'${String(str).replace(/'/g, "'\\''")}'`;
}

function genCbName() {
  return `__cav_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
}

export function exec(command, timeoutMs = EXEC_TIMEOUT_MS) {
  if (!isKsuEnvironment()) {
    return Promise.resolve({ code: 0, stdout: '', stderr: '' });
  }
  return new Promise((resolve, reject) => {
    const cbName = genCbName();
    const timer = setTimeout(() => {
      delete window[cbName];
      reject(new Error('Command timed out'));
    }, timeoutMs);

    window[cbName] = (code, stdout, stderr) => {
      clearTimeout(timer);
      delete window[cbName];
      if (typeof code === 'number') {
        resolve({
          code,
          stdout: typeof stdout === 'string' ? stdout : '',
          stderr: typeof stderr === 'string' ? stderr : '',
        });
      } else if (typeof code === 'string' && code) {
        try {
          const parsed = JSON.parse(code);
          resolve({
            code: typeof parsed.code === 'number' ? parsed.code : parsed.success !== false ? 0 : 1,
            stdout: parsed.stdout || parsed.result || parsed.output || '',
            stderr: parsed.stderr || parsed.error || '',
          });
        } catch {
          resolve({ code: -1, stdout: code, stderr: '' });
        }
      } else {
        resolve({ code: -1, stdout: '', stderr: '' });
      }
    };

    try {
      window.ksu.exec(command, '{}', cbName);
    } catch (err) {
      clearTimeout(timer);
      delete window[cbName];
      reject(err);
    }
  });
}

function createChildEmitter(handlers) {
  const cbs = { stdout: [], stderr: [], exit: [], error: [] };
  if (handlers?.onStdout) cbs.stdout.push(handlers.onStdout);
  if (handlers?.onStderr) cbs.stderr.push(handlers.onStderr);
  if (handlers?.onExit) cbs.exit.push(handlers.onExit);
  if (handlers?.onError) cbs.error.push(handlers.onError);

  return {
    stdout: {
      on(ev, fn) { if (ev === 'data') cbs.stdout.push(fn); },
      emit(ev, data) { if (ev === 'data') cbs.stdout.forEach(fn => fn(data)); },
    },
    stderr: {
      on(ev, fn) { if (ev === 'data') cbs.stderr.push(fn); },
      emit(ev, data) { if (ev === 'data') cbs.stderr.forEach(fn => fn(data)); },
    },
    on(ev, fn) { if (cbs[ev]) cbs[ev].push(fn); },
    emit(ev, ...args) { if (cbs[ev]) cbs[ev].forEach(fn => fn(...args)); },
  };
}

export async function callCtl(args) {
  if (!isKsuEnvironment()) {
    return handleMockCtl(args);
  }
  const cmd = `sh ${shellEscape(getCtlPath())} ${args.map(shellEscape).join(' ')}`;
  return exec(cmd);
}

export function spawnCtl(args, handlers = {}, timeoutMs = SPAWN_TIMEOUT_MS) {
  if (!isKsuEnvironment()) {
    return handleMockSpawn(args, handlers);
  }
  const child = createChildEmitter(handlers);
  const ctlPath = getCtlPath();

  if (typeof window.ksu?.spawn === 'function') {
    const cbName = genCbName();
    window[cbName] = child;
    const cleanup = () => { delete window[cbName]; };
    const timer = setTimeout(() => {
      cleanup();
      child.emit('error', new Error('Process timed out'));
    }, timeoutMs);
    child.on('exit', () => { clearTimeout(timer); cleanup(); });
    child.on('error', () => { clearTimeout(timer); cleanup(); });

    try {
      window.ksu.spawn('sh', JSON.stringify([ctlPath, ...args]), '{}', cbName);
    } catch (err) {
      clearTimeout(timer);
      cleanup();
      setTimeout(() => child.emit('error', err), 0);
    }
    return child;
  }

  const cmd = `sh ${shellEscape(ctlPath)} ${args.map(shellEscape).join(' ')}`;
  exec(cmd, timeoutMs)
    .then(({ code, stdout, stderr }) => {
      if (stdout) stdout.split('\n').forEach(l => l && child.stdout.emit('data', l));
      if (stderr) stderr.split('\n').forEach(l => l && child.stderr.emit('data', l));
      child.emit('exit', typeof code === 'number' ? code : 0);
    })
    .catch(err => child.emit('error', err));

  return child;
}

export function nativeToast(msg) {
  try {
    if (typeof window.ksu?.toast === 'function') {
      window.ksu.toast(String(msg));
    }
  } catch {}
}

function handleMockCtl(args) {
  const cmd = args[0] || 'status-json';
  if (cmd === 'status-json') {
    return Promise.resolve({ code: 0, stdout: JSON.stringify(mockState), stderr: '' });
  }
  if (cmd === 'save-config') {
    args.slice(1).forEach(pair => {
      const idx = pair.indexOf('=');
      if (idx > 0) {
        const k = pair.slice(0, idx);
        const v = pair.slice(idx + 1);
        mockState.config[k] = /^\d+$/.test(v) ? Number(v) : v;
      }
    });
    mockState.art.dex2oat_filter = mockState.config.ART_DEX2OAT_FILTER;
    mockState.art.image_filter = mockState.config.ART_DEX2OAT_FILTER;
    mockState.lmkd.psi_partial_ms = String(mockState.config.LMKD_PSI_PARTIAL_MS);
    mockState.lmkd.thrashing_limit = String(mockState.config.LMKD_THRASHING_LIMIT);
    mockState.lmkd.swap_free_low_pct = String(mockState.config.LMKD_SWAP_FREE_LOW_PCT);
    mockState.thp.enabled = mockState.config.THP_MODE;
    mockState.sched.profile = mockState.config.SCHED_PROFILE;
    mockState.cpufreq.profile = mockState.config.CPU_RATE_PROFILE;
    mockState.cpufreq.p0_resp_ms = mockState.config.CPU_RATE_PROFILE === 'ptune' ? '1' : mockState.config.CPU_RATE_PROFILE === 'stock' ? '8' : '4';
    mockState.io.scheduler = mockState.config.IO_SCHEDULER;
    mockState.io.read_ahead_kb = String(mockState.config.IO_READ_AHEAD_KB);
    mockState.io.nr_requests = String(mockState.config.IO_NR_REQUESTS);
    mockState.gpu.power_policy = mockState.config.GPU_POWER_POLICY;
    mockState.gpu.dvfs_period_ms = String(mockState.config.GPU_DVFS_PERIOD_MS);
    mockState.sf.mode = mockState.config.SF_TUNING_MODE;
    mockState.watchdog_running = Number(mockState.config.WATCHDOG_ENABLED) === 1;
    mockLogs.push(`[preview] Saved config (${args.length - 1} keys)`);
    return Promise.resolve({ code: 0, stdout: 'Saved config (preview)', stderr: '' });
  }
  if (cmd === 'apply') {
    mockState.vm.swappiness = String(mockState.config.VM_SWAPPINESS);
    mockState.vm.watermark_scale_factor = String(mockState.config.VM_WATERMARK_SCALE_FACTOR);
    mockState.watchdog_running = Number(mockState.config.WATCHDOG_ENABLED) === 1;
    mockLogs.push('[preview] Applied VM, GS101 sched, UFS I/O, Mali GPU & LMKD tuning');
    return Promise.resolve({ code: 0, stdout: 'Applied (preview)', stderr: '' });
  }
  if (cmd === 'compact') {
    mockState.ram.available_kb += 98304;
    const msg = 'zRAM compact + lmkd.reinit done (MemAvailable: 1800 MB -> 1896 MB).';
    mockLogs.push(`[preview] ${msg}`);
    return Promise.resolve({ code: 0, stdout: msg, stderr: '' });
  }
  if (cmd === 'reset-defaults') {
    mockLogs.push('[preview] Configuration reset to Pixel 6 (oriole) defaults.');
    return Promise.resolve({ code: 0, stdout: 'Reset complete', stderr: '' });
  }
  if (cmd === 'logs') {
    return Promise.resolve({ code: 0, stdout: mockLogs.join('\n'), stderr: '' });
  }
  if (cmd === 'clear-logs') {
    mockLogs = ['[preview] Logs cleared.'];
    return Promise.resolve({ code: 0, stdout: 'Logs cleared.', stderr: '' });
  }
  if (cmd === 'diag-list') {
    return Promise.resolve({
      code: 0,
      stdout: 'caventus-diag-20261128-045500-manual.log|42KB\nlast-boot.log|3KB',
      stderr: '',
    });
  }
  if (cmd === 'diag-read') {
    return Promise.resolve({
      code: 0,
      stdout: [
        '===== SECTION 01: METADATA, CONFIG & KSU MODULE INVENTORY =====',
        'device=oriole | android=17 | kernel=6.1.176-android14-Wild',
        'SCHED_PROFILE=stock | CPU_RATE_PROFILE=stock | ART_BOOT_PROPS=0 | ZRAM_RUNTIME_RESIZE=0',
        '',
        '===== SECTION 05: PSI (PRESSURE STALL INFORMATION) =====',
        'cpu: some avg10=7.41 avg60=6.82 | io: some avg10=0.60 | mem: some avg10=0.11',
        '',
        '===== SECTION 13: AUTOMATED DIAGNOSTIC SUMMARY =====',
        'THERMAL_THROTTLE_MAX_STATE=0',
        'HIGH_SOC_TEMP=0 (BIG=51.0C, MID=52.0C)',
        'ZRAM_FULL_PCT=78%',
        'ZRAM_MMD_MISMATCH=0',
        'ODREFRESH_HITS=0',
        'LMKD_KILL_HITS=0',
        'SLOW_DISPLAYED_HITS=0',
        'AVC_DENIED_HITS=0',
      ].join('\n'),
      stderr: '',
    });
  }
  if (cmd === 'diag-clear') {
    mockLogs.push('[preview] Diagnostic logs cleared.');
    return Promise.resolve({ code: 0, stdout: 'Diagnostic logs cleared.', stderr: '' });
  }
  return Promise.resolve({ code: 0, stdout: '', stderr: '' });
}

function handleMockSpawn(args, handlers) {
  const child = createChildEmitter(handlers);
  const subcmd = args[0] || '';
  if (subcmd === 'diag-capture') {
    const steps = [
      'STAGE=1/13 Collecting metadata, config & module inventory',
      'STAGE=4/13 Reading Memory, zRAM, VM, MGLRU, THP & vmstat',
      'STAGE=6/13 Reading Thermal Zones & Cooling Throttle State',
      'STAGE=10/13 Live Time-Series Sampling (duration=15s, interval=3s)',
      'SAMPLE=1/5 avail=1820MB swap=2290MB psi=4.10/0.35/0.04 big=51.0C',
      'SAMPLE=3/5 avail=1804MB swap=2305MB psi=5.20/0.40/0.06 big=52.1C',
      'SAMPLE=5/5 avail=1836MB swap=2298MB psi=3.80/0.25/0.03 big=51.4C',
      'STAGE=11/13 Extracting Logcat Forensics (ART, LMKD, mmd, Thermal, SF)',
      'STAGE=13/13 Computing Automated Diagnostic Summary',
      'SAVED_INTERNAL=/data/adb/caventus/diag/caventus-diag-20261128-045500-manual.log',
      'SAVED_EXPORT=/sdcard/Download/Caventus-Logs/caventus-diag-20261128-045500-manual.log',
      'VERDICT=THROTTLE=0 HIGH_TEMP=0 ZRAM=78% MISMATCH=0 ODREFRESH=0 LMKD=0 SLOW_APP=0 AVC=0',
    ];
    let i = 0;
    const iv = setInterval(() => {
      if (i < steps.length) {
        child.stdout.emit('data', steps[i]);
        i += 1;
      } else {
        clearInterval(iv);
        child.emit('exit', 0);
      }
    }, 160);
    return child;
  }
  const samplePkgs = [
    'com.android.systemui',
    'com.google.android.gms',
    'com.google.android.googlequicksearchbox',
    'com.android.chrome',
    'com.whatsapp',
    'com.discord',
    'com.droidspaces.app',
    'com.tailscale.ipn',
  ];
  setTimeout(() => {
    child.stdout.emit('data', `TOTAL=${samplePkgs.length}`);
    let i = 0;
    const iv = setInterval(() => {
      if (i < samplePkgs.length) {
        child.stdout.emit('data', `[${i + 1}/${samplePkgs.length}] ok: ${samplePkgs[i]}`);
        i += 1;
      } else {
        clearInterval(iv);
        child.stdout.emit('data', `[preview] ART recompile finished: ok=${samplePkgs.length} skip=0 elapsed=2s`);
        child.emit('exit', 0);
      }
    }, 180);
  }, 120);
  return child;
}
