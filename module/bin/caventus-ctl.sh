#!/system/bin/sh
# Caventus runtime controller for Pixel 6 (oriole / gs101)

CONFIG_ENV="${CAVENTUS_CONFIG_ENV:-/data/adb/caventus/config.env}"
LOG_FILE="${CAVENTUS_LOG_FILE:-/data/adb/caventus/caventus.log}"

# Defaults (can be overridden in /data/adb/caventus/config.env)
ZRAM_SIZE_MB=4096
ZRAM_ALGO=zstd
VM_SWAPPINESS=80
VM_VFS_CACHE_PRESSURE=100
VM_WATERMARK_SCALE_FACTOR=60
VM_DIRTY_BACKGROUND_RATIO=5
VM_DIRTY_RATIO=15
VM_PAGE_CLUSTER=0
VM_STAT_INTERVAL=10
MGLRU_MIN_TTL_MS=1000
SWAPOFF_HEADROOM_PCT=80

if [ -f "$CONFIG_ENV" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_ENV"
fi

log_msg() {
  ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "boot")
  line="[$ts] $*"
  echo "$line"
  log_dir=$(dirname "$LOG_FILE")
  [ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null || true
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

resolve_cmd() {
  name="$1"
  if [ -x "/system/bin/$name" ]; then
    echo "/system/bin/$name"
    return 0
  fi
  found=$(command -v "$name" 2>/dev/null || true)
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi
  if command -v toybox >/dev/null 2>&1; then
    echo "toybox $name"
    return 0
  fi
  return 1
}

write_node() {
  path="$1"
  val="$2"
  if [ -w "$path" ]; then
    printf '%s' "$val" > "$path" 2>/dev/null || return 1
    return 0
  fi
  return 1
}

# Pure helper: pick requested algo if supported, else fallback zstd -> lz4 -> lzo-rle -> lzo
pick_zram_algo() {
  requested="$1"
  avail="$2"
  for candidate in "$requested" zstd lz4 lzo-rle lzo; do
    [ -z "$candidate" ] && continue
    for tok in $avail; do
      clean=$(printf '%s' "$tok" | tr -d '[]')
      if [ "$clean" = "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done
  return 1
}

# Pure helper: returns 0 if SwapUsed * 100 < MemAvailable * headroom_pct
can_safely_swapoff() {
  swap_used_kb="$1"
  mem_avail_kb="$2"
  headroom_pct="${3:-80}"
  [ -z "$swap_used_kb" ] && swap_used_kb=0
  [ -z "$mem_avail_kb" ] && mem_avail_kb=0
  if [ "$swap_used_kb" -le 0 ]; then
    return 0
  fi
  if [ "$mem_avail_kb" -le 0 ]; then
    return 1
  fi
  lhs=$((swap_used_kb * 100))
  rhs=$((mem_avail_kb * headroom_pct))
  [ "$lhs" -lt "$rhs" ]
}

extract_active_algo() {
  avail="$1"
  for tok in $avail; do
    case "$tok" in
      \[*\])
        printf '%s\n' "$tok" | tr -d '[]'
        return 0
        ;;
    esac
  done
  return 1
}

read_meminfo_kb() {
  key="$1"
  awk -v k="${key}:" '$1 == k {print $2; exit}' /proc/meminfo 2>/dev/null
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

  target_bytes=$((ZRAM_SIZE_MB * 1048576))
  cur_algo=$(extract_active_algo "$avail_algos" || true)
  cur_disksize=$(cat "$zram_sys/disksize" 2>/dev/null || echo 0)
  swap_active=0
  grep -q "zram0" /proc/swaps 2>/dev/null && swap_active=1

  if [ "$cur_algo" = "$target_algo" ] && [ "$cur_disksize" = "$target_bytes" ] && [ "$swap_active" -eq 1 ]; then
    log_msg "zram0 already configured (${ZRAM_SIZE_MB} MB, $target_algo)."
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
    log_msg "ABORT zram0 resize: SwapUsed=${swap_used}kB too high vs MemAvailable=${mem_avail}kB (headroom ${SWAPOFF_HEADROOM_PCT}%). Keeping current swap safe."
    return 0
  fi

  old_bdev=""
  if [ -r "$zram_sys/backing_dev" ]; then
    old_bdev=$(cat "$zram_sys/backing_dev" 2>/dev/null || true)
    [ "$old_bdev" = "none" ] && old_bdev=""
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
    write_node "$zram_sys/backing_dev" "$old_bdev" || log_msg "Note: backing_dev '$old_bdev' could not be re-attached."
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
    [ "$cur_disksize" -gt 0 ] 2>/dev/null && write_node "$zram_sys/disksize" "$cur_disksize" || true
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
    cur_mglru=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "0")
    case "$cur_mglru" in
      0|0x0000|n|N) write_node /sys/kernel/mm/lru_gen/enabled "y" || true ;;
    esac
  fi
  if [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ]; then
    write_node /sys/kernel/mm/lru_gen/min_ttl_ms "$MGLRU_MIN_TTL_MS" || true
  fi

  log_msg "VM sysctls applied (swappiness=$VM_SWAPPINESS, watermark_scale=$VM_WATERMARK_SCALE_FACTOR, dirty=${VM_DIRTY_BACKGROUND_RATIO}/${VM_DIRTY_RATIO})."
}

apply_lmkd() {
  setprop lmkd.reinit 1 2>/dev/null || true
  if command -v lmkd >/dev/null 2>&1; then
    lmkd --reinit 2>/dev/null || true
  fi
  log_msg "LMKD reinitialized (use_psi=$(getprop ro.lmk.use_psi), partial_ms=$(getprop ro.lmk.psi_partial_stall_ms), thrash=$(getprop ro.lmk.thrashing_limit), swap_low=$(getprop ro.lmk.swap_free_low_percentage)%)."
}

cmd_status() {
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

  echo "=== Caventus Status (oriole) ==="
  echo "RAM        : MemTotal=$(( ${mem_total:-0} / 1024 )) MB | MemAvailable=$(( ${mem_avail:-0} / 1024 )) MB"
  echo "Swap       : Used=$(( swap_used / 1024 )) MB / Total=$(( ${swap_total:-0} / 1024 )) MB"
  echo "zRAM       : $(( zram_size / 1048576 )) MB | algo: $zram_algo | backing_dev: $zram_bdev"
  echo "zRAM stat  : $zram_stat"
  echo "VM         : swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null) | wm_scale=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null) | vfs_cache=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null) | page_cluster=$(cat /proc/sys/vm/page-cluster 2>/dev/null)"
  echo "MGLRU      : enabled=$mglru_en | min_ttl_ms=$mglru_ttl"
  echo "LMKD       : use_psi=$(getprop ro.lmk.use_psi) | partial_ms=$(getprop ro.lmk.psi_partial_stall_ms) | complete_ms=$(getprop ro.lmk.psi_complete_stall_ms) | thrashing=$(getprop ro.lmk.thrashing_limit) | swap_low=$(getprop ro.lmk.swap_free_low_percentage)%"
  echo "ART        : dex2oat-filter=$(getprop dalvik.vm.dex2oat-filter) | image-filter=$(getprop dalvik.vm.image-dex2oat-filter)"
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

cmd_recompile() {
  echo "Recompiling installed packages with speed-profile (this may take several minutes; keep device cool/charging)..."
  log_msg "Starting manual ART recompile (speed-profile)."
  if cmd package compile -m speed-profile -a; then
    log_msg "ART speed-profile recompile completed."
  else
    log_msg "ART speed-profile recompile returned non-zero status."
    return 1
  fi
}

if [ "${CAVENTUS_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

case "${1:-status}" in
  apply)
    apply_zram
    apply_vm
    apply_lmkd
    ;;
  status)
    cmd_status
    ;;
  compact)
    cmd_compact
    ;;
  recompile)
    cmd_recompile
    ;;
  help|-h|--help)
    echo "Usage: $0 {apply|status|compact|recompile|help}"
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Usage: $0 {apply|status|compact|recompile|help}" >&2
    exit 1
    ;;
esac
