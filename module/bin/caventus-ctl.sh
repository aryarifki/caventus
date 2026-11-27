#!/system/bin/sh
# Caventus runtime controller for Pixel 6 (oriole / gs101)

if [ -n "${CAVENTUS_MODDIR:-}" ]; then
  MODDIR="$CAVENTUS_MODDIR"
else
  MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi
CTL_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DIAG_BIN="$CTL_DIR/caventus-diag.sh"
[ -f "$DIAG_BIN" ] || DIAG_BIN="$MODDIR/bin/caventus-diag.sh"

CONFIG_ENV="${CAVENTUS_CONFIG_ENV:-/data/adb/caventus/config.env}"
LOG_FILE="${CAVENTUS_LOG_FILE:-/data/adb/caventus/caventus.log}"
LOCK_FILE="${CAVENTUS_LOCK_FILE:-/data/adb/caventus/recompile.lock}"
WATCHDOG_PID_FILE="${CAVENTUS_WATCHDOG_PID_FILE:-/data/adb/caventus/watchdog.pid}"

set_defaults() {
  CONFIG_SCHEMA_VERSION=2
  ZRAM_SIZE_MB=6144
  ZRAM_ALGO=lz77eh
  MMD_ZRAM_SYNC=1
  ZRAM_RUNTIME_RESIZE=0
  SWAPOFF_HEADROOM_PCT=80
  VM_SWAPPINESS=70
  VM_VFS_CACHE_PRESSURE=100
  VM_WATERMARK_SCALE_FACTOR=55
  VM_DIRTY_BACKGROUND_RATIO=10
  VM_DIRTY_RATIO=20
  VM_PAGE_CLUSTER=0
  VM_STAT_INTERVAL=10
  MGLRU_ENABLED=1
  MGLRU_MIN_TTL_MS=1000
  THP_MODE=never
  SCHED_PROFILE=stock
  CPU_RATE_PROFILE=stock
  IO_SCHEDULER=mq-deadline
  IO_READ_AHEAD_KB=256
  IO_NR_REQUESTS=128
  GPU_POWER_POLICY=adaptive
  GPU_DVFS_PERIOD_MS=20
  SF_TUNING_MODE=off
  WATCHDOG_ENABLED=0
  ART_DEX2OAT_FILTER=speed-profile
  ART_MADVISE_MB=64
  ART_BOOT_PROPS=0
  LMKD_USE_PSI=true
  LMKD_PSI_PARTIAL_MS=70
  LMKD_PSI_COMPLETE_MS=500
  LMKD_THRASHING_LIMIT=50
  LMKD_THRASHING_DECAY=10
  LMKD_SWAP_FREE_LOW_PCT=15
  LMKD_SWAP_UTIL_MAX=90
  LMKD_KILL_HEAVIEST=true
  LMKD_KILL_TIMEOUT_MS=150
  LMKD_DOWNGRADE_PRESSURE=80
  AUTO_BOOT_DIAG=1
  ACTION_MODE=both
  RECOMPILE_SCOPE=all
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

in_range() {
  is_uint "$1" || return 1
  [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}

# Use 64-bit awk math because Android /system/bin/sh (mksh) uses 32-bit signed integers
mb_to_bytes() {
  awk -v m="$1" 'BEGIN { printf "%.0f\n", m * 1048576 }'
}

bytes_to_mb() {
  awk -v b="$1" 'BEGIN { printf "%.0f\n", int(b / 1048576) }'
}

is_pos_num() {
  awk -v v="$1" 'BEGIN { exit !(v + 0 > 0) }' 2>/dev/null
}

# Whitelist + bounds validator for config keys
validate_config_kv() {
  _k="$1"
  _v="$2"
  case "$_k" in
    CONFIG_SCHEMA_VERSION)     in_range "$_v" 1 100 ;;
    ZRAM_SIZE_MB)              in_range "$_v" 512 8192 ;;
    ZRAM_ALGO)                 case "$_v" in zstd|lz4|lzo-rle|lzo|lz77eh) return 0 ;; *) return 1 ;; esac ;;
    MMD_ZRAM_SYNC)             case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    ZRAM_RUNTIME_RESIZE)       case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    SWAPOFF_HEADROOM_PCT)      in_range "$_v" 20 95 ;;
    VM_SWAPPINESS)             in_range "$_v" 1 200 ;;
    VM_VFS_CACHE_PRESSURE)     in_range "$_v" 10 500 ;;
    VM_WATERMARK_SCALE_FACTOR) in_range "$_v" 10 500 ;;
    VM_DIRTY_BACKGROUND_RATIO) in_range "$_v" 1 50 ;;
    VM_DIRTY_RATIO)            in_range "$_v" 5 80 ;;
    VM_PAGE_CLUSTER)           in_range "$_v" 0 4 ;;
    VM_STAT_INTERVAL)          in_range "$_v" 1 60 ;;
    MGLRU_ENABLED)             case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    MGLRU_MIN_TTL_MS)          in_range "$_v" 0 10000 ;;
    THP_MODE)                  case "$_v" in never|madvise|always) return 0 ;; *) return 1 ;; esac ;;
    SCHED_PROFILE)             case "$_v" in stock|balanced|ptune) return 0 ;; *) return 1 ;; esac ;;
    CPU_RATE_PROFILE)          case "$_v" in stock|responsive|ptune) return 0 ;; *) return 1 ;; esac ;;
    IO_SCHEDULER)              case "$_v" in mq-deadline|kyber|bfq|none) return 0 ;; *) return 1 ;; esac ;;
    IO_READ_AHEAD_KB)          in_range "$_v" 0 1024 ;;
    IO_NR_REQUESTS)            in_range "$_v" 64 512 ;;
    GPU_POWER_POLICY)          case "$_v" in adaptive|coarse_demand|always_on) return 0 ;; *) return 1 ;; esac ;;
    GPU_DVFS_PERIOD_MS)        in_range "$_v" 10 50 ;;
    SF_TUNING_MODE)            case "$_v" in off|ram_safe|ptune) return 0 ;; *) return 1 ;; esac ;;
    WATCHDOG_ENABLED)          case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    ART_DEX2OAT_FILTER)        case "$_v" in speed-profile|speed|quicken|verify|everything) return 0 ;; *) return 1 ;; esac ;;
    ART_MADVISE_MB)            in_range "$_v" 8 256 ;;
    ART_BOOT_PROPS)            case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    LMKD_USE_PSI)              case "$_v" in true|false) return 0 ;; *) return 1 ;; esac ;;
    LMKD_PSI_PARTIAL_MS)       in_range "$_v" 20 500 ;;
    LMKD_PSI_COMPLETE_MS)      in_range "$_v" 100 2000 ;;
    LMKD_THRASHING_LIMIT)      in_range "$_v" 10 200 ;;
    LMKD_THRASHING_DECAY)      in_range "$_v" 1 100 ;;
    LMKD_SWAP_FREE_LOW_PCT)    in_range "$_v" 5 50 ;;
    LMKD_SWAP_UTIL_MAX)        in_range "$_v" 50 100 ;;
    LMKD_KILL_HEAVIEST)        case "$_v" in true|false) return 0 ;; *) return 1 ;; esac ;;
    LMKD_KILL_TIMEOUT_MS)      in_range "$_v" 20 1000 ;;
    LMKD_DOWNGRADE_PRESSURE)   in_range "$_v" 10 100 ;;
    AUTO_BOOT_DIAG)            case "$_v" in 0|1) return 0 ;; *) return 1 ;; esac ;;
    ACTION_MODE)               case "$_v" in both|recompile|compact|diag) return 0 ;; *) return 1 ;; esac ;;
    RECOMPILE_SCOPE)           case "$_v" in all|third_party) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

load_config() {
  set_defaults
  [ -f "$CONFIG_ENV" ] || return 0
  CONFIG_SCHEMA_VERSION=1
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|'#'*) continue ;;
      *=*)
        _k=${_line%%=*}
        _v=${_line#*=}
        if validate_config_kv "$_k" "$_v"; then
          eval "${_k}=\"${_v}\""
        fi
        ;;
    esac
  done < "$CONFIG_ENV"
}

write_config_file() {
  _cdir=$(dirname "$CONFIG_ENV")
  mkdir -p "$_cdir" 2>/dev/null || true
  _tmp="${CONFIG_ENV}.tmp.$$"
  cat <<EOF > "$_tmp"
# Caventus Pixel 6 (oriole) configuration
CONFIG_SCHEMA_VERSION=$CONFIG_SCHEMA_VERSION
ZRAM_SIZE_MB=$ZRAM_SIZE_MB
ZRAM_ALGO=$ZRAM_ALGO
MMD_ZRAM_SYNC=$MMD_ZRAM_SYNC
ZRAM_RUNTIME_RESIZE=$ZRAM_RUNTIME_RESIZE
SWAPOFF_HEADROOM_PCT=$SWAPOFF_HEADROOM_PCT
VM_SWAPPINESS=$VM_SWAPPINESS
VM_VFS_CACHE_PRESSURE=$VM_VFS_CACHE_PRESSURE
VM_WATERMARK_SCALE_FACTOR=$VM_WATERMARK_SCALE_FACTOR
VM_DIRTY_BACKGROUND_RATIO=$VM_DIRTY_BACKGROUND_RATIO
VM_DIRTY_RATIO=$VM_DIRTY_RATIO
VM_PAGE_CLUSTER=$VM_PAGE_CLUSTER
VM_STAT_INTERVAL=$VM_STAT_INTERVAL
MGLRU_ENABLED=$MGLRU_ENABLED
MGLRU_MIN_TTL_MS=$MGLRU_MIN_TTL_MS
THP_MODE=$THP_MODE
SCHED_PROFILE=$SCHED_PROFILE
CPU_RATE_PROFILE=$CPU_RATE_PROFILE
IO_SCHEDULER=$IO_SCHEDULER
IO_READ_AHEAD_KB=$IO_READ_AHEAD_KB
IO_NR_REQUESTS=$IO_NR_REQUESTS
GPU_POWER_POLICY=$GPU_POWER_POLICY
GPU_DVFS_PERIOD_MS=$GPU_DVFS_PERIOD_MS
SF_TUNING_MODE=$SF_TUNING_MODE
WATCHDOG_ENABLED=$WATCHDOG_ENABLED
ART_DEX2OAT_FILTER=$ART_DEX2OAT_FILTER
ART_MADVISE_MB=$ART_MADVISE_MB
ART_BOOT_PROPS=$ART_BOOT_PROPS
LMKD_USE_PSI=$LMKD_USE_PSI
LMKD_PSI_PARTIAL_MS=$LMKD_PSI_PARTIAL_MS
LMKD_PSI_COMPLETE_MS=$LMKD_PSI_COMPLETE_MS
LMKD_THRASHING_LIMIT=$LMKD_THRASHING_LIMIT
LMKD_THRASHING_DECAY=$LMKD_THRASHING_DECAY
LMKD_SWAP_FREE_LOW_PCT=$LMKD_SWAP_FREE_LOW_PCT
LMKD_SWAP_UTIL_MAX=$LMKD_SWAP_UTIL_MAX
LMKD_KILL_HEAVIEST=$LMKD_KILL_HEAVIEST
LMKD_KILL_TIMEOUT_MS=$LMKD_KILL_TIMEOUT_MS
LMKD_DOWNGRADE_PRESSURE=$LMKD_DOWNGRADE_PRESSURE
AUTO_BOOT_DIAG=$AUTO_BOOT_DIAG
ACTION_MODE=$ACTION_MODE
RECOMPILE_SCOPE=$RECOMPILE_SCOPE
EOF
  mv -f "$_tmp" "$CONFIG_ENV"
}

sync_system_prop() {
  _madvise_bytes=$(mb_to_bytes "$ART_MADVISE_MB")
  _zram_bytes=$(mb_to_bytes "$ZRAM_SIZE_MB")
  _sp_path="$MODDIR/system.prop"
  _sp_tmp="${_sp_path}.tmp.$$"
  mkdir -p "$MODDIR" 2>/dev/null || true
  cat <<EOF > "$_sp_tmp"
# === Caventus: Pixel 6 (oriole / GS101) Memory Optimization ===
# Generated by caventus-ctl.sh

# 1. ART / dex2oat
EOF
  if [ "$ART_BOOT_PROPS" = "1" ]; then
    cat <<EOF >> "$_sp_tmp"
dalvik.vm.dex2oat-filter=$ART_DEX2OAT_FILTER
dalvik.vm.image-dex2oat-filter=$ART_DEX2OAT_FILTER
EOF
  fi
  cat <<EOF >> "$_sp_tmp"
pm.dexopt.install=$ART_DEX2OAT_FILTER
pm.dexopt.bg-dexopt=$ART_DEX2OAT_FILTER
pm.dexopt.shared=speed
dalvik.vm.madvise.odexfile.size=$_madvise_bytes
dalvik.vm.madvise.vdexfile.size=$_madvise_bytes

# 2. LMKD — PSI-based tuning for 8 GB Pixel 6
ro.lmk.use_psi=$LMKD_USE_PSI
ro.lmk.use_minfree_levels=false
ro.lmk.psi_partial_stall_ms=$LMKD_PSI_PARTIAL_MS
ro.lmk.psi_complete_stall_ms=$LMKD_PSI_COMPLETE_MS
ro.lmk.thrashing_limit=$LMKD_THRASHING_LIMIT
ro.lmk.thrashing_limit_decay=$LMKD_THRASHING_DECAY
ro.lmk.swap_free_low_percentage=$LMKD_SWAP_FREE_LOW_PCT
ro.lmk.swap_util_max=$LMKD_SWAP_UTIL_MAX
ro.lmk.kill_heaviest_task=$LMKD_KILL_HEAVIEST
ro.lmk.kill_timeout_ms=$LMKD_KILL_TIMEOUT_MS
ro.lmk.downgrade_pressure=$LMKD_DOWNGRADE_PRESSURE
ro.lmk.debug=false
EOF

  if [ "$MMD_ZRAM_SYNC" = "1" ]; then
    cat <<EOF >> "$_sp_tmp"

# 3. Android 16/17 mmd zRAM boot sync
mmd.zram.enabled=true
mmd.zram.size=$_zram_bytes
mmd.zram.comp_algorithm=$ZRAM_ALGO
EOF
  fi

  case "$SF_TUNING_MODE" in
    ram_safe|ptune)
      cat <<EOF >> "$_sp_tmp"

# 4. SurfaceFlinger — Graphics RAM & latency ($SF_TUNING_MODE)
ro.surface_flinger.clear_slots_with_set_layer_buffer=true
ro.surface_flinger.use_context_priority=true
ro.surface_flinger.force_hwc_copy_for_virtual_displays=true
ro.surface_flinger.running_without_sync_framework=false
EOF
      ;;
  esac

  if [ "$SF_TUNING_MODE" = "ptune" ]; then
    cat <<EOF >> "$_sp_tmp"
ro.surface_flinger.max_frame_buffer_acquired_buffers=6
ro.surface_flinger.game_default_frame_rate_override=90
debug.graphics.game_default_frame_rate.disabled=true
vendor.powerhal.adpf.rate=1000000
EOF
  fi

  mv -f "$_sp_tmp" "$_sp_path"
}

log_msg() {
  ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "boot")
  line="[$ts] $*"
  echo "$line"
  log_dir=$(dirname "$LOG_FILE")
  [ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null || true
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

resolve_cmd() {
  _name="$1"
  if [ -x "/system/bin/$_name" ]; then
    echo "/system/bin/$_name"
    return 0
  fi
  _found=$(command -v "$_name" 2>/dev/null || true)
  if [ -n "$_found" ]; then
    echo "$_found"
    return 0
  fi
  if command -v toybox >/dev/null 2>&1; then
    echo "toybox $_name"
    return 0
  fi
  return 1
}

resolve_resetprop() {
  for _rp in /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop; do
    if [ -x "$_rp" ]; then
      echo "$_rp"
      return 0
    fi
  done
  _rp=$(command -v resetprop 2>/dev/null || true)
  if [ -n "$_rp" ]; then
    echo "$_rp"
    return 0
  fi
  return 1
}

write_node() {
  _path="$1"
  _val="$2"
  if [ -w "$_path" ]; then
    printf '%s' "$_val" > "$_path" 2>/dev/null || return 1
    return 0
  fi
  return 1
}

pick_zram_algo() {
  _requested="$1"
  _avail="$2"
  for _candidate in "$_requested" zstd lz4 lzo-rle lzo; do
    [ -z "$_candidate" ] && continue
    for _tok in $_avail; do
      _clean=$(printf '%s' "$_tok" | tr -d '[]')
      if [ "$_clean" = "$_candidate" ]; then
        printf '%s\n' "$_candidate"
        return 0
      fi
    done
  done
  return 1
}

can_safely_swapoff() {
  _swap_used_kb="${1:-0}"
  _mem_avail_kb="${2:-0}"
  _headroom_pct="${3:-80}"
  is_uint "$_swap_used_kb" || _swap_used_kb=0
  is_uint "$_mem_avail_kb" || _mem_avail_kb=0
  if [ "$_swap_used_kb" -le 0 ]; then
    return 0
  fi
  if [ "$_mem_avail_kb" -le 0 ]; then
    return 1
  fi
  awk -v u="$_swap_used_kb" -v a="$_mem_avail_kb" -v p="$_headroom_pct" 'BEGIN { exit !((u * 100) < (a * p)) }'
}

extract_bracketed_token() {
  _avail="$1"
  for _tok in $_avail; do
    case "$_tok" in
      \[*\])
        printf '%s\n' "$_tok" | tr -d '[]'
        return 0
        ;;
    esac
  done
  return 1
}

extract_active_algo() {
  extract_bracketed_token "$1"
}

token_in_list() {
  _target="$1"
  _list="$2"
  for _tok in $_list; do
    _clean=$(printf '%s' "$_tok" | tr -d '[]')
    if [ "$_clean" = "$_target" ]; then
      return 0
    fi
  done
  return 1
}

read_meminfo_kb() {
  _key="$1"
  awk -v k="${_key}:" '$1 == k {print $2; exit}' /proc/meminfo 2>/dev/null
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr '\n\r' '  '
}

apply_live_props() {
  _rp=$(resolve_resetprop 2>/dev/null || true)
  [ -z "$_rp" ] && return 0
  _madvise_bytes=$(mb_to_bytes "$ART_MADVISE_MB")
  _zram_bytes=$(mb_to_bytes "$ZRAM_SIZE_MB")
  if [ "$ART_BOOT_PROPS" = "1" ]; then
    "$_rp" -n dalvik.vm.dex2oat-filter "$ART_DEX2OAT_FILTER" 2>/dev/null || true
    "$_rp" -n dalvik.vm.image-dex2oat-filter "$ART_DEX2OAT_FILTER" 2>/dev/null || true
  fi
  "$_rp" -n pm.dexopt.install "$ART_DEX2OAT_FILTER" 2>/dev/null || true
  "$_rp" -n pm.dexopt.bg-dexopt "$ART_DEX2OAT_FILTER" 2>/dev/null || true
  "$_rp" -n dalvik.vm.madvise.odexfile.size "$_madvise_bytes" 2>/dev/null || true
  "$_rp" -n dalvik.vm.madvise.vdexfile.size "$_madvise_bytes" 2>/dev/null || true
  "$_rp" -n ro.lmk.use_psi "$LMKD_USE_PSI" 2>/dev/null || true
  "$_rp" -n ro.lmk.use_minfree_levels "false" 2>/dev/null || true
  "$_rp" -n ro.lmk.psi_partial_stall_ms "$LMKD_PSI_PARTIAL_MS" 2>/dev/null || true
  "$_rp" -n ro.lmk.psi_complete_stall_ms "$LMKD_PSI_COMPLETE_MS" 2>/dev/null || true
  "$_rp" -n ro.lmk.thrashing_limit "$LMKD_THRASHING_LIMIT" 2>/dev/null || true
  "$_rp" -n ro.lmk.thrashing_limit_decay "$LMKD_THRASHING_DECAY" 2>/dev/null || true
  "$_rp" -n ro.lmk.swap_free_low_percentage "$LMKD_SWAP_FREE_LOW_PCT" 2>/dev/null || true
  "$_rp" -n ro.lmk.swap_util_max "$LMKD_SWAP_UTIL_MAX" 2>/dev/null || true
  "$_rp" -n ro.lmk.kill_heaviest_task "$LMKD_KILL_HEAVIEST" 2>/dev/null || true
  "$_rp" -n ro.lmk.kill_timeout_ms "$LMKD_KILL_TIMEOUT_MS" 2>/dev/null || true
  "$_rp" -n ro.lmk.downgrade_pressure "$LMKD_DOWNGRADE_PRESSURE" 2>/dev/null || true

  if [ "$MMD_ZRAM_SYNC" = "1" ]; then
    "$_rp" -n mmd.zram.enabled "true" 2>/dev/null || true
    "$_rp" -n mmd.zram.size "$_zram_bytes" 2>/dev/null || true
    "$_rp" -n mmd.zram.comp_algorithm "$ZRAM_ALGO" 2>/dev/null || true
  fi

  case "$SF_TUNING_MODE" in
    ram_safe|ptune)
      "$_rp" -n ro.surface_flinger.clear_slots_with_set_layer_buffer "true" 2>/dev/null || true
      "$_rp" -n ro.surface_flinger.use_context_priority "true" 2>/dev/null || true
      "$_rp" -n ro.surface_flinger.force_hwc_copy_for_virtual_displays "true" 2>/dev/null || true
      "$_rp" -n ro.surface_flinger.running_without_sync_framework "false" 2>/dev/null || true
      ;;
  esac
  if [ "$SF_TUNING_MODE" = "ptune" ]; then
    "$_rp" -n ro.surface_flinger.max_frame_buffer_acquired_buffers "6" 2>/dev/null || true
    "$_rp" -n ro.surface_flinger.game_default_frame_rate_override "90" 2>/dev/null || true
    "$_rp" -n debug.graphics.game_default_frame_rate.disabled "true" 2>/dev/null || true
    "$_rp" -n vendor.powerhal.adpf.rate "1000000" 2>/dev/null || true
  fi
}

apply_zram() {
  zram_sys="/sys/block/zram0"
  zram_dev="/dev/block/zram0"
  if [ ! -d "$zram_sys" ]; then
    log_msg "zram0 sysfs not found; skipping zRAM tuning."
    return 0
  fi

  avail_algos=$(cat "$zram_sys/comp_algorithm" 2>/dev/null || true)
  target_algo=$(pick_zram_algo "$ZRAM_ALGO" "$avail_algos")
  if [ -z "$target_algo" ]; then
    log_msg "No supported zRAM algorithm found in: $avail_algos"
    return 1
  fi

  target_bytes=$(mb_to_bytes "$ZRAM_SIZE_MB")
  cur_algo=$(extract_active_algo "$avail_algos" || true)
  cur_disksize=$(cat "$zram_sys/disksize" 2>/dev/null || echo 0)
  swap_active=0
  grep -q "zram0" /proc/swaps 2>/dev/null && swap_active=1

  if [ "$cur_algo" = "$target_algo" ] && [ "$cur_disksize" = "$target_bytes" ] && [ "$swap_active" -eq 1 ]; then
    log_msg "zram0 already configured (${ZRAM_SIZE_MB} MB, $target_algo)."
    return 0
  fi

  if [ "$swap_active" -eq 1 ] && [ "${ZRAM_RUNTIME_RESIZE:-0}" != "1" ]; then
    log_msg "SKIPPED runtime zram0 swapoff (ZRAM_RUNTIME_RESIZE=0): live=${cur_disksize}B/${cur_algo} vs target=${target_bytes}B/${target_algo}"
    return 0
  fi

  swap_total=$(read_meminfo_kb SwapTotal)
  swap_free=$(read_meminfo_kb SwapFree)
  mem_avail=$(read_meminfo_kb MemAvailable)
  swap_total=${swap_total:-0}
  swap_free=${swap_free:-0}
  mem_avail=${mem_avail:-0}
  swap_used=$((swap_total - swap_free))

  if [ "$swap_active" -eq 1 ] && ! can_safely_swapoff "$swap_used" "$mem_avail" "$SWAPOFF_HEADROOM_PCT"; then
    log_msg "DEFERRED zram0 resize: SwapUsed=$((swap_used / 1024))MB vs MemAvailable=$((mem_avail / 1024))MB (headroom ${SWAPOFF_HEADROOM_PCT}%). Reboot to apply new zRAM size/algo safely."
    return 0
  fi

  old_bdev=""
  old_wb_en=""
  if [ -r "$zram_sys/backing_dev" ]; then
    old_bdev=$(cat "$zram_sys/backing_dev" 2>/dev/null || true)
    [ "$old_bdev" = "none" ] && old_bdev=""
  fi
  if [ -r "$zram_sys/writeback_limit_enable" ]; then
    old_wb_en=$(cat "$zram_sys/writeback_limit_enable" 2>/dev/null || true)
  fi

  mkswap_cmd=$(resolve_cmd mkswap) || { log_msg "mkswap binary not found"; return 1; }
  swapon_cmd=$(resolve_cmd swapon) || { log_msg "swapon binary not found"; return 1; }
  swapoff_cmd=$(resolve_cmd swapoff) || { log_msg "swapoff binary not found"; return 1; }

  if [ "$swap_active" -eq 1 ]; then
    if ! $swapoff_cmd "$zram_dev" 2>/dev/null; then
      log_msg "swapoff $zram_dev failed; keeping existing swap."
      return 1
    fi
  fi

  if ! write_node "$zram_sys/reset" "1"; then
    log_msg "zram0 reset failed; attempting recovery swapon."
    $swapon_cmd "$zram_dev" 2>/dev/null || true
    return 1
  fi

  failed=0
  write_node "$zram_sys/comp_algorithm" "$target_algo" || failed=1
  if [ "$failed" -eq 0 ] && [ -n "$old_bdev" ] && [ -e "$old_bdev" ]; then
    if write_node "$zram_sys/backing_dev" "$old_bdev"; then
      if [ "$old_wb_en" = "1" ]; then
        write_node "$zram_sys/writeback_limit_enable" "1" || true
      fi
    else
      log_msg "Note: backing_dev '$old_bdev' could not be re-attached."
    fi
  fi
  if [ "$failed" -eq 0 ]; then
    write_node "$zram_sys/disksize" "$target_bytes" || failed=1
  fi
  if [ "$failed" -eq 0 ]; then
    $mkswap_cmd "$zram_dev" >/dev/null 2>&1 || failed=1
  fi
  if [ "$failed" -eq 0 ]; then
    $swapon_cmd "$zram_dev" >/dev/null 2>&1 || failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    log_msg "zram0 reconfiguration failed; restoring previous settings (${cur_algo:-lz4}, ${cur_disksize}B)."
    write_node "$zram_sys/reset" "1" || true
    [ -n "$cur_algo" ] && write_node "$zram_sys/comp_algorithm" "$cur_algo" || true
    is_pos_num "$cur_disksize" && write_node "$zram_sys/disksize" "$cur_disksize" || true
    $mkswap_cmd "$zram_dev" >/dev/null 2>&1 || true
    $swapon_cmd "$zram_dev" >/dev/null 2>&1 || true
    return 1
  fi

  log_msg "zram0 configured: ${ZRAM_SIZE_MB} MB (${target_bytes}B), algo=${target_algo}, backing_dev=${old_bdev:-none}"
  return 0
}

apply_vm() {
  write_node /proc/sys/vm/swappiness "$VM_SWAPPINESS" || true
  write_node /proc/sys/vm/page-cluster "$VM_PAGE_CLUSTER" || true
  write_node /proc/sys/vm/vfs_cache_pressure "$VM_VFS_CACHE_PRESSURE" || true
  write_node /proc/sys/vm/watermark_scale_factor "$VM_WATERMARK_SCALE_FACTOR" || true
  write_node /proc/sys/vm/watermark_boost_factor "0" || true
  write_node /proc/sys/vm/dirty_background_ratio "$VM_DIRTY_BACKGROUND_RATIO" || true
  write_node /proc/sys/vm/dirty_ratio "$VM_DIRTY_RATIO" || true
  write_node /proc/sys/vm/stat_interval "$VM_STAT_INTERVAL" || true

  if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
    if [ "$MGLRU_ENABLED" = "1" ]; then
      _cur_mglru=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo 0)
      case "$_cur_mglru" in
        0|0x0|0x0000) write_node /sys/kernel/mm/lru_gen/enabled "y" || true ;;
      esac
    else
      write_node /sys/kernel/mm/lru_gen/enabled "0" || true
    fi
  fi
  if [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ]; then
    write_node /sys/kernel/mm/lru_gen/min_ttl_ms "$MGLRU_MIN_TTL_MS" || true
  fi

  log_msg "VM sysctls applied (swappiness=$VM_SWAPPINESS, watermark_scale=$VM_WATERMARK_SCALE_FACTOR, dirty=${VM_DIRTY_BACKGROUND_RATIO}/${VM_DIRTY_RATIO}, mglru=$MGLRU_ENABLED)."
}

apply_thp() {
  _thp_dir="/sys/kernel/mm/transparent_hugepage"
  [ -d "$_thp_dir" ] || return 0
  case "$THP_MODE" in
    always)
      write_node "$_thp_dir/shmem_enabled" "within_size" || true
      write_node "$_thp_dir/defrag" "defer+madvise" || true
      write_node "$_thp_dir/enabled" "always" || true
      ;;
    madvise)
      write_node "$_thp_dir/shmem_enabled" "advise" || true
      write_node "$_thp_dir/defrag" "defer+madvise" || true
      write_node "$_thp_dir/enabled" "madvise" || true
      ;;
    never|*)
      write_node "$_thp_dir/shmem_enabled" "never" || true
      write_node "$_thp_dir/defrag" "madvise" || true
      write_node "$_thp_dir/enabled" "never" || true
      ;;
  esac
  [ "${CAVENTUS_QUIET:-0}" = "1" ] || log_msg "THP applied (mode=$THP_MODE)."
}

set_sched_group() {
  _gdir="$1"
  _umin="$2"
  _umax="$3"
  _pidle="$4"
  _phcap="${5:-0}"
  _spread="${6:-0}"
  [ -d "$_gdir" ] || return 0
  write_node "$_gdir/uclamp_min" "$_umin" || true
  write_node "$_gdir/uclamp_max" "$_umax" || true
  write_node "$_gdir/prefer_idle" "$_pidle" || true
  write_node "$_gdir/prefer_high_cap" "$_phcap" || true
  write_node "$_gdir/task_spreading" "$_spread" || true
}

apply_sched() {
  write_node /proc/sys/kernel/sched_child_runs_first "0" || true
  _vs="/proc/vendor_sched"
  if [ ! -d "$_vs" ]; then
    return 0
  fi

  case "$SCHED_PROFILE" in
    stock)
      write_node "$_vs/latency_ns" "8000000" || true
      write_node "$_vs/min_granularity_ns" "1000000" || true
      write_node "$_vs/adpf_rampup_multiplier" "4" || true
      write_node "$_vs/auto_prefer_idle" "0" || true
      write_node "$_vs/reduce_prefer_idle" "1" || true
      write_node "$_vs/uclamp_max_filter_enable" "0" || true
      set_sched_group "$_vs/groups/ta" 1 1024 1 0 0
      set_sched_group "$_vs/groups/fg" 0 1024 1 0 0
      set_sched_group "$_vs/groups/cam" 1 1024 1 0 0
      set_sched_group "$_vs/groups/sf" 0 1024 0 0 0
      set_sched_group "$_vs/groups/sys" 0 1024 0 0 0
      set_sched_group "$_vs/groups/bg" 0 512 0 0 0
      set_sched_group "$_vs/groups/sys_bg" 0 512 0 0 0
      set_sched_group "$_vs/groups/ota" 0 512 0 0 0
      set_sched_group "$_vs/groups/dex2oat" 0 615 0 0 0
      ;;
    ptune)
      write_node "$_vs/latency_ns" "4166666" || true
      write_node "$_vs/min_granularity_ns" "4166666" || true
      write_node "$_vs/adpf_rampup_multiplier" "1" || true
      write_node "$_vs/auto_prefer_idle" "0" || true
      write_node "$_vs/reduce_prefer_idle" "0" || true
      write_node "$_vs/auto_dvfs_headroom_enable" "0" || true
      write_node "$_vs/tapered_dvfs_headroom_enable" "0" || true
      write_node "$_vs/uclamp_max_filter_enable" "0" || true
      write_node "$_vs/dvfs_headroom" "1280" || true
      write_node "$_vs/util_threshold" "9999" || true
      for _g in "$_vs/groups"/*; do
        [ -d "$_g" ] || continue
        set_sched_group "$_g" 0 1024 1 0 0
      done
      ;;
    balanced|*)
      write_node "$_vs/latency_ns" "6000000" || true
      write_node "$_vs/min_granularity_ns" "1000000" || true
      write_node "$_vs/adpf_rampup_multiplier" "2" || true
      write_node "$_vs/auto_prefer_idle" "0" || true
      write_node "$_vs/reduce_prefer_idle" "1" || true
      set_sched_group "$_vs/groups/ta" 1 1024 1 0 0
      set_sched_group "$_vs/groups/fg" 0 1024 1 0 0
      set_sched_group "$_vs/groups/sf" 0 1024 1 0 0
      set_sched_group "$_vs/groups/sys" 0 1024 0 0 0
      set_sched_group "$_vs/groups/bg" 0 512 0 0 0
      set_sched_group "$_vs/groups/sys_bg" 0 512 0 0 0
      set_sched_group "$_vs/groups/ota" 0 512 0 0 0
      set_sched_group "$_vs/groups/dex2oat" 0 615 0 0 0
      ;;
  esac
  [ "${CAVENTUS_QUIET:-0}" = "1" ] || log_msg "GS101 vendor_sched applied (profile=$SCHED_PROFILE)."
}

apply_cpufreq() {
  _cbase="/sys/devices/system/cpu/cpufreq"
  [ -d "$_cbase" ] || return 0
  for _pol in "$_cbase"/policy*; do
    _sp="$_pol/sched_pixel"
    [ -d "$_sp" ] || continue
    _pname=$(basename "$_pol")
    case "$CPU_RATE_PROFILE" in
      stock)
        write_node "$_sp/up_rate_limit_us" "500" || true
        case "$_pname" in
          policy0)
            write_node "$_sp/down_rate_limit_us" "5000" || true
            write_node "$_sp/response_time_ms" "8" || true
            ;;
          policy4)
            write_node "$_sp/down_rate_limit_us" "20000" || true
            write_node "$_sp/response_time_ms" "29" || true
            ;;
          *)
            write_node "$_sp/down_rate_limit_us" "20000" || true
            write_node "$_sp/response_time_ms" "155" || true
            ;;
        esac
        ;;
      ptune)
        write_node "$_sp/up_rate_limit_us" "0" || true
        write_node "$_sp/down_rate_limit_us" "0" || true
        write_node "$_sp/response_time_ms" "1" || true
        write_node "$_sp/cpu_busy_limit_ms" "1" || true
        ;;
      responsive|*)
        case "$_pname" in
          policy0)
            write_node "$_sp/up_rate_limit_us" "0" || true
            write_node "$_sp/down_rate_limit_us" "4000" || true
            write_node "$_sp/response_time_ms" "4" || true
            ;;
          policy4)
            write_node "$_sp/up_rate_limit_us" "250" || true
            write_node "$_sp/down_rate_limit_us" "10000" || true
            write_node "$_sp/response_time_ms" "16" || true
            ;;
          *)
            write_node "$_sp/up_rate_limit_us" "500" || true
            write_node "$_sp/down_rate_limit_us" "15000" || true
            write_node "$_sp/response_time_ms" "60" || true
            ;;
        esac
        ;;
    esac
  done
  [ "${CAVENTUS_QUIET:-0}" = "1" ] || log_msg "sched_pixel CPUFreq applied (profile=$CPU_RATE_PROFILE)."
}

apply_io() {
  _async_depth=$((IO_NR_REQUESTS / 2))
  [ "$_async_depth" -lt 32 ] && _async_depth=32
  for _blk in /sys/block/sd*; do
    _q="$_blk/queue"
    [ -d "$_q" ] || continue
    if [ -r "$_q/scheduler" ]; then
      _avail_io=$(cat "$_q/scheduler" 2>/dev/null || true)
      if token_in_list "$IO_SCHEDULER" "$_avail_io"; then
        write_node "$_q/scheduler" "$IO_SCHEDULER" || true
      fi
    fi
    write_node "$_q/nr_requests" "$IO_NR_REQUESTS" || true
    write_node "$_q/read_ahead_kb" "$IO_READ_AHEAD_KB" || true
    write_node "$_q/iosched/async_depth" "$_async_depth" || true
  done
  if [ -d /sys/block/zram0/queue ]; then
    write_node /sys/block/zram0/queue/read_ahead_kb "0" || true
  fi
  [ "${CAVENTUS_QUIET:-0}" = "1" ] || log_msg "Block I/O applied (sched=$IO_SCHEDULER, ra=${IO_READ_AHEAD_KB}KB, nr_req=$IO_NR_REQUESTS)."
}

apply_gpu() {
  _mali="/sys/devices/platform/1c500000.mali"
  [ -d "$_mali" ] || return 0
  _gmin=$(cat "$_mali/min_freq" 2>/dev/null || echo 151000)
  _gmax=$(cat "$_mali/max_freq" 2>/dev/null || echo 848000)
  is_uint "$_gmin" || _gmin=151000
  is_uint "$_gmax" || _gmax=848000

  # Note: min_freq/max_freq are read-only on Pixel 6; unlock writable scaling/hint bounds only
  write_node "$_mali/hint_min_freq" "$_gmin" || true
  write_node "$_mali/scaling_min_freq" "$_gmin" || true
  write_node "$_mali/scaling_min_compute_freq" "$_gmin" || true
  write_node "$_mali/hint_max_freq" "$_gmax" || true
  write_node "$_mali/scaling_max_freq" "$_gmax" || true
  write_node "$_mali/dvfs_period" "$GPU_DVFS_PERIOD_MS" || true

  if [ -r "$_mali/power_policy" ]; then
    _avail_pp=$(cat "$_mali/power_policy" 2>/dev/null || true)
    if token_in_list "$GPU_POWER_POLICY" "$_avail_pp"; then
      write_node "$_mali/power_policy" "$GPU_POWER_POLICY" || true
    fi
  fi
  [ "${CAVENTUS_QUIET:-0}" = "1" ] || log_msg "Mali GPU applied (policy=$GPU_POWER_POLICY, dvfs_period=${GPU_DVFS_PERIOD_MS}ms)."
}

watchdog_is_running() {
  [ -f "$WATCHDOG_PID_FILE" ] || return 1
  _wpid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
  is_uint "$_wpid" && kill -0 "$_wpid" 2>/dev/null
}

cmd_watchdog_stop() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    _wpid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
    if is_uint "$_wpid" && kill -0 "$_wpid" 2>/dev/null; then
      kill "$_wpid" 2>/dev/null || true
    fi
    rm -f "$WATCHDOG_PID_FILE"
    log_msg "Sysfs drift guard stopped."
  fi
}

cmd_watchdog_start() {
  if watchdog_is_running; then
    return 0
  fi
  _wdir=$(dirname "$WATCHDOG_PID_FILE")
  mkdir -p "$_wdir" 2>/dev/null || true
  if command -v nohup >/dev/null 2>&1; then
    nohup "$0" watchdog-loop </dev/null >/dev/null 2>&1 &
  else
    "$0" watchdog-loop </dev/null >/dev/null 2>&1 &
  fi
  echo "$!" > "$WATCHDOG_PID_FILE"
  log_msg "Sysfs drift guard started (PID $!, interval=300s)."
}

cmd_watchdog_loop() {
  trap 'rm -f "$WATCHDOG_PID_FILE"; exit 0' INT TERM
  while true; do
    sleep 300
    load_config
    [ "$WATCHDOG_ENABLED" = "1" ] || break
    CAVENTUS_QUIET=1
    export CAVENTUS_QUIET
    apply_vm
    apply_thp
    apply_sched
    apply_cpufreq
    apply_io
    apply_gpu
  done
  rm -f "$WATCHDOG_PID_FILE"
}

apply_lmkd() {
  setprop lmkd.reinit 1 2>/dev/null || true
  if command -v lmkd >/dev/null 2>&1; then
    lmkd --reinit 2>/dev/null || true
  fi
  log_msg "LMKD reinitialized (use_psi=$(getprop ro.lmk.use_psi 2>/dev/null), partial_ms=$(getprop ro.lmk.psi_partial_stall_ms 2>/dev/null), thrash=$(getprop ro.lmk.thrashing_limit 2>/dev/null), swap_low=$(getprop ro.lmk.swap_free_low_percentage 2>/dev/null)%)."
}

cmd_save_config() {
  load_config
  if [ "$#" -eq 0 ]; then
    echo "No KEY=VAL pairs provided" >&2
    return 1
  fi
  for _arg in "$@"; do
    case "$_arg" in
      *=*)
        _k=${_arg%%=*}
        _v=${_arg#*=}
        if ! validate_config_kv "$_k" "$_v"; then
          echo "Invalid config parameter: $_k=$_v" >&2
          return 1
        fi
        eval "${_k}=\"${_v}\""
        ;;
      *)
        echo "Invalid argument format (expected KEY=VAL): $_arg" >&2
        return 1
        ;;
    esac
  done
  CONFIG_SCHEMA_VERSION=2
  write_config_file
  sync_system_prop
  apply_live_props
  log_msg "Saved config & synced system.prop ($# updates)."
}

migrate_config_if_needed() {
  [ -f "$CONFIG_ENV" ] || return 0
  is_uint "$CONFIG_SCHEMA_VERSION" || CONFIG_SCHEMA_VERSION=1
  [ "$CONFIG_SCHEMA_VERSION" -lt 2 ] || return 0

  _old_ver="$CONFIG_SCHEMA_VERSION"
  if [ "$ZRAM_ALGO" = "lz77eh" ]; then
    case "$ZRAM_SIZE_MB" in
      4096|5120) ZRAM_SIZE_MB=6144 ;;
    esac
  fi
  [ "$LMKD_PSI_COMPLETE_MS" = "700" ] && LMKD_PSI_COMPLETE_MS=500
  [ "$LMKD_THRASHING_LIMIT" = "80" ] && LMKD_THRASHING_LIMIT=50
  [ "$LMKD_SWAP_FREE_LOW_PCT" = "10" ] && LMKD_SWAP_FREE_LOW_PCT=15
  [ "$LMKD_SWAP_UTIL_MAX" = "95" ] && LMKD_SWAP_UTIL_MAX=90

  CONFIG_SCHEMA_VERSION=2
  write_config_file
  sync_system_prop
  log_msg "Migrated config.env schema v${_old_ver} -> v2 (zram=${ZRAM_SIZE_MB}MB/${ZRAM_ALGO}, lmkd=${LMKD_PSI_PARTIAL_MS}/${LMKD_PSI_COMPLETE_MS}/${LMKD_THRASHING_LIMIT}/${LMKD_SWAP_FREE_LOW_PCT}%/${LMKD_SWAP_UTIL_MAX}%)."
}

cmd_migrate_config() {
  load_config
  migrate_config_if_needed
}

cmd_init_defaults() {
  set_defaults
  write_config_file
  sync_system_prop
  log_msg "Initialized Pixel 6 (oriole) boot-safe optimal defaults."
}

cmd_reset_defaults() {
  set_defaults
  write_config_file
  sync_system_prop
  apply_live_props
  apply_vm
  apply_thp
  apply_sched
  apply_cpufreq
  apply_io
  apply_gpu
  apply_lmkd
  cmd_watchdog_stop
  log_msg "Configuration reset to Pixel 6 (oriole) defaults."
}

cmd_status() {
  load_config
  mem_total=$(read_meminfo_kb MemTotal)
  mem_avail=$(read_meminfo_kb MemAvailable)
  swap_total=$(read_meminfo_kb SwapTotal)
  swap_free=$(read_meminfo_kb SwapFree)
  swap_used=$(( ${swap_total:-0} - ${swap_free:-0} ))
  zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)
  zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "N/A")
  zram_stat=$(cat /sys/block/zram0/mm_stat 2>/dev/null || echo "N/A")
  zram_bdev=$(cat /sys/block/zram0/backing_dev 2>/dev/null || echo "N/A")
  mglru_en=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "N/A")
  mglru_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null || echo "N/A")
  thp_en=$(extract_bracketed_token "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true)" 2>/dev/null || echo "N/A")
  vs_lat=$(cat /proc/vendor_sched/latency_ns 2>/dev/null || echo "N/A")
  cpufreq_resp=$(cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/response_time_ms 2>/dev/null || echo "N/A")
  io_sched=$(extract_bracketed_token "$(cat /sys/block/sda/queue/scheduler 2>/dev/null || true)" 2>/dev/null || echo "N/A")
  io_ra=$(cat /sys/block/sda/queue/read_ahead_kb 2>/dev/null || echo "N/A")
  io_nr=$(cat /sys/block/sda/queue/nr_requests 2>/dev/null || echo "N/A")
  gpu_pp=$(extract_bracketed_token "$(cat /sys/devices/platform/1c500000.mali/power_policy 2>/dev/null || true)" 2>/dev/null || echo "N/A")
  gpu_dvfs=$(cat /sys/devices/platform/1c500000.mali/dvfs_period 2>/dev/null || echo "N/A")
  wd_state="stopped"
  watchdog_is_running && wd_state="running"

  echo "=== Caventus Status (oriole) ==="
  echo "RAM        : MemTotal=$(( ${mem_total:-0} / 1024 )) MB | MemAvailable=$(( ${mem_avail:-0} / 1024 )) MB"
  echo "Swap       : Used=$(( swap_used / 1024 )) MB / Total=$(( ${swap_total:-0} / 1024 )) MB"
  echo "zRAM       : $(bytes_to_mb "$zram_size") MB | algo: $zram_algo | backing_dev: $zram_bdev | mmd_sync=$MMD_ZRAM_SYNC"
  echo "zRAM stat  : $zram_stat"
  echo "VM         : swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null) | wm_scale=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null) | vfs_cache=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null) | page_cluster=$(cat /proc/sys/vm/page-cluster 2>/dev/null)"
  echo "MGLRU/THP  : mglru=$mglru_en (ttl=${mglru_ttl}ms) | thp=$thp_en"
  echo "GS101 Sched: profile=$SCHED_PROFILE (latency_ns=$vs_lat) | cpu_rate=$CPU_RATE_PROFILE (p0_resp=${cpufreq_resp}ms)"
  echo "UFS I/O    : sched=$io_sched | read_ahead=${io_ra}KB | nr_requests=$io_nr"
  echo "Mali GPU   : policy=$gpu_pp | dvfs_period=${gpu_dvfs}ms"
  echo "SurfaceFlg : mode=$SF_TUNING_MODE | clear_slots=$(getprop ro.surface_flinger.clear_slots_with_set_layer_buffer 2>/dev/null)"
  echo "LMKD       : use_psi=$(getprop ro.lmk.use_psi 2>/dev/null) | partial_ms=$(getprop ro.lmk.psi_partial_stall_ms 2>/dev/null) | complete_ms=$(getprop ro.lmk.psi_complete_stall_ms 2>/dev/null) | thrashing=$(getprop ro.lmk.thrashing_limit 2>/dev/null) | swap_low=$(getprop ro.lmk.swap_free_low_percentage 2>/dev/null)%"
  echo "ART        : dex2oat-filter=$(getprop dalvik.vm.dex2oat-filter 2>/dev/null) | image-filter=$(getprop dalvik.vm.image-dex2oat-filter 2>/dev/null)"
  echo "Watchdog   : enabled=$WATCHDOG_ENABLED | state=$wd_state"
}

cmd_status_json() {
  load_config
  _dev=$(getprop ro.product.device 2>/dev/null || echo "oriole")
  _and=$(getprop ro.build.version.release 2>/dev/null || echo "17")
  _bld=$(getprop ro.build.display.id 2>/dev/null || echo "unknown")
  _kern=$(uname -r 2>/dev/null || echo "unknown")
  _up=$(uptime 2>/dev/null | sed 's/^ *//' || echo "unknown")

  _mt=$(read_meminfo_kb MemTotal); is_uint "$_mt" || _mt=0
  _mf=$(read_meminfo_kb MemFree); is_uint "$_mf" || _mf=0
  _ma=$(read_meminfo_kb MemAvailable); is_uint "$_ma" || _ma=0
  _ca=$(read_meminfo_kb Cached); is_uint "$_ca" || _ca=0
  _st=$(read_meminfo_kb SwapTotal); is_uint "$_st" || _st=0
  _sf=$(read_meminfo_kb SwapFree); is_uint "$_sf" || _sf=0
  _su=$((_st - _sf))

  _zsize=$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0); is_uint "$_zsize" || _zsize=0
  _zalgos=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "")
  _zactive=$(extract_active_algo "$_zalgos" 2>/dev/null || echo "unknown")
  _zbdev=$(cat /sys/block/zram0/backing_dev 2>/dev/null || echo "none")
  _zorig=0; _zcompr=0; _zmem=0
  if [ -r /sys/block/zram0/mm_stat ]; then
    set -- $(cat /sys/block/zram0/mm_stat 2>/dev/null)
    _zorig=${1:-0}; _zcompr=${2:-0}; _zmem=${3:-0}
  fi
  is_uint "$_zorig" || _zorig=0
  is_uint "$_zcompr" || _zcompr=0
  is_uint "$_zmem" || _zmem=0

  _v_swap=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "$VM_SWAPPINESS")
  _v_vfs=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "$VM_VFS_CACHE_PRESSURE")
  _v_wm=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo "$VM_WATERMARK_SCALE_FACTOR")
  _v_dbr=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || echo "$VM_DIRTY_BACKGROUND_RATIO")
  _v_dr=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo "$VM_DIRTY_RATIO")
  _v_pc=$(cat /proc/sys/vm/page-cluster 2>/dev/null || echo "$VM_PAGE_CLUSTER")
  _mglru_en=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "N/A")
  _mglru_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null || echo "$MGLRU_MIN_TTL_MS")

  _thp_raw=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "")
  _thp_en=$(extract_bracketed_token "$_thp_raw" 2>/dev/null || echo "$THP_MODE")
  _thp_shmem_raw=$(cat /sys/kernel/mm/transparent_hugepage/shmem_enabled 2>/dev/null || echo "")
  _thp_shmem=$(extract_bracketed_token "$_thp_shmem_raw" 2>/dev/null || echo "never")

  _vs_lat=$(cat /proc/vendor_sched/latency_ns 2>/dev/null || echo "4166666")
  _vs_ramp=$(cat /proc/vendor_sched/adpf_rampup_multiplier 2>/dev/null || echo "2")
  _vs_ta_min=$(cat /proc/vendor_sched/groups/ta/uclamp_min 2>/dev/null || echo "1")
  _vs_bg_max=$(cat /proc/vendor_sched/groups/bg/uclamp_max 2>/dev/null || echo "512")

  _cpu_p0_up=$(cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/up_rate_limit_us 2>/dev/null || echo "0")
  _cpu_p0_dn=$(cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/down_rate_limit_us 2>/dev/null || echo "2000")
  _cpu_p0_resp=$(cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/response_time_ms 2>/dev/null || echo "4")

  _io_raw=$(cat /sys/block/sda/queue/scheduler 2>/dev/null || echo "")
  _io_sched=$(extract_bracketed_token "$_io_raw" 2>/dev/null || echo "$IO_SCHEDULER")
  _io_ra=$(cat /sys/block/sda/queue/read_ahead_kb 2>/dev/null || echo "$IO_READ_AHEAD_KB")
  _io_nr=$(cat /sys/block/sda/queue/nr_requests 2>/dev/null || echo "$IO_NR_REQUESTS")

  _gpu_pp_raw=$(cat /sys/devices/platform/1c500000.mali/power_policy 2>/dev/null || echo "")
  _gpu_pp=$(extract_bracketed_token "$_gpu_pp_raw" 2>/dev/null || echo "$GPU_POWER_POLICY")
  _gpu_gov=$(cat /sys/devices/platform/1c500000.mali/governor 2>/dev/null || echo "quickstep")
  _gpu_dvfs=$(cat /sys/devices/platform/1c500000.mali/dvfs_period 2>/dev/null || echo "$GPU_DVFS_PERIOD_MS")
  _gpu_min=$(cat /sys/devices/platform/1c500000.mali/scaling_min_freq 2>/dev/null || echo "151000")
  _gpu_max=$(cat /sys/devices/platform/1c500000.mali/scaling_max_freq 2>/dev/null || echo "848000")

  _sf_clear=$(getprop ro.surface_flinger.clear_slots_with_set_layer_buffer 2>/dev/null || echo "")
  [ -z "$_sf_clear" ] && _sf_clear="stock"
  _sf_bufs=$(getprop ro.surface_flinger.max_frame_buffer_acquired_buffers 2>/dev/null || echo "")

  _l_psi=$(getprop ro.lmk.use_psi 2>/dev/null || echo "$LMKD_USE_PSI")
  _l_part=$(getprop ro.lmk.psi_partial_stall_ms 2>/dev/null || echo "$LMKD_PSI_PARTIAL_MS")
  _l_comp=$(getprop ro.lmk.psi_complete_stall_ms 2>/dev/null || echo "$LMKD_PSI_COMPLETE_MS")
  _l_thr=$(getprop ro.lmk.thrashing_limit 2>/dev/null || echo "$LMKD_THRASHING_LIMIT")
  _l_slow=$(getprop ro.lmk.swap_free_low_percentage 2>/dev/null || echo "$LMKD_SWAP_FREE_LOW_PCT")
  _l_smax=$(getprop ro.lmk.swap_util_max 2>/dev/null || echo "$LMKD_SWAP_UTIL_MAX")

  _a_flt=$(getprop dalvik.vm.dex2oat-filter 2>/dev/null || echo "")
  [ -z "$_a_flt" ] && _a_flt="${ART_DEX2OAT_FILTER}"
  _a_img=$(getprop dalvik.vm.image-dex2oat-filter 2>/dev/null || echo "")
  [ -z "$_a_img" ] && _a_img="stock"
  _a_mad=$(getprop dalvik.vm.madvise.odexfile.size 2>/dev/null || echo "")
  [ -z "$_a_mad" ] && _a_mad=$(mb_to_bytes "$ART_MADVISE_MB")

  _recomp_run=false
  if [ -f "$LOCK_FILE" ]; then
    _lpid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if is_uint "$_lpid" && kill -0 "$_lpid" 2>/dev/null; then
      _recomp_run=true
    fi
  fi

  _wd_run=false
  watchdog_is_running && _wd_run=true

  printf '{"device":"%s","android":"%s","build":"%s","kernel":"%s","uptime":"%s",' \
    "$(json_escape "$_dev")" "$(json_escape "$_and")" "$(json_escape "$_bld")" "$(json_escape "$_kern")" "$(json_escape "$_up")"
  printf '"ram":{"total_kb":%s,"free_kb":%s,"available_kb":%s,"cached_kb":%s,"swap_total_kb":%s,"swap_free_kb":%s,"swap_used_kb":%s},' \
    "$_mt" "$_mf" "$_ma" "$_ca" "$_st" "$_sf" "$_su"
  printf '"zram":{"disksize_bytes":%s,"active_algo":"%s","avail_algos":"%s","backing_dev":"%s","orig_data_bytes":%s,"compr_data_bytes":%s,"mem_used_bytes":%s},' \
    "$_zsize" "$(json_escape "$_zactive")" "$(json_escape "$_zalgos")" "$(json_escape "$_zbdev")" "$_zorig" "$_zcompr" "$_zmem"
  printf '"vm":{"swappiness":"%s","vfs_cache_pressure":"%s","watermark_scale_factor":"%s","dirty_background_ratio":"%s","dirty_ratio":"%s","page_cluster":"%s","mglru_enabled":"%s","mglru_min_ttl_ms":"%s"},' \
    "$(json_escape "$_v_swap")" "$(json_escape "$_v_vfs")" "$(json_escape "$_v_wm")" "$(json_escape "$_v_dbr")" "$(json_escape "$_v_dr")" "$(json_escape "$_v_pc")" "$(json_escape "$_mglru_en")" "$(json_escape "$_mglru_ttl")"
  printf '"thp":{"enabled":"%s","shmem_enabled":"%s"},' \
    "$(json_escape "$_thp_en")" "$(json_escape "$_thp_shmem")"
  printf '"sched":{"profile":"%s","latency_ns":"%s","adpf_rampup":"%s","ta_uclamp_min":"%s","bg_uclamp_max":"%s"},' \
    "$(json_escape "$SCHED_PROFILE")" "$(json_escape "$_vs_lat")" "$(json_escape "$_vs_ramp")" "$(json_escape "$_vs_ta_min")" "$(json_escape "$_vs_bg_max")"
  printf '"cpufreq":{"profile":"%s","p0_up_us":"%s","p0_down_us":"%s","p0_resp_ms":"%s"},' \
    "$(json_escape "$CPU_RATE_PROFILE")" "$(json_escape "$_cpu_p0_up")" "$(json_escape "$_cpu_p0_dn")" "$(json_escape "$_cpu_p0_resp")"
  printf '"io":{"scheduler":"%s","read_ahead_kb":"%s","nr_requests":"%s"},' \
    "$(json_escape "$_io_sched")" "$(json_escape "$_io_ra")" "$(json_escape "$_io_nr")"
  printf '"gpu":{"power_policy":"%s","governor":"%s","dvfs_period_ms":"%s","min_freq":"%s","max_freq":"%s"},' \
    "$(json_escape "$_gpu_pp")" "$(json_escape "$_gpu_gov")" "$(json_escape "$_gpu_dvfs")" "$(json_escape "$_gpu_min")" "$(json_escape "$_gpu_max")"
  printf '"sf":{"mode":"%s","clear_slots":"%s","max_fb_buffers":"%s"},' \
    "$(json_escape "$SF_TUNING_MODE")" "$(json_escape "$_sf_clear")" "$(json_escape "$_sf_bufs")"
  printf '"lmkd":{"use_psi":"%s","psi_partial_ms":"%s","psi_complete_ms":"%s","thrashing_limit":"%s","swap_free_low_pct":"%s","swap_util_max":"%s"},' \
    "$(json_escape "$_l_psi")" "$(json_escape "$_l_part")" "$(json_escape "$_l_comp")" "$(json_escape "$_l_thr")" "$(json_escape "$_l_slow")" "$(json_escape "$_l_smax")"
  printf '"art":{"dex2oat_filter":"%s","image_filter":"%s","madvise_odex_bytes":"%s"},' \
    "$(json_escape "$_a_flt")" "$(json_escape "$_a_img")" "$(json_escape "$_a_mad")"
  printf '"recompile_running":%s,"watchdog_running":%s,' "$_recomp_run" "$_wd_run"
  printf '"config":{"CONFIG_SCHEMA_VERSION":%s,"ZRAM_SIZE_MB":%s,"ZRAM_ALGO":"%s","MMD_ZRAM_SYNC":%s,"ZRAM_RUNTIME_RESIZE":%s,"SWAPOFF_HEADROOM_PCT":%s,"VM_SWAPPINESS":%s,"VM_VFS_CACHE_PRESSURE":%s,"VM_WATERMARK_SCALE_FACTOR":%s,"VM_DIRTY_BACKGROUND_RATIO":%s,"VM_DIRTY_RATIO":%s,"VM_PAGE_CLUSTER":%s,"VM_STAT_INTERVAL":%s,"MGLRU_ENABLED":%s,"MGLRU_MIN_TTL_MS":%s,"THP_MODE":"%s","SCHED_PROFILE":"%s","CPU_RATE_PROFILE":"%s","IO_SCHEDULER":"%s","IO_READ_AHEAD_KB":%s,"IO_NR_REQUESTS":%s,"GPU_POWER_POLICY":"%s","GPU_DVFS_PERIOD_MS":%s,"SF_TUNING_MODE":"%s","WATCHDOG_ENABLED":%s,"ART_DEX2OAT_FILTER":"%s","ART_MADVISE_MB":%s,"ART_BOOT_PROPS":%s,"LMKD_USE_PSI":"%s","LMKD_PSI_PARTIAL_MS":%s,"LMKD_PSI_COMPLETE_MS":%s,"LMKD_THRASHING_LIMIT":%s,"LMKD_THRASHING_DECAY":%s,"LMKD_SWAP_FREE_LOW_PCT":%s,"LMKD_SWAP_UTIL_MAX":%s,"LMKD_KILL_HEAVIEST":"%s","LMKD_KILL_TIMEOUT_MS":%s,"LMKD_DOWNGRADE_PRESSURE":%s,"AUTO_BOOT_DIAG":%s,"ACTION_MODE":"%s","RECOMPILE_SCOPE":"%s"}}\n' \
    "$CONFIG_SCHEMA_VERSION" "$ZRAM_SIZE_MB" "$ZRAM_ALGO" "$MMD_ZRAM_SYNC" "$ZRAM_RUNTIME_RESIZE" "$SWAPOFF_HEADROOM_PCT" \
    "$VM_SWAPPINESS" "$VM_VFS_CACHE_PRESSURE" "$VM_WATERMARK_SCALE_FACTOR" "$VM_DIRTY_BACKGROUND_RATIO" "$VM_DIRTY_RATIO" "$VM_PAGE_CLUSTER" "$VM_STAT_INTERVAL" "$MGLRU_ENABLED" "$MGLRU_MIN_TTL_MS" \
    "$THP_MODE" "$SCHED_PROFILE" "$CPU_RATE_PROFILE" "$IO_SCHEDULER" "$IO_READ_AHEAD_KB" "$IO_NR_REQUESTS" "$GPU_POWER_POLICY" "$GPU_DVFS_PERIOD_MS" "$SF_TUNING_MODE" "$WATCHDOG_ENABLED" \
    "$ART_DEX2OAT_FILTER" "$ART_MADVISE_MB" "$ART_BOOT_PROPS" \
    "$LMKD_USE_PSI" "$LMKD_PSI_PARTIAL_MS" "$LMKD_PSI_COMPLETE_MS" "$LMKD_THRASHING_LIMIT" "$LMKD_THRASHING_DECAY" "$LMKD_SWAP_FREE_LOW_PCT" "$LMKD_SWAP_UTIL_MAX" "$LMKD_KILL_HEAVIEST" "$LMKD_KILL_TIMEOUT_MS" "$LMKD_DOWNGRADE_PRESSURE" \
    "$AUTO_BOOT_DIAG" "$ACTION_MODE" "$RECOMPILE_SCOPE"
}

cmd_compact() {
  before_avail=$(read_meminfo_kb MemAvailable)
  if [ -w /sys/block/zram0/compact ]; then
    echo 1 > /sys/block/zram0/compact 2>/dev/null || true
  fi
  setprop lmkd.reinit 1 2>/dev/null || true
  after_avail=$(read_meminfo_kb MemAvailable)
  log_msg "zRAM compact + lmkd.reinit done (MemAvailable: $(( ${before_avail:-0} / 1024 )) MB -> $(( ${after_avail:-0} / 1024 )) MB)."
}

read_soc_temp_c() {
  _max_c=0
  for _tz in /sys/class/thermal/thermal_zone*; do
    [ -r "$_tz/type" ] || continue
    _t=$(cat "$_tz/type" 2>/dev/null || true)
    case "$_t" in
      BIG|MID)
        _raw=$(cat "$_tz/temp" 2>/dev/null || echo "")
        if [ -n "$_raw" ]; then
          _c=$(awk -v r="$_raw" 'BEGIN {
            r += 0;
            if (r >= 1000) printf "%.0f\n", int(r / 1000);
            else if (r > 0) printf "%.0f\n", int(r);
            else print 0;
          }' 2>/dev/null || echo 0)
          if is_uint "$_c" && [ "$_c" -gt "$_max_c" ]; then
            _max_c=$_c
          fi
        fi
        ;;
    esac
  done
  echo "$_max_c"
}

read_uptime_int() {
  if [ -r /proc/uptime ]; then
    awk '{printf "%.0f\n", int($1)}' /proc/uptime 2>/dev/null || echo 9999
  else
    echo 9999
  fi
}

cmd_recompile() {
  load_config
  _filter="$ART_DEX2OAT_FILTER"
  _scope="$RECOMPILE_SCOPE"
  _do_reset=0
  _force=0

  for _arg in "$@"; do
    case "$_arg" in
      --filter=*) _filter=${_arg#--filter=} ;;
      --scope=*)  _scope=${_arg#--scope=} ;;
      --reset)    _do_reset=1 ;;
      --force)    _force=1 ;;
      *)          echo "Unknown recompile option: $_arg" >&2; return 1 ;;
    esac
  done

  if ! validate_config_kv ART_DEX2OAT_FILTER "$_filter"; then
    echo "Invalid filter: $_filter" >&2
    return 1
  fi
  if ! validate_config_kv RECOMPILE_SCOPE "$_scope"; then
    echo "Invalid scope: $_scope" >&2
    return 1
  fi

  if [ "$_force" -eq 0 ] && [ "${CAVENTUS_SKIP_THERMAL_GUARD:-0}" != "1" ]; then
    _up_s=$(read_uptime_int)
    if is_uint "$_up_s" && [ "$_up_s" -lt 120 ]; then
      _tg_msg="THERMAL_GUARD: Uptime ${_up_s}s < 120s (baru boot). Tunggu minimal 2 menit pasca-boot sebelum ART recompile, atau gunakan --force."
      log_msg "$_tg_msg"
      echo "$_tg_msg" >&2
      return 2
    fi
    _soc_c=$(read_soc_temp_c)
    if is_uint "$_soc_c" && [ "$_soc_c" -ge 70 ]; then
      _tg_msg="THERMAL_GUARD: Suhu SoC terlalu tinggi (${_soc_c}C >= 70C). Tunggu HP dingin di bawah 70C sebelum ART recompile, atau gunakan --force."
      log_msg "$_tg_msg"
      echo "$_tg_msg" >&2
      return 2
    fi
  fi

  _ldir=$(dirname "$LOCK_FILE")
  mkdir -p "$_ldir" 2>/dev/null || true
  if [ -f "$LOCK_FILE" ]; then
    _old_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if is_uint "$_old_pid" && kill -0 "$_old_pid" 2>/dev/null; then
      echo "Recompile already running (PID $_old_pid)." >&2
      return 1
    fi
    rm -f "$LOCK_FILE"
  fi
  echo "$$" > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

  _start_ts=$(date +%s 2>/dev/null || echo 0)
  log_msg "Starting forced ART recompile: filter=$_filter, scope=$_scope, reset=$_do_reset"

  _pm_flag=""
  [ "$_scope" = "third_party" ] && _pm_flag="-3"

  _pkgs=$(pm list packages $_pm_flag 2>/dev/null | sed 's/^package://' | sort)
  if [ -z "$_pkgs" ]; then
    echo "Package list empty; running bulk cmd package compile -m $_filter -f -a ..."
    if cmd package compile -m "$_filter" -f -a; then
      log_msg "Bulk ART recompile (-m $_filter -f -a) completed."
      return 0
    fi
    log_msg "Bulk ART recompile failed."
    return 1
  fi

  _total=$(printf '%s\n' "$_pkgs" | wc -l | tr -d ' ')
  echo "TOTAL=$_total"
  _i=0
  _ok=0
  _skip=0

  for _pkg in $_pkgs; do
    _i=$((_i + 1))
    if [ "$_force" -eq 0 ] && [ "${CAVENTUS_SKIP_THERMAL_GUARD:-0}" != "1" ] && [ $((_i % 15)) -eq 0 ]; then
      _soc_c=$(read_soc_temp_c)
      if is_uint "$_soc_c" && [ "$_soc_c" -ge 78 ]; then
        echo "[thermal-cooldown] SoC=${_soc_c}C >= 78C — pausing 8s..."
        sleep 8
      fi
    fi
    if [ "$_do_reset" -eq 1 ]; then
      cmd package compile --reset "$_pkg" >/dev/null 2>&1 || true
    fi
    if cmd package compile -m "$_filter" -f "$_pkg" >/dev/null 2>&1; then
      _ok=$((_ok + 1))
      echo "[$_i/$_total] ok: $_pkg"
    else
      _skip=$((_skip + 1))
      echo "[$_i/$_total] skip: $_pkg"
    fi
  done

  _end_ts=$(date +%s 2>/dev/null || echo 0)
  _elapsed=$((_end_ts - _start_ts))
  log_msg "ART recompile finished: filter=$_filter ok=$_ok skip=$_skip total=$_total elapsed=${_elapsed}s"
  return 0
}

cmd_logs() {
  _n="${1:-120}"
  is_uint "$_n" || _n=120
  if [ -f "$LOG_FILE" ]; then
    tail -n "$_n" "$LOG_FILE"
  else
    echo "No logs yet at $LOG_FILE"
  fi
}

cmd_clear_logs() {
  _ldir=$(dirname "$LOG_FILE")
  mkdir -p "$_ldir" 2>/dev/null || true
  : > "$LOG_FILE"
  log_msg "Logs cleared."
}

if [ "${CAVENTUS_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

cmd="${1:-status}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
  apply)
    _apply_t0=$(date +%s 2>/dev/null || echo 0)
    load_config
    migrate_config_if_needed
    apply_live_props
    _z_t0=$(date +%s 2>/dev/null || echo 0)
    apply_zram
    _z_t1=$(date +%s 2>/dev/null || echo 0)
    apply_vm
    apply_thp
    apply_sched
    apply_cpufreq
    apply_io
    apply_gpu
    apply_lmkd
    if [ "${CAVENTUS_NO_WATCHDOG:-0}" != "1" ]; then
      if [ "$WATCHDOG_ENABLED" = "1" ]; then
        cmd_watchdog_start
      else
        cmd_watchdog_stop
      fi
    fi
    _apply_t1=$(date +%s 2>/dev/null || echo 0)
    log_msg "Caventus apply finished in $((_apply_t1 - _apply_t0))s (zram=$((_z_t1 - _z_t0))s, sched=$SCHED_PROFILE, cpu=$CPU_RATE_PROFILE)."
    ;;
  save-config)
    cmd_save_config "$@"
    ;;
  migrate-config)
    cmd_migrate_config
    ;;
  init-defaults)
    cmd_init_defaults
    ;;
  reset-defaults)
    cmd_reset_defaults
    ;;
  status)
    cmd_status
    ;;
  status-json)
    cmd_status_json
    ;;
  compact)
    cmd_compact
    ;;
  recompile)
    cmd_recompile "$@"
    ;;
  logs)
    cmd_logs "$@"
    ;;
  clear-logs)
    cmd_clear_logs
    ;;
  diag-capture)
    exec sh "$DIAG_BIN" capture "$@"
    ;;
  diag-boot-snapshot)
    exec sh "$DIAG_BIN" boot-snapshot "$@"
    ;;
  diag-list)
    exec sh "$DIAG_BIN" list "$@"
    ;;
  diag-read)
    exec sh "$DIAG_BIN" read "$@"
    ;;
  diag-clear)
    exec sh "$DIAG_BIN" clear "$@"
    ;;
  watchdog-start)
    cmd_watchdog_start
    ;;
  watchdog-stop)
    cmd_watchdog_stop
    ;;
  watchdog-loop)
    cmd_watchdog_loop
    ;;
  help|-h|--help)
    echo "Usage: $0 {apply|save-config KEY=VAL...|migrate-config|init-defaults|reset-defaults|status|status-json|compact|recompile [--filter=speed-profile] [--scope=all|third_party] [--reset] [--force]|logs [N]|clear-logs|diag-capture|diag-boot-snapshot|diag-list|diag-read|diag-clear|watchdog-start|watchdog-stop|help}"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
