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
    swap_total_kb: 4194300,
    swap_free_kb: 1843200,
    swap_used_kb: 2351100,
  },
  zram: {
    disksize_bytes: 4294967296,
    active_algo: 'zstd',
    avail_algos: '[zstd] lz4 lzo-rle lzo lz77eh',
    backing_dev: '/dev/block/loop5',
    orig_data_bytes: 2407526400,
    compr_data_bytes: 668757333,
    mem_used_bytes: 695120000,
  },
  vm: {
    swappiness: '80',
    vfs_cache_pressure: '100',
    watermark_scale_factor: '60',
    dirty_background_ratio: '5',
    dirty_ratio: '15',
    page_cluster: '0',
    mglru_enabled: '0x0007',
    mglru_min_ttl_ms: '1000',
  },
  thp: {
    enabled: 'never',
    shmem_enabled: 'never',
  },
  sched: {
    profile: 'balanced',
    latency_ns: '4166666',
    adpf_rampup: '2',
    ta_uclamp_min: '1',
    bg_uclamp_max: '512',
  },
  cpufreq: {
    profile: 'responsive',
    p0_up_us: '0',
    p0_down_us: '2000',
    p0_resp_ms: '4',
  },
  io: {
    scheduler: 'mq-deadline',
    read_ahead_kb: '128',
    nr_requests: '256',
  },
  gpu: {
    power_policy: 'adaptive',
    governor: 'quickstep',
    dvfs_period_ms: '20',
    min_freq: '151000',
    max_freq: '848000',
  },
  sf: {
    mode: 'ram_safe',
    clear_slots: 'true',
    max_fb_buffers: '',
  },
  lmkd: {
    use_psi: 'true',
    psi_partial_ms: '50',
    psi_complete_ms: '500',
    thrashing_limit: '60',
    swap_free_low_pct: '20',
    swap_util_max: '85',
  },
  art: {
    dex2oat_filter: 'speed-profile',
    image_filter: 'speed-profile',
    madvise_odex_bytes: '33554432',
  },
  recompile_running: false,
  watchdog_running: false,
  config: {
    ZRAM_SIZE_MB: 4096,
    ZRAM_ALGO: 'zstd',
    MMD_ZRAM_SYNC: 1,
    SWAPOFF_HEADROOM_PCT: 80,
    VM_SWAPPINESS: 80,
    VM_VFS_CACHE_PRESSURE: 100,
    VM_WATERMARK_SCALE_FACTOR: 60,
    VM_DIRTY_BACKGROUND_RATIO: 5,
    VM_DIRTY_RATIO: 15,
    VM_PAGE_CLUSTER: 0,
    VM_STAT_INTERVAL: 10,
    MGLRU_ENABLED: 1,
    MGLRU_MIN_TTL_MS: 1000,
    THP_MODE: 'never',
    SCHED_PROFILE: 'balanced',
    CPU_RATE_PROFILE: 'responsive',
    IO_SCHEDULER: 'mq-deadline',
    IO_READ_AHEAD_KB: 128,
    IO_NR_REQUESTS: 256,
    GPU_POWER_POLICY: 'adaptive',
    GPU_DVFS_PERIOD_MS: 20,
    SF_TUNING_MODE: 'ram_safe',
    WATCHDOG_ENABLED: 0,
    ART_DEX2OAT_FILTER: 'speed-profile',
    ART_MADVISE_MB: 32,
    LMKD_USE_PSI: 'true',
    LMKD_PSI_PARTIAL_MS: 50,
    LMKD_PSI_COMPLETE_MS: 500,
    LMKD_THRASHING_LIMIT: 60,
    LMKD_THRASHING_DECAY: 15,
    LMKD_SWAP_FREE_LOW_PCT: 20,
    LMKD_SWAP_UTIL_MAX: 85,
    LMKD_KILL_HEAVIEST: 'true',
    LMKD_KILL_TIMEOUT_MS: 100,
    LMKD_DOWNGRADE_PRESSURE: 60,
    ACTION_MODE: 'both',
    RECOMPILE_SCOPE: 'all',
  },
};

let mockLogs = [
  '[2026-11-24 22:15:02] zram0 configured: 4096 MB (4294967296B), algo=zstd, backing_dev=/dev/block/loop5',
  '[2026-11-24 22:15:02] VM sysctls applied (swappiness=80, watermark_scale=60, dirty=5/15, mglru=1).',
  '[2026-11-24 22:15:02] LMKD reinitialized (use_psi=true, partial_ms=50, thrash=60, swap_low=20%).',
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
  return Promise.resolve({ code: 0, stdout: '', stderr: '' });
}

function handleMockSpawn(args, handlers) {
  const child = createChildEmitter(handlers);
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
