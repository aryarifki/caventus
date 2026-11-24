import { AMOLED_OVERRIDES, COLOR_KEYS, PALETTES } from './presets.js';

const KEY_MODE = 'caventus_theme_mode';
const KEY_ACCENT = 'caventus_theme_accent';

let currentMode = localStorage.getItem(KEY_MODE) || 'dark';
let currentAccent = localStorage.getItem(KEY_ACCENT) || 'blue';
if (!PALETTES[`${currentAccent}_dark`]) currentAccent = 'blue';

function resolveThemeMode(mode) {
  if (mode === 'amoled') return 'dark';
  if (mode === 'auto') {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
      ? 'dark'
      : 'light';
  }
  return mode === 'light' ? 'light' : 'dark';
}

export function applyTheme(mode = currentMode, accent = currentAccent) {
  currentMode = mode;
  currentAccent = PALETTES[`${accent}_dark`] ? accent : 'blue';

  localStorage.setItem(KEY_MODE, currentMode);
  localStorage.setItem(KEY_ACCENT, currentAccent);

  const resolved = resolveThemeMode(currentMode);
  const palette = PALETTES[`${currentAccent}_${resolved}`] || PALETTES.blue_dark;
  const root = document.documentElement;

  COLOR_KEYS.forEach((key, idx) => {
    root.style.setProperty(key, palette[idx]);
  });

  if (currentMode === 'amoled') {
    Object.entries(AMOLED_OVERRIDES).forEach(([k, v]) => root.style.setProperty(k, v));
  }

  root.setAttribute('data-theme-resolved', resolved);
  root.setAttribute('data-theme-mode', currentMode);
  root.setAttribute('data-theme-accent', currentAccent);

  return { mode: currentMode, resolved, accent: currentAccent };
}

export function getThemeState() {
  return { mode: currentMode, resolved: resolveThemeMode(currentMode), accent: currentAccent };
}

export function initTheme() {
  applyTheme(currentMode, currentAccent);
  if (window.matchMedia) {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    mq.addEventListener('change', () => {
      if (currentMode === 'auto') applyTheme('auto', currentAccent);
    });
  }
}
