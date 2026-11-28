#!/system/bin/sh
# Caventus forensic diagnostic log capturer for Pixel 6 (oriole / GS101)

PATH="/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:$PATH"
export PATH

if [ -n "${CAVENTUS_MODDIR:-}" ]; then
  MODDIR="$CAVENTUS_MODDIR"
else
  MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi

CONFIG_ENV="${CAVENTUS_CONFIG_ENV:-/data/adb/caventus/config.env}"
LOG_FILE="${CAVENTUS_LOG_FILE:-/data/adb/caventus/caventus.log}"
DIAG_DIR="${CAVENTUS_DIAG_DIR:-/data/adb/caventus/diag}"
RT_DIR="${CAVENTUS_RT_DIR:-/data/adb/caventus/realtime}"
RT_PID_FILE="${CAVENTUS_RT_PID_FILE:-/data/adb/caventus/diag-daemon.pid}"
EXPORT_DIR="${CAVENTUS_EXPORT_DIR:-/sdcard/Download/Caventus-Logs}"
PROJECT_EXPORT_DIR="${CAVENTUS_PROJECT_EXPORT_DIR:-/sdcard/Project}"
BOOT_LOG="$DIAG_DIR/last-boot.log"

RT_META="$RT_DIR/session.meta"
RT_METRICS="$RT_DIR/metrics.tsv"
RT_ANOM="$RT_DIR/anomalies.log"
RT_EVENTS="$RT_DIR/events.log"
RT_STATUS="$RT_DIR/daemon.status"
RT_STATE_DM="$RT_DIR/.last_dmesg_ts"
RT_STATE_LC="$RT_DIR/.last_lc_line"

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

count_matches() {
  _cm_pat="$1"
  _cm_file="$2"
  if [ ! -r "$_cm_file" ]; then
    echo 0
    return 0
  fi
  _cm_res=$(grep -ciE "$_cm_pat" "$_cm_file" 2>/dev/null)
  _cm_res=$(printf '%s' "$_cm_res" | tr -cd '0-9')
  echo "${_cm_res:-0}"
}

pct_of() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (b+0 > 0) printf "%.0f\n", int((a * 100) / b); else print 0 }'
}

read_first_line() {
  if [ -r "$1" ]; then
    cat "$1" 2>/dev/null | head -n 1 | tr -d '\r'
  else
    echo "N/A"
  fi
}

read_meminfo_kb() {
  _k="$1"
  awk -v k="${_k}:" '$1 == k {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

read_vmstat_val() {
  _k="$1"
  awk -v k="$_k" '$1 == k {print $2; exit}' /proc/vmstat 2>/dev/null || echo 0
}

read_uptime_s() {
  awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null || echo 0
}

extract_psi_avg10() {
  _pfile="$1"
  if [ -r "$_pfile" ]; then
    awk '/^some / {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=","",$i); print $i; exit}}' "$_pfile" 2>/dev/null || echo "0.00"
  else
    echo "N/A"
  fi
}

read_thermal_c() {
  _target="$1"
  for _tz in /sys/class/thermal/thermal_zone*; do
    [ -r "$_tz/type" ] || continue
    _t=$(cat "$_tz/type" 2>/dev/null || true)
    if [ "$_t" = "$_target" ]; then
      _raw=$(cat "$_tz/temp" 2>/dev/null || echo "")
      if [ -n "$_raw" ]; then
        case "$_raw" in
          ''|*[!0-9-]*) echo "$_raw"; return 0 ;;
          *)
            if [ "$_raw" -ge 1000 ] 2>/dev/null || [ "$_raw" -le -1000 ] 2>/dev/null; then
              awk -v v="$_raw" 'BEGIN {printf "%.1f", v/1000}'
            else
              echo "$_raw"
            fi
            return 0
            ;;
        esac
      fi
    fi
  done
  echo "N/A"
}

read_cool_state() {
  _target="$1"
  for _cd in /sys/class/thermal/cooling_device*; do
    [ -r "$_cd/type" ] || continue
    _t=$(cat "$_cd/type" 2>/dev/null || true)
    if [ "$_t" = "$_target" ]; then
      _cur=$(cat "$_cd/cur_state" 2>/dev/null || echo "?")
      _max=$(cat "$_cd/max_state" 2>/dev/null || echo "?")
      echo "${_cur}/${_max}"
      return 0
    fi
  done
  echo "N/A"
}

read_policy_mhz() {
  _pol="$1"
  _f=$(cat "/sys/devices/system/cpu/cpufreq/${_pol}/scaling_cur_freq" 2>/dev/null || echo 0)
  if is_uint "$_f" && [ "$_f" -gt 0 ]; then
    echo $((_f / 1000))
  else
    echo 0
  fi
}

safe_getprop() {
  if command -v getprop >/dev/null 2>&1; then
    getprop "$1" 2>/dev/null || true
  fi
}

sanitize_tag() {
  _in="$1"
  _clean=$(printf '%s' "$_in" | sed 's/[^A-Za-z0-9_-]/_/g' | cut -c1-24)
  [ -z "$_clean" ] && _clean="manual"
  printf '%s' "$_clean"
}

cmd_boot_snapshot() {
  _phase="${1:-post}"
  mkdir -p "$DIAG_DIR" 2>/dev/null || true
  if [ "$_phase" = "pre" ]; then
    : > "$BOOT_LOG"
  fi
  _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
  _up=$(cat /proc/uptime 2>/dev/null || echo "unknown")
  _ma=$(read_meminfo_kb MemAvailable)
  _st=$(read_meminfo_kb SwapTotal)
  _sf=$(read_meminfo_kb SwapFree)
  {
    echo "=== BOOT SNAPSHOT ($_phase) @ $_ts ==="
    echo "uptime: $_up"
    echo "mem: MemAvailable_kB=$_ma SwapTotal_kB=$_st SwapFree_kB=$_sf"
    echo "zram0: initstate=$(read_first_line /sys/block/zram0/initstate) disksize=$(read_first_line /sys/block/zram0/disksize) algo=$(read_first_line /sys/block/zram0/comp_algorithm) bdev=$(read_first_line /sys/block/zram0/backing_dev)"
    echo "zram0_mm_stat: $(read_first_line /sys/block/zram0/mm_stat)"
    echo "thermals_C: BIG=$(read_thermal_c BIG) MID=$(read_thermal_c MID) LITTLE=$(read_thermal_c LITTLE) G3D=$(read_thermal_c G3D) battery=$(read_thermal_c battery) quiet=$(read_thermal_c quiet_therm)"
    echo "cooling: cpufreq0=$(read_cool_state thermal-cpufreq-0) cpufreq1=$(read_cool_state thermal-cpufreq-1) cpufreq2=$(read_cool_state thermal-cpufreq-2) gpufreq0=$(read_cool_state thermal-gpufreq-0)"
    for _p in policy0 policy4 policy6; do
      _pd="/sys/devices/system/cpu/cpufreq/$_p"
      echo "cpufreq_$_p: cur=$(read_first_line "$_pd/scaling_cur_freq") max=$(read_first_line "$_pd/scaling_max_freq") resp=$(read_first_line "$_pd/sched_pixel/response_time_ms") up=$(read_first_line "$_pd/sched_pixel/up_rate_limit_us") down=$(read_first_line "$_pd/sched_pixel/down_rate_limit_us")"
    done
    echo "vendor_sched: latency_ns=$(read_first_line /proc/vendor_sched/latency_ns) reduce_prefer_idle=$(read_first_line /proc/vendor_sched/reduce_prefer_idle) sys_prefer_idle=$(read_first_line /proc/vendor_sched/groups/sys/prefer_idle)"
    echo "sda_queue: sched=$(read_first_line /sys/block/sda/queue/scheduler) ra=$(read_first_line /sys/block/sda/queue/read_ahead_kb) nr=$(read_first_line /sys/block/sda/queue/nr_requests)"
    echo "psi_cpu: $(read_first_line /proc/pressure/cpu)"
    echo "psi_io: $(read_first_line /proc/pressure/io)"
    echo "psi_mem: $(read_first_line /proc/pressure/memory)"
    echo ""
  } >> "$BOOT_LOG" 2>/dev/null || true
}

prune_old_diags() {
  _idx=0
  for _f in $(ls -1t "$DIAG_DIR"/caventus-diag-*.log 2>/dev/null || true); do
    [ -f "$_f" ] || continue
    _idx=$((_idx + 1))
    if [ "$_idx" -gt 10 ]; then
      rm -f "$_f" 2>/dev/null || true
    fi
  done
}

top_proc_line() {
  _tp=$(top -b -n 1 2>/dev/null | awk 'NR>4 && $1 ~ /^[0-9]+$/ {print $NF "(" $9 "%)"; exit}' 2>/dev/null || true)
  if [ -z "$_tp" ]; then
    _tp=$(ps -A -o PID,RSS,NAME 2>/dev/null | awk 'NR>1 {print}' | sort -k2 -rn 2>/dev/null | head -n 1 | awk '{print $3 "(" int($2/1024) "M)"}' 2>/dev/null || true)
  fi
  [ -z "$_tp" ] && _tp="unknown"
  printf '%s' "$_tp"
}

capture_dmesg_raw() {
  _cd_out="$1"
  _cd_err="$2"
  _DM_USED="none"
  _DM_RC=127
  : > "$_cd_out"
  : > "$_cd_err"
  if [ -x /system/bin/dmesg ]; then
    _DM_USED="/system/bin/dmesg"
    /system/bin/dmesg > "$_cd_out" 2>"$_cd_err"
    _DM_RC=$?
  fi
  if [ ! -s "$_cd_out" ] && command -v toybox >/dev/null 2>&1; then
    _DM_USED="toybox dmesg"
    toybox dmesg > "$_cd_out" 2>>"$_cd_err"
    _DM_RC=$?
  fi
  for _bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    if [ ! -s "$_cd_out" ] && [ -x "$_bb" ]; then
      _DM_USED="$_bb dmesg"
      "$_bb" dmesg > "$_cd_out" 2>>"$_cd_err"
      _DM_RC=$?
    fi
  done
  if [ ! -s "$_cd_out" ] && command -v dmesg >/dev/null 2>&1; then
    _DM_USED=$(command -v dmesg 2>/dev/null || echo dmesg)
    "$_DM_USED" > "$_cd_out" 2>>"$_cd_err"
    _DM_RC=$?
  fi
}

cmd_capture() {
  _dur=15
  _iv=3
  _export=1
  _tag="manual"

  for _arg in "$@"; do
    case "$_arg" in
      --duration=*) _dur=${_arg#--duration=} ;;
      --interval=*) _iv=${_arg#--interval=} ;;
      --export=*)   _export=${_arg#--export=} ;;
      --tag=*)      _tag=${_arg#--tag=} ;;
      *) echo "Unknown capture option: $_arg" >&2; return 1 ;;
    esac
  done

  if ! in_range "$_dur" 0 120; then
    echo "Invalid duration (expected 0..120): $_dur" >&2
    return 1
  fi
  if ! in_range "$_iv" 1 10; then
    echo "Invalid interval (expected 1..10): $_iv" >&2
    return 1
  fi
  case "$_export" in
    0|1) ;;
    *) echo "Invalid export flag (expected 0|1): $_export" >&2; return 1 ;;
  esac
  _tag=$(sanitize_tag "$_tag")

  mkdir -p "$DIAG_DIR" 2>/dev/null || true
  _stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo "00000000-000000")
  _bname="caventus-diag-${_stamp}-${_tag}.log"
  _out="$DIAG_DIR/$_bname"

  echo "STAGE=1/13 Collecting metadata, config & module inventory"
  {
    echo "######################################################################"
    echo "# CAVENTUS FORENSIC DIAGNOSTIC REPORT"
    echo "# File: $_bname"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown)"
    echo "######################################################################"
    echo ""
    echo "===== SECTION 01: METADATA, CONFIG & KSU MODULE INVENTORY ====="
    echo "[module.prop]"
    if [ -r "$MODDIR/module.prop" ]; then
      cat "$MODDIR/module.prop" 2>/dev/null || true
    else
      echo "(missing $MODDIR/module.prop)"
    fi
    echo ""
    echo "[device]"
    echo "device=$(safe_getprop ro.product.device)"
    echo "android=$(safe_getprop ro.build.version.release)"
    echo "build=$(safe_getprop ro.build.display.id)"
    echo "kernel=$(uname -a 2>/dev/null || echo unknown)"
    echo "uptime=$(cat /proc/uptime 2>/dev/null || echo unknown)"
    echo "loadavg=$(cat /proc/loadavg 2>/dev/null || echo unknown)"
    echo ""
    echo "[config.env]"
    if [ -r "$CONFIG_ENV" ]; then
      cat "$CONFIG_ENV" 2>/dev/null || true
    else
      echo "(missing $CONFIG_ENV)"
    fi
    echo ""
    echo "[module system.prop]"
    if [ -r "$MODDIR/system.prop" ]; then
      cat "$MODDIR/system.prop" 2>/dev/null || true
    else
      echo "(missing $MODDIR/system.prop)"
    fi
    echo ""
    echo "[ksu modules inventory]"
    if [ -d /data/adb/modules ]; then
      for _md in /data/adb/modules/*; do
        [ -d "$_md" ] || continue
        _mstate="enabled"
        [ -f "$_md/disable" ] && _mstate="disabled"
        [ -f "$_md/remove" ] && _mstate="remove"
        _mver=$(grep -m1 '^version=' "$_md/module.prop" 2>/dev/null | cut -d= -f2- || echo "?")
        _mname=$(grep -m1 '^name=' "$_md/module.prop" 2>/dev/null | cut -d= -f2- || basename "$_md")
        echo "  $(basename "$_md") | $_mstate | ver=$_mver | $_mname"
      done
    else
      echo "(no /data/adb/modules directory)"
    fi
    echo ""
  } > "$_out"

  echo "STAGE=2/13 Reading Caventus boot & runtime logs"
  {
    echo "===== SECTION 02: CAVENTUS BOOT & RUNTIME LOGS ====="
    echo "[caventus.log tail 200]"
    if [ -r "$LOG_FILE" ]; then
      tail -n 200 "$LOG_FILE" 2>/dev/null || true
    else
      echo "(no $LOG_FILE)"
    fi
    echo ""
    echo "[last-boot.log]"
    if [ -r "$BOOT_LOG" ]; then
      cat "$BOOT_LOG" 2>/dev/null || true
    else
      echo "(no $BOOT_LOG)"
    fi
    echo ""
  } >> "$_out"

  echo "STAGE=3/13 Inspecting Android ART, mmd, LMKD & SurfaceFlinger properties"
  {
    echo "===== SECTION 03: ANDROID PROPERTIES (ART / MMD / LMKD / SF / SERVICES) ====="
    if command -v getprop >/dev/null 2>&1; then
      getprop 2>/dev/null | grep -E '\[(dalvik\.vm\.|pm\.dexopt\.|mmd\.|ro\.lmk\.|persist\.device_config\.lmkd_native\.|ro\.surface_flinger\.|sys\.boot_completed|init\.svc\.mmd|init\.svc\.lmkd|init\.svc\.odsign|init\.svc\.artd|init\.svc\.thermal)' | sort || true
    else
      echo "(getprop unavailable in sandbox)"
    fi
    echo ""
  } >> "$_out"

  echo "STAGE=4/13 Reading Memory, zRAM, VM, MGLRU, THP & vmstat"
  {
    echo "===== SECTION 04: MEMORY, ZRAM, VM, MGLRU, THP & VMSTAT ====="
    echo "[/proc/meminfo top 35]"
    head -n 35 /proc/meminfo 2>/dev/null || true
    echo ""
    echo "[/proc/swaps]"
    cat /proc/swaps 2>/dev/null || true
    echo ""
    echo "[/sys/block/zram0]"
    for _zf in disksize comp_algorithm backing_dev mm_stat bd_stat io_stat debug_stat writeback_limit writeback_limit_enable initstate max_comp_streams; do
      [ -r "/sys/block/zram0/$_zf" ] && echo "zram0/$_zf: $(cat "/sys/block/zram0/$_zf" 2>/dev/null | tr '\n' ' ')"
    done
    echo ""
    echo "[/proc/sys/vm]"
    for _vf in swappiness page-cluster vfs_cache_pressure watermark_scale_factor watermark_boost_factor min_free_kbytes dirty_background_ratio dirty_ratio stat_interval compaction_proactiveness; do
      [ -r "/proc/sys/vm/$_vf" ] && echo "vm/$_vf: $(read_first_line "/proc/sys/vm/$_vf")"
    done
    echo ""
    echo "[MGLRU & THP]"
    for _mf in /sys/kernel/mm/lru_gen/enabled /sys/kernel/mm/lru_gen/min_ttl_ms /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/shmem_enabled /sys/kernel/mm/transparent_hugepage/defrag; do
      [ -r "$_mf" ] && echo "$_mf: $(read_first_line "$_mf")"
    done
    echo ""
    echo "[/proc/vmstat key counters]"
    grep -E '^(pswpin|pswpout|pgmajfault|allocstall|pgsteal|pgscan|compact_|oom_kill|workingset_)' /proc/vmstat 2>/dev/null || true
    echo ""
  } >> "$_out"

  echo "STAGE=5/13 Reading PSI (CPU, I/O, Memory stall pressure)"
  {
    echo "===== SECTION 05: PSI (PRESSURE STALL INFORMATION) ====="
    for _pf in cpu io memory; do
      echo "--- /proc/pressure/$_pf ---"
      cat "/proc/pressure/$_pf" 2>/dev/null || echo "(unreadable)"
    done
    echo ""
  } >> "$_out"

  echo "STAGE=6/13 Reading Thermal Zones & Cooling Throttle State"
  {
    echo "===== SECTION 06: THERMAL ZONES & COOLING THROTTLE STATE ====="
    echo "[thermal_zones]"
    for _tz in /sys/class/thermal/thermal_zone*; do
      [ -r "$_tz/type" ] || continue
      echo "  $(basename "$_tz") | $(read_first_line "$_tz/type"): $(read_first_line "$_tz/temp")"
    done
    echo ""
    echo "[cooling_devices]"
    for _cd in /sys/class/thermal/cooling_device*; do
      [ -r "$_cd/type" ] || continue
      echo "  $(basename "$_cd") | $(read_first_line "$_cd/type"): cur=$(read_first_line "$_cd/cur_state") / max=$(read_first_line "$_cd/max_state")"
    done
    echo ""
  } >> "$_out"

  echo "STAGE=7/13 Inspecting CPUFreq (sched_pixel) & GS101 vendor_sched"
  {
    echo "===== SECTION 07: CPUFREQ (sched_pixel) & GS101 vendor_sched ====="
    for _pol in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$_pol" ] || continue
      echo "--- $(basename "$_pol") ---"
      for _cf in scaling_cur_freq scaling_min_freq scaling_max_freq cpuinfo_max_freq scaling_governor; do
        [ -r "$_pol/$_cf" ] && echo "  $_cf=$(read_first_line "$_pol/$_cf")"
      done
      if [ -d "$_pol/sched_pixel" ]; then
        for _sf in "$_pol"/sched_pixel/*; do
          [ -r "$_sf" ] && echo "  sched_pixel/$(basename "$_sf")=$(read_first_line "$_sf")"
        done
      fi
    done
    echo ""
    if [ -d /proc/vendor_sched ]; then
      echo "[/proc/vendor_sched globals]"
      for _vg in latency_ns min_granularity_ns adpf_rampup_multiplier auto_prefer_idle reduce_prefer_idle uclamp_max_filter_enable auto_uclamp_max dvfs_headroom util_threshold; do
        [ -r "/proc/vendor_sched/$_vg" ] && echo "  $_vg=$(read_first_line "/proc/vendor_sched/$_vg")"
      done
      echo "[/proc/vendor_sched/groups]"
      for _g in ta fg sf sys bg sys_bg ota dex2oat cam; do
        _gd="/proc/vendor_sched/groups/$_g"
        [ -d "$_gd" ] || continue
        echo "  $_g: uclamp_min=$(read_first_line "$_gd/uclamp_min") uclamp_max=$(read_first_line "$_gd/uclamp_max") prefer_idle=$(read_first_line "$_gd/prefer_idle") prefer_high_cap=$(read_first_line "$_gd/prefer_high_cap") task_spreading=$(read_first_line "$_gd/task_spreading")"
      done
    else
      echo "(/proc/vendor_sched unavailable)"
    fi
    echo ""
  } >> "$_out"

  echo "STAGE=8/13 Inspecting UFS Block I/O & Mali-G78 GPU"
  {
    echo "===== SECTION 08: UFS BLOCK I/O & MALI-G78 GPU ====="
    for _blk in /sys/block/sd* /sys/block/zram0; do
      [ -d "$_blk/queue" ] || continue
      _bn=$(basename "$_blk")
      echo "  $_bn: sched=$(read_first_line "$_blk/queue/scheduler") ra=$(read_first_line "$_blk/queue/read_ahead_kb") nr=$(read_first_line "$_blk/queue/nr_requests") async=$(read_first_line "$_blk/queue/iosched/async_depth") iostats=$(read_first_line "$_blk/queue/iostats")"
    done
    echo ""
    if [ -d /sys/devices/platform/1c500000.mali ]; then
      echo "[Mali-G78 1c500000.mali]"
      for _gf in cur_freq min_freq max_freq hint_min_freq hint_max_freq scaling_min_freq scaling_max_freq power_policy dvfs_period governor; do
        [ -r "/sys/devices/platform/1c500000.mali/$_gf" ] && echo "  $_gf=$(read_first_line "/sys/devices/platform/1c500000.mali/$_gf")"
      done
    else
      echo "(1c500000.mali unavailable)"
    fi
    echo ""
  } >> "$_out"

  echo "STAGE=9/13 Capturing Top CPU & RAM Processes"
  {
    echo "===== SECTION 09: TOP CPU & RAM PROCESSES ====="
    echo "[top snapshot]"
    top -b -n 1 2>/dev/null | head -n 40 || echo "(top unavailable)"
    echo ""
    echo "[ps top 30 by RSS]"
    if ps -A -o PID,PPID,USER,RSS,VSZ,S,NAME >/dev/null 2>&1; then
      ps -A -o PID,PPID,USER,RSS,VSZ,S,NAME 2>/dev/null | awk 'NR==1{print; next} {print | "sort -k4 -rn | head -n 30"}' || true
    else
      ps -eo pid,ppid,user,rss,vsz,s,comm 2>/dev/null | awk 'NR==1{print; next} {print | "sort -k4 -rn | head -n 30"}' || true
    fi
    if command -v dumpsys >/dev/null 2>&1; then
      echo ""
      echo "[dumpsys meminfo --short]"
      dumpsys meminfo --short 2>/dev/null | head -n 65 || echo "(dumpsys meminfo unavailable)"
    fi
    echo ""
  } >> "$_out"

  echo "STAGE=10/13 Live Time-Series Sampling (duration=${_dur}s, interval=${_iv}s)"
  {
    echo "===== SECTION 10: LIVE TIME-SERIES SAMPLING ====="
    if [ "$_dur" -eq 0 ]; then
      echo "(skipped: duration=0)"
    else
      printf 'idx\tuptime_s\tmem_avail_mb\tswap_used_mb\td_pswpin\td_pswpout\td_pgmajfault\td_allocstall\td_oom\tpsi_cpu10\tpsi_io10\tpsi_mem10\tbig_c\tmid_c\tbatt_c\tcool0\tcool1\tcool2\tp0_mhz\tp4_mhz\tp6_mhz\ttop_proc\n'
      _prev_in=$(read_vmstat_val pswpin)
      _prev_out=$(read_vmstat_val pswpout)
      _prev_maj=$(read_vmstat_val pgmajfault)
      _prev_ast=$(($(read_vmstat_val allocstall_normal) + $(read_vmstat_val allocstall_movable) + $(read_vmstat_val allocstall_dma32)))
      _prev_oom=$(read_vmstat_val oom_kill)
      _steps=$((_dur / _iv))
      [ "$_steps" -lt 1 ] && _steps=1
      _i=1
      while [ "$_i" -le "$_steps" ]; do
        sleep "$_iv"
        _cur_in=$(read_vmstat_val pswpin)
        _cur_out=$(read_vmstat_val pswpout)
        _cur_maj=$(read_vmstat_val pgmajfault)
        _cur_ast=$(($(read_vmstat_val allocstall_normal) + $(read_vmstat_val allocstall_movable) + $(read_vmstat_val allocstall_dma32)))
        _cur_oom=$(read_vmstat_val oom_kill)
        _d_in=$((_cur_in - _prev_in))
        _d_out=$((_cur_out - _prev_out))
        _d_maj=$((_cur_maj - _prev_maj))
        _d_ast=$((_cur_ast - _prev_ast))
        _d_oom=$((_cur_oom - _prev_oom))
        _prev_in=$_cur_in; _prev_out=$_cur_out; _prev_maj=$_cur_maj; _prev_ast=$_cur_ast; _prev_oom=$_cur_oom

        _ma_mb=$(( $(read_meminfo_kb MemAvailable) / 1024 ))
        _su_mb=$(( ($(read_meminfo_kb SwapTotal) - $(read_meminfo_kb SwapFree)) / 1024 ))
        _p_cpu=$(extract_psi_avg10 /proc/pressure/cpu)
        _p_io=$(extract_psi_avg10 /proc/pressure/io)
        _p_mem=$(extract_psi_avg10 /proc/pressure/memory)
        _big_c=$(read_thermal_c BIG)
        _mid_c=$(read_thermal_c MID)
        _bat_c=$(read_thermal_c battery)
        _c0=$(read_cool_state thermal-cpufreq-0)
        _c1=$(read_cool_state thermal-cpufreq-1)
        _c2=$(read_cool_state thermal-cpufreq-2)
        _m0=$(read_policy_mhz policy0)
        _m4=$(read_policy_mhz policy4)
        _m6=$(read_policy_mhz policy6)
        _up_s=$(read_uptime_s)
        _tproc=$(top_proc_line)
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$_i" "$_up_s" "$_ma_mb" "$_su_mb" "$_d_in" "$_d_out" "$_d_maj" "$_d_ast" "$_d_oom" \
          "$_p_cpu" "$_p_io" "$_p_mem" "$_big_c" "$_mid_c" "$_bat_c" "$_c0" "$_c1" "$_c2" \
          "$_m0" "$_m4" "$_m6" "$_tproc"
        echo "SAMPLE=${_i}/${_steps} avail=${_ma_mb}MB swap=${_su_mb}MB psi=${_p_cpu}/${_p_io}/${_p_mem} big=${_big_c}C" >&3 2>/dev/null || \
          printf 'SAMPLE=%s/%s avail=%sMB swap=%sMB psi=%s/%s/%s big=%sC\n' "$_i" "$_steps" "$_ma_mb" "$_su_mb" "$_p_cpu" "$_p_io" "$_p_mem" "$_big_c" >/dev/tty 2>/dev/null || true
        _i=$((_i + 1))
      done
    fi
    echo ""
  } 3>&1 >> "$_out"

  # Emit sample lines reliably even without /dev/tty by splitting sampling progress or reading section 10?
  # Note: fd 3 above already redirects directly to caller stdout while >> "$_out" writes only section content!

  echo "STAGE=11/13 Extracting Logcat Forensics (ART, LMKD, mmd, Thermal, SF)"
  _od_hits=0
  _lmk_hits=0
  _slow_hits=0
  _lc_tmp="$DIAG_DIR/.lc.tmp.$$"
  _lc_err="$DIAG_DIR/.lc.err.$$"
  _lc_bin="/system/bin/logcat"
  [ -x "$_lc_bin" ] || _lc_bin=$(command -v logcat 2>/dev/null || true)
  _lc_lines=0
  {
    echo "===== SECTION 11: LOGCAT FORENSICS (FILTERED) ====="
    if [ -n "$_lc_bin" ] && [ -x "$_lc_bin" ]; then
      _lc_rc=0
      "$_lc_bin" -b main -b system -b events -b crash -d -v threadtime -t 6000 > "$_lc_tmp" 2>"$_lc_err"
      _lc_rc=$?
      if [ ! -s "$_lc_tmp" ]; then
        "$_lc_bin" -d -v threadtime > "$_lc_tmp" 2>>"$_lc_err"
        _lc_rc=$?
      fi
      if [ ! -s "$_lc_tmp" ]; then
        "$_lc_bin" -b all -d -t 3000 > "$_lc_tmp" 2>>"$_lc_err"
        _lc_rc=$?
      fi
      _lc_lines=$(wc -l < "$_lc_tmp" 2>/dev/null | tr -d ' ' || echo 0)
      echo "[logcat_bin=$_lc_bin rc=$_lc_rc raw_lines=${_lc_lines:-0}]"
      if [ "${_lc_lines:-0}" -eq 0 ]; then
        echo "[logcat_probe]"
        ls -l "$_lc_bin" 2>&1 || true
        "$_lc_bin" -g 2>&1 || true
        getprop 2>/dev/null | grep -iE 'logd|log\.tag' | head -n 20 || true
        if [ -s "$_lc_err" ]; then
          echo "[logcat_stderr]"
          cat "$_lc_err" 2>/dev/null || true
        fi
      fi
      echo "--- [ART / odrefresh / dex2oat / artd] ---"
      grep -iE 'odrefresh|dex2oat|artd|odsign' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
      echo "--- [LMKD / lowmemorykiller] ---"
      grep -iE 'lowmemorykiller|lmkd|Kill .' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
      echo "--- [mmd / zram] ---"
      grep -iE 'mmd|zram' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
      echo "--- [ActivityTaskManager / Displayed / ANR / Slow] ---"
      grep -iE 'Displayed |ANR in|Slow operation|ActivityTaskManager' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
      echo "--- [Thermal / PowerHAL / Mitigation] ---"
      grep -iE 'thermal|powerhal|mitigation|BCL' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
      echo "--- [SurfaceFlinger / HWComposer / Choreographer] ---"
      grep -iE 'SurfaceFlinger|HWComposer|Choreographer|Skipped [0-9]+ frames' "$_lc_tmp" 2>/dev/null | tail -n 120 || true
    else
      echo "(logcat binary unavailable)"
    fi
    echo ""
  } >> "$_out"

  if [ -r "$_lc_tmp" ]; then
    _od_hits=$(count_matches 'odrefresh.*Compiling|dex2oat.*(filter|compiling)' "$_lc_tmp")
    _lmk_hits=$(count_matches 'lowmemorykiller.*Kill|lmkd.*Kill' "$_lc_tmp")
    _slow_hits=$(count_matches 'Displayed .*\+([3-9][0-9]s|[0-9]+s.*|1[0-9]{4,}ms|[2-9][0-9]{4,}ms)|ANR in' "$_lc_tmp")
  fi
  rm -f "$_lc_tmp" "$_lc_err" 2>/dev/null || true

  echo "STAGE=12/13 Extracting Kernel dmesg Forensics"
  _avc_hits=0
  _dm_tmp="$DIAG_DIR/.dm.tmp.$$"
  _dm_err="$DIAG_DIR/.dm.err.$$"
  _dm_used="none"
  _dm_rc=127
  _dm_lines=0
  {
    echo "===== SECTION 12: KERNEL DMESG FORENSICS (FILTERED) ====="
    capture_dmesg_raw "$_dm_tmp" "$_dm_err"
    _dm_used="$_DM_USED"
    _dm_rc="$_DM_RC"
    _dm_lines=$(wc -l < "$_dm_tmp" 2>/dev/null | tr -d ' ' || echo 0)
    echo "[dmesg_bin=$_dm_used rc=$_dm_rc raw_lines=${_dm_lines:-0}]"
    if [ "${_dm_lines:-0}" -eq 0 ]; then
      echo "[dmesg_probe]"
      ls -l /system/bin/dmesg 2>&1 || true
      echo "dmesg_restrict=$(read_first_line /proc/sys/kernel/dmesg_restrict)"
      echo "id=$(id 2>/dev/null || echo unknown)"
      if [ -s "$_dm_err" ]; then
        echo "[dmesg_stderr]"
        cat "$_dm_err" 2>/dev/null || true
      fi
    fi
    if [ -s "$_dm_tmp" ]; then
      grep -iE 'zram|swap|oom|lmk|thermal|throttle|cpufreq|vendor_sched|mali|ufshcd|avc:|denied|hung_task|blocked for more than' "$_dm_tmp" 2>/dev/null | tail -n 250 || true
    fi
    echo ""
  } >> "$_out"
  if [ -r "$_dm_tmp" ]; then
    _avc_hits=$(count_matches 'avc:.*denied' "$_dm_tmp")
  fi
  rm -f "$_dm_tmp" "$_dm_err" 2>/dev/null || true

  echo "STAGE=13/13 Computing Automated Diagnostic Summary"
  _cool_max=0
  for _cn in thermal-cpufreq-0 thermal-cpufreq-1 thermal-cpufreq-2 thermal-gpufreq-0; do
    _cs=$(read_cool_state "$_cn")
    _cv=${_cs%%/*}
    if is_uint "$_cv" && [ "$_cv" -gt "$_cool_max" ]; then
      _cool_max=$_cv
    fi
  done

  _big_now=$(read_thermal_c BIG)
  _mid_now=$(read_thermal_c MID)
  _high_temp="0"
  _big_int=${_big_now%%.*}
  if is_uint "$_big_int" && [ "$_big_int" -ge 75 ]; then
    _high_temp="1"
  fi

  _zdisk=$(read_first_line /sys/block/zram0/disksize)
  _zorig=$(awk '{print $1}' /sys/block/zram0/mm_stat 2>/dev/null || echo 0)
  _zpct=$(pct_of "$_zorig" "$_zdisk")

  _mmd_req=$(safe_getprop mmd.zram.size)
  _zmismatch="0"
  if is_uint "$_mmd_req" && is_uint "$_zdisk" && [ "$_mmd_req" != "$_zdisk" ]; then
    _zmismatch="1"
  fi

  {
    echo "===== SECTION 13: AUTOMATED DIAGNOSTIC SUMMARY ====="
    echo "THERMAL_THROTTLE_MAX_STATE=$_cool_max"
    echo "HIGH_SOC_TEMP=$_high_temp (BIG=${_big_now}C, MID=${_mid_now}C)"
    echo "ZRAM_FULL_PCT=${_zpct}%"
    echo "ZRAM_MMD_MISMATCH=$_zmismatch (live=${_zdisk}, mmd.zram.size=${_mmd_req:-unset})"
    echo "ODREFRESH_HITS=$_od_hits"
    echo "LMKD_KILL_HITS=$_lmk_hits"
    echo "SLOW_DISPLAYED_HITS=$_slow_hits"
    echo "AVC_DENIED_HITS=$_avc_hits"
    echo ""
  } >> "$_out"

  prune_old_diags

  _exp_path=""
  if [ "$_export" = "1" ]; then
    if mkdir -p "$EXPORT_DIR" 2>/dev/null && cp -f "$_out" "$EXPORT_DIR/$_bname" 2>/dev/null; then
      cp -f "$_out" "$EXPORT_DIR/latest-caventus-diag.log" 2>/dev/null || true
      _exp_path="$EXPORT_DIR/$_bname"
    fi
    if [ -d "$PROJECT_EXPORT_DIR" ] && [ -w "$PROJECT_EXPORT_DIR" ]; then
      cp -f "$_out" "$PROJECT_EXPORT_DIR/latest-caventus-diag.log" 2>/dev/null || true
    fi
  fi

  echo "SAVED_INTERNAL=$_out"
  [ -n "$_exp_path" ] && echo "SAVED_EXPORT=$_exp_path"
  echo "VERDICT=THROTTLE=${_cool_max} HIGH_TEMP=${_high_temp} ZRAM=${_zpct}% MISMATCH=${_zmismatch} ODREFRESH=${_od_hits} LMKD=${_lmk_hits} SLOW_APP=${_slow_hits} AVC=${_avc_hits}"
  return 0
}

validate_diag_filename() {
  _fn="$1"
  [ -n "$_fn" ] || return 1
  case "$_fn" in
    */*|*..*) return 1 ;;
    caventus-diag-*.log|caventus-realtime-*.log|last-boot.log) return 0 ;;
    *) return 1 ;;
  esac
}

rt_load_settings() {
  RT_ENABLED=1
  RT_INTERVAL=10
  RT_MAX_MB=15
  if [ -r "$CONFIG_ENV" ]; then
    _v=$(grep -m1 '^DIAG_DAEMON_ENABLED=' "$CONFIG_ENV" 2>/dev/null | cut -d= -f2 || true)
    case "$_v" in 0|1) RT_ENABLED="$_v" ;; esac
    _v=$(grep -m1 '^DIAG_DAEMON_INTERVAL_SEC=' "$CONFIG_ENV" 2>/dev/null | cut -d= -f2 || true)
    if in_range "$_v" 5 60; then
      RT_INTERVAL="$_v"
    fi
    _v=$(grep -m1 '^DIAG_DAEMON_MAX_MB=' "$CONFIG_ENV" 2>/dev/null | cut -d= -f2 || true)
    if in_range "$_v" 2 100; then
      RT_MAX_MB="$_v"
    fi
  fi
  if [ "${CAVENTUS_RT_TEST_FAST:-0}" = "1" ]; then
    RT_INTERVAL=1
  fi
}

rt_is_running() {
  [ -f "$RT_PID_FILE" ] || return 1
  _rpid=$(cat "$RT_PID_FILE" 2>/dev/null || true)
  is_uint "$_rpid" || return 1
  kill -0 "$_rpid" 2>/dev/null || return 1
  if [ -r "/proc/$_rpid/cmdline" ]; then
    _cmd=$(tr '\000' ' ' < "/proc/$_rpid/cmdline" 2>/dev/null || true)
    case "$_cmd" in
      *caventus-diag*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

rt_metrics_header() {
  printf 'ts\tuptime_s\tmem_avail_mb\tmem_free_mb\tcached_mb\tanon_mb\tswap_used_mb\tswap_total_mb\tzram_orig_mb\tzram_compr_mb\tzram_mem_mb\tbd_count\td_pswpin\td_pswpout\td_pgmajfault\td_pgsteal_direct\td_allocstall\td_oom\tpsi_cpu10\tpsi_io10\tpsi_mem10\tpsi_mem_full10\tbig_c\tmid_c\tbatt_c\tcool0\tcool1\tcool2\tp0_mhz\tp4_mhz\tp6_mhz\tflags\n'
}

rt_file_bytes() {
  if [ -f "$1" ]; then
    wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0
  else
    echo 0
  fi
}

rt_dir_kb() {
  _tot_b=0
  for _rf in "$RT_DIR"/*; do
    [ -f "$_rf" ] || continue
    _fb=$(wc -c < "$_rf" 2>/dev/null | tr -d ' ' || echo 0)
    _tot_b=$(awk -v a="$_tot_b" -v b="${_fb:-0}" 'BEGIN { printf "%.0f\n", a + b }')
  done
  awk -v b="$_tot_b" 'BEGIN { printf "%.0f\n", int((b + 1023) / 1024) }'
}

rt_write_status() {
  _st_tmp="${RT_STATUS}.tmp.$$"
  cat <<EOF > "$_st_tmp"
state=$1
pid=$2
started=$3
samples=$4
anomalies=$5
interval_s=$6
size_kb=$7
last_ts=$8
last_flags=$9
EOF
  mv -f "$_st_tmp" "$RT_STATUS" 2>/dev/null || true
}

rt_read_status_field() {
  _fk="$1"
  _fdef="$2"
  if [ -r "$RT_STATUS" ]; then
    _fv=$(grep -m1 "^${_fk}=" "$RT_STATUS" 2>/dev/null | cut -d= -f2- || true)
    [ -n "$_fv" ] && { printf '%s' "$_fv"; return 0; }
  fi
  printf '%s' "$_fdef"
}

rt_write_session_meta() {
  mkdir -p "$RT_DIR" 2>/dev/null || true
  _ts=$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown)
  _up=$(cat /proc/uptime 2>/dev/null || echo unknown)
  {
    echo "######################################################################"
    echo "# CAVENTUS REALTIME SESSION METADATA"
    echo "# Updated: $_ts"
    echo "######################################################################"
    echo ""
    echo "[module.prop]"
    if [ -r "$MODDIR/module.prop" ]; then
      cat "$MODDIR/module.prop" 2>/dev/null || true
    else
      echo "(missing $MODDIR/module.prop)"
    fi
    echo ""
    echo "[device]"
    echo "device=$(safe_getprop ro.product.device)"
    echo "android=$(safe_getprop ro.build.version.release)"
    echo "build=$(safe_getprop ro.build.display.id)"
    echo "kernel=$(uname -a 2>/dev/null || echo unknown)"
    echo "uptime=$_up"
    echo ""
    echo "[config.env]"
    if [ -r "$CONFIG_ENV" ]; then
      cat "$CONFIG_ENV" 2>/dev/null || true
    else
      echo "(missing $CONFIG_ENV)"
    fi
    echo ""
    echo "[module system.prop]"
    if [ -r "$MODDIR/system.prop" ]; then
      cat "$MODDIR/system.prop" 2>/dev/null || true
    else
      echo "(missing $MODDIR/system.prop)"
    fi
    echo ""
    echo "[ksu modules inventory]"
    if [ -d /data/adb/modules ]; then
      for _md in /data/adb/modules/*; do
        [ -d "$_md" ] || continue
        _mstate="enabled"
        [ -f "$_md/disable" ] && _mstate="disabled"
        [ -f "$_md/remove" ] && _mstate="remove"
        _mver=$(grep -m1 '^version=' "$_md/module.prop" 2>/dev/null | cut -d= -f2- || echo "?")
        _mname=$(grep -m1 '^name=' "$_md/module.prop" 2>/dev/null | cut -d= -f2- || basename "$_md")
        echo "  $(basename "$_md") | $_mstate | ver=$_mver | $_mname"
      done
    else
      echo "(no /data/adb/modules directory)"
    fi
    echo ""
    echo "[android properties]"
    if command -v getprop >/dev/null 2>&1; then
      getprop 2>/dev/null | grep -E '\[(dalvik\.vm\.|pm\.dexopt\.|mmd\.|ro\.lmk\.|persist\.device_config\.lmkd_native\.|sys\.boot_completed|init\.svc\.(mmd|lmkd|artd))' | sort || true
    else
      echo "(getprop unavailable in sandbox)"
    fi
    echo ""
    echo "[last-boot.log]"
    if [ -r "$BOOT_LOG" ]; then
      cat "$BOOT_LOG" 2>/dev/null || true
    else
      echo "(no $BOOT_LOG)"
    fi
    echo ""
  } > "$RT_META"

  if [ ! -s "$RT_METRICS" ]; then
    rt_metrics_header > "$RT_METRICS"
  fi
  _marker="# === SESSION START $_ts uptime=$(echo "$_up" | awk '{print $1}') ==="
  echo "$_marker" >> "$RT_METRICS"
  echo "$_marker" >> "$RT_ANOM"
  echo "$_marker" >> "$RT_EVENTS"
}

rt_rotate_if_needed() {
  _max_total_bytes=$(awk -v m="${RT_MAX_MB:-15}" 'BEGIN { printf "%.0f\n", m * 1048576 }')
  _lim_metrics=$(awk -v t="$_max_total_bytes" 'BEGIN { printf "%.0f\n", int(t * 0.40) }')
  _lim_anom=$(awk -v t="$_max_total_bytes" 'BEGIN { printf "%.0f\n", int(t * 0.35) }')
  _lim_evt=$(awk -v t="$_max_total_bytes" 'BEGIN { printf "%.0f\n", int(t * 0.25) }')

  _sz=$(rt_file_bytes "$RT_METRICS")
  if awk -v s="$_sz" -v l="$_lim_metrics" 'BEGIN { exit !(s > l) }'; then
    mv -f "$RT_METRICS" "${RT_METRICS}.prev" 2>/dev/null || true
    rt_metrics_header > "$RT_METRICS"
  fi
  _sz=$(rt_file_bytes "$RT_ANOM")
  if awk -v s="$_sz" -v l="$_lim_anom" 'BEGIN { exit !(s > l) }'; then
    mv -f "$RT_ANOM" "${RT_ANOM}.prev" 2>/dev/null || true
    : > "$RT_ANOM"
  fi
  _sz=$(rt_file_bytes "$RT_EVENTS")
  if awk -v s="$_sz" -v l="$_lim_evt" 'BEGIN { exit !(s > l) }'; then
    mv -f "$RT_EVENTS" "${RT_EVENTS}.prev" 2>/dev/null || true
    : > "$RT_EVENTS"
  fi
}

rt_collect_events() {
  _first_evt="${1:-0}"
  _ev_now=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
  _dm_tmp="$RT_DIR/.dm.$$"
  _dm_err="$RT_DIR/.dm.err.$$"
  _lc_tmp="$RT_DIR/.lc.$$"
  _lc_err="$RT_DIR/.lc.err.$$"

  capture_dmesg_raw "$_dm_tmp" "$_dm_err"

  _lc_bin="/system/bin/logcat"
  [ -x "$_lc_bin" ] || _lc_bin=$(command -v logcat 2>/dev/null || true)
  _lc_rc=127
  : > "$_lc_tmp"
  : > "$_lc_err"
  if [ -n "$_lc_bin" ] && [ -x "$_lc_bin" ]; then
    "$_lc_bin" -b main -b system -b events -b crash -d -v threadtime -t 250 > "$_lc_tmp" 2>"$_lc_err"
    _lc_rc=$?
    if [ ! -s "$_lc_tmp" ]; then
      "$_lc_bin" -b all -d -t 250 > "$_lc_tmp" 2>>"$_lc_err"
      _lc_rc=$?
    fi
  fi

  if [ "$_first_evt" = "1" ]; then
    _dm_cnt=$(wc -l < "$_dm_tmp" 2>/dev/null | tr -d ' ' || echo 0)
    _lc_cnt=$(wc -l < "$_lc_tmp" 2>/dev/null | tr -d ' ' || echo 0)
    echo "[$_ev_now] [events_init dmesg_bin=${_DM_USED} rc=${_DM_RC} raw=${_dm_cnt} logcat_bin=${_lc_bin:-none} rc=${_lc_rc} raw=${_lc_cnt}]" >> "$RT_EVENTS"
  fi

  if [ -s "$_dm_tmp" ]; then
    _last_dm=$(cat "$RT_STATE_DM" 2>/dev/null || echo "-1")
    [ -z "$_last_dm" ] && _last_dm="-1"
    _dm_filt="$RT_DIR/.dmf.$$"
    grep -iE 'zram|swap|oom|lmk|thermal|throttle|cpufreq|vendor_sched|mali|ufshcd|avc:|denied|hung_task|blocked for more than|artd|odrefresh|init:.*(lmkd|artd|mmd)' "$_dm_tmp" 2>/dev/null | \
      awk -v last="$_last_dm" -v statef="$RT_STATE_DM" '
        {
          ts = -1;
          if (match($0, /^\[[ ]*[0-9]+\.[0-9]+\]/)) {
            s = substr($0, RSTART + 1, RLENGTH - 2);
            gsub(/ /, "", s);
            ts = s + 0;
          }
          if (ts > (last + 0) || (ts < 0 && (last + 0) < 0)) {
            lines[++n] = $0;
            if (ts > max_ts) max_ts = ts;
          }
        }
        END {
          start = (n > 80) ? (n - 79) : 1;
          for (i = start; i <= n; i++) print lines[i];
          if (n > 0 && max_ts > (last + 0)) {
            printf "%.6f\n", max_ts > statef;
            close(statef);
          }
        }
      ' > "$_dm_filt" 2>/dev/null || true
    if [ -s "$_dm_filt" ]; then
      echo "--- [dmesg @ $_ev_now] ---" >> "$RT_EVENTS"
      cat "$_dm_filt" >> "$RT_EVENTS"
    fi
    rm -f "$_dm_filt" 2>/dev/null || true
  fi

  if [ -s "$_lc_tmp" ]; then
    _last_lc=$(cat "$RT_STATE_LC" 2>/dev/null || true)
    _lc_filt="$RT_DIR/.lcf.$$"
    grep -iE 'odrefresh|dex2oat|artd|lowmemorykiller|lmkd|Kill |mmd|zram|Displayed |ANR in|Slow operation|thermal|powerhal|Choreographer|Skipped [0-9]+ frames' "$_lc_tmp" 2>/dev/null | \
      awk -v prev="$_last_lc" -v statef="$RT_STATE_LC" '
        { lines[++n] = $0 }
        END {
          idx = 0;
          if (prev != "") {
            for (i = n; i >= 1; i--) {
              if (lines[i] == prev) { idx = i; break; }
            }
          }
          start = idx + 1;
          if ((n - start + 1) > 60) start = n - 59;
          for (i = start; i <= n; i++) print lines[i];
          if (n > 0) {
            print lines[n] > statef;
            close(statef);
          }
        }
      ' > "$_lc_filt" 2>/dev/null || true
    if [ -s "$_lc_filt" ]; then
      echo "--- [logcat @ $_ev_now] ---" >> "$RT_EVENTS"
      cat "$_lc_filt" >> "$RT_EVENTS"
    fi
    rm -f "$_lc_filt" 2>/dev/null || true
  fi

  rm -f "$_dm_tmp" "$_dm_err" "$_lc_tmp" "$_lc_err" 2>/dev/null || true
}

rt_write_anomaly_snapshot() {
  _reason="${1:-EVENT}"
  _ats=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
  {
    echo "=== SNAPSHOT [$_reason] @ $_ats | uptime=$(read_uptime_s)s | load=$(cat /proc/loadavg 2>/dev/null || echo unknown) ==="
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|AnonPages|Dirty|Writeback|Slab|SReclaimable|SUnreclaim|PageTables):' /proc/meminfo 2>/dev/null || true
    echo "zram0/mm_stat: $(read_first_line /sys/block/zram0/mm_stat)"
    echo "zram0/bd_stat: $(read_first_line /sys/block/zram0/bd_stat) | io_stat: $(read_first_line /sys/block/zram0/io_stat)"
    echo "psi_cpu: $(read_first_line /proc/pressure/cpu)"
    echo "psi_io: $(read_first_line /proc/pressure/io)"
    echo "psi_mem: $(read_first_line /proc/pressure/memory)"
    echo "drift: sda_ra=$(read_first_line /sys/block/sda/queue/read_ahead_kb) mglru_ttl=$(read_first_line /sys/kernel/mm/lru_gen/min_ttl_ms) vendor_lat=$(read_first_line /proc/vendor_sched/latency_ns) cool=$(read_cool_state thermal-cpufreq-0)/$(read_cool_state thermal-cpufreq-1)/$(read_cool_state thermal-cpufreq-2)"
    echo "[top 22]"
    top -b -n 1 2>/dev/null | head -n 22 || true
    echo "[ps top 15 RSS]"
    if ps -A -o PID,RSS,S,NAME >/dev/null 2>&1; then
      ps -A -o PID,RSS,S,NAME 2>/dev/null | awk 'NR==1{print; next} {print | "sort -k2 -rn | head -n 15"}' || true
    else
      ps -eo pid,rss,s,comm 2>/dev/null | awk 'NR==1{print; next} {print | "sort -k2 -rn | head -n 15"}' || true
    fi
    if command -v dumpsys >/dev/null 2>&1; then
      echo "[dumpsys meminfo --short]"
      dumpsys meminfo --short 2>/dev/null | head -n 45 || true
    fi
    echo ""
  } >> "$RT_ANOM" 2>/dev/null || true
}

rt_read_vmstat_tuple() {
  awk '
    $1=="pswpin" {pin=$2}
    $1=="pswpout" {pout=$2}
    $1=="pgmajfault" {maj=$2}
    $1=="pgsteal_direct" {sd=$2}
    $1=="allocstall_normal" {an=$2}
    $1=="allocstall_movable" {am=$2}
    $1=="allocstall_dma32" {ad=$2}
    $1=="oom_kill" {oom=$2}
    END { printf "%.0f %.0f %.0f %.0f %.0f %.0f\n", pin+0, pout+0, maj+0, sd+0, (an+0)+(am+0)+(ad+0), oom+0 }
  ' /proc/vmstat 2>/dev/null || echo "0 0 0 0 0 0"
}

cmd_daemon_loop() {
  mkdir -p "$RT_DIR" 2>/dev/null || true
  echo "$$" > "$RT_PID_FILE"
  echo -900 > "/proc/$$/oom_score_adj" 2>/dev/null || true
  renice -n 5 "$$" >/dev/null 2>&1 || true
  trap 'rm -f "$RT_PID_FILE"; exit 0' INT TERM

  rt_load_settings
  rt_write_session_meta

  set -- $(rt_read_vmstat_tuple)
  _prev_pin=${1:-0}; _prev_pout=${2:-0}; _prev_maj=${3:-0}
  _prev_sd=${4:-0}; _prev_ast=${5:-0}; _prev_oom=${6:-0}

  _samples=0
  _anom_count=0
  _last_anom_epoch=0
  _last_evt_epoch=0
  _last_chk_epoch=$(date +%s 2>/dev/null || echo 0)
  _started_ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")

  while true; do
    _now_epoch=$(date +%s 2>/dev/null || echo 0)
    _now_ts=$(date '+%H:%M:%S' 2>/dev/null || echo "00:00:00")
    _up_s=$(read_uptime_s)

    set -- $(awk '
      $1=="MemAvailable:" {ma=$2}
      $1=="MemFree:" {mf=$2}
      $1=="Cached:" {ca=$2}
      $1=="AnonPages:" {an=$2}
      $1=="SwapTotal:" {st=$2}
      $1=="SwapFree:" {sf=$2}
      END {
        su = (st > sf) ? (st - sf) : 0;
        printf "%.0f %.0f %.0f %.0f %.0f %.0f\n", int(ma/1024), int(mf/1024), int(ca/1024), int(an/1024), int(su/1024), int(st/1024);
      }
    ' /proc/meminfo 2>/dev/null || echo "0 0 0 0 0 0")
    _ma_mb=${1:-0}; _mf_mb=${2:-0}; _ca_mb=${3:-0}
    _an_mb=${4:-0}; _su_mb=${5:-0}; _st_mb=${6:-0}

    if [ -r /sys/block/zram0/mm_stat ]; then
      set -- $(awk '{printf "%.0f %.0f %.0f\n", int($1/1048576), int($2/1048576), int($3/1048576)}' /sys/block/zram0/mm_stat 2>/dev/null || echo "0 0 0")
      _zorig_mb=${1:-0}; _zcomp_mb=${2:-0}; _zmem_mb=${3:-0}
    else
      _zorig_mb=0; _zcomp_mb=0; _zmem_mb=0
    fi
    _bd_cnt=$(awk '{printf "%.0f\n", $1+0}' /sys/block/zram0/bd_stat 2>/dev/null || echo 0)

    set -- $(rt_read_vmstat_tuple)
    _cur_pin=${1:-0}; _cur_pout=${2:-0}; _cur_maj=${3:-0}
    _cur_sd=${4:-0}; _cur_ast=${5:-0}; _cur_oom=${6:-0}

    set -- $(awk -v cp="$_cur_pin" -v pp="$_prev_pin" \
      -v co="$_cur_pout" -v po="$_prev_pout" \
      -v cm="$_cur_maj" -v pm="$_prev_maj" \
      -v cs="$_cur_sd" -v ps="$_prev_sd" \
      -v ca="$_cur_ast" -v pa="$_prev_ast" \
      -v ck="$_cur_oom" -v pk="$_prev_oom" \
      'BEGIN { printf "%.0f %.0f %.0f %.0f %.0f %.0f\n", cp-pp, co-po, cm-pm, cs-ps, ca-pa, ck-pk }')
    _d_pin=${1:-0}; _d_pout=${2:-0}; _d_maj=${3:-0}
    _d_sd=${4:-0}; _d_ast=${5:-0}; _d_oom=${6:-0}
    _prev_pin=$_cur_pin; _prev_pout=$_cur_pout; _prev_maj=$_cur_maj
    _prev_sd=$_cur_sd; _prev_ast=$_cur_ast; _prev_oom=$_cur_oom

    _p_cpu=$(extract_psi_avg10 /proc/pressure/cpu)
    _p_io=$(extract_psi_avg10 /proc/pressure/io)
    _p_mem=$(extract_psi_avg10 /proc/pressure/memory)
    _p_mem_f=$(awk '/^full / {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=","",$i); print $i; exit}}' /proc/pressure/memory 2>/dev/null || echo "0.00")
    [ -n "$_p_mem_f" ] || _p_mem_f="0.00"

    _big_c=$(read_thermal_c BIG)
    _mid_c=$(read_thermal_c MID)
    _bat_c=$(read_thermal_c battery)
    _c0=$(read_cool_state thermal-cpufreq-0)
    _c1=$(read_cool_state thermal-cpufreq-1)
    _c2=$(read_cool_state thermal-cpufreq-2)
    _m0=$(read_policy_mhz policy0)
    _m4=$(read_policy_mhz policy4)
    _m6=$(read_policy_mhz policy6)

    _c0_n=${_c0%%/*}; is_uint "$_c0_n" || _c0_n=0
    _c2_n=${_c2%%/*}; is_uint "$_c2_n" || _c2_n=0
    _flags=$(awk -v ma="$_ma_mb" -v su="$_su_mb" -v st="$_st_mb" \
      -v dm="$_d_maj" -v da="$_d_ast" -v doom="$_d_oom" \
      -v pio="$_p_io" -v pmem="$_p_mem" -v pmemf="$_p_mem_f" \
      -v big="$_big_c" -v c0="$_c0_n" -v c2="$_c2_n" '
      BEGIN {
        f = "";
        if ((big + 0 >= 72.0) || (c0 + 0 >= 7) || (c2 + 0 >= 11)) f = f ",THERMAL";
        if ((ma + 0 > 0) && (ma + 0 <= 500)) f = f ",LOWMEM";
        if ((st + 0 > 0) && ((su * 100 / st) >= 95)) f = f ",SWAPFULL";
        if (dm + 0 >= 15000) f = f ",THRASH";
        if ((pmem + 0 >= 10.0) || (pmemf + 0 >= 3.0)) f = f ",PSI_MEM";
        if (pio + 0 >= 20.0) f = f ",PSI_IO";
        if (da + 0 > 0) f = f ",ALLOCSTALL";
        if (doom + 0 > 0) f = f ",OOM";
        sub(/^,/, "", f);
        print (f == "" ? "OK" : f);
      }')

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$_now_ts" "$_up_s" "$_ma_mb" "$_mf_mb" "$_ca_mb" "$_an_mb" "$_su_mb" "$_st_mb" \
      "$_zorig_mb" "$_zcomp_mb" "$_zmem_mb" "$_bd_cnt" \
      "$_d_pin" "$_d_pout" "$_d_maj" "$_d_sd" "$_d_ast" "$_d_oom" \
      "$_p_cpu" "$_p_io" "$_p_mem" "$_p_mem_f" \
      "$_big_c" "$_mid_c" "$_bat_c" "$_c0" "$_c1" "$_c2" "$_m0" "$_m4" "$_m6" "$_flags" >> "$RT_METRICS"

    _samples=$((_samples + 1))

    if [ "$_flags" != "OK" ]; then
      if [ $((_now_epoch - _last_anom_epoch)) -ge 60 ]; then
        _anom_count=$((_anom_count + 1))
        _last_anom_epoch=$_now_epoch
        rt_write_anomaly_snapshot "$_flags"
      fi
    fi

    if [ $((_now_epoch - _last_chk_epoch)) -ge 600 ]; then
      _last_chk_epoch=$_now_epoch
      rt_write_anomaly_snapshot "CHECKPOINT_10M"
    fi

    if [ "$_samples" -eq 1 ] || [ $((_now_epoch - _last_evt_epoch)) -ge 60 ]; then
      _first=0
      [ "$_samples" -eq 1 ] && _first=1
      _last_evt_epoch=$_now_epoch
      rt_collect_events "$_first"
      rt_rotate_if_needed
      rt_load_settings
      if [ "$RT_ENABLED" != "1" ]; then
        break
      fi
    fi

    _sz_kb=$(rt_dir_kb)
    rt_write_status "running" "$$" "$_started_ts" "$_samples" "$_anom_count" "$RT_INTERVAL" "$_sz_kb" "$_now_ts" "$_flags"
    sleep "$RT_INTERVAL"
  done

  _sz_kb=$(rt_dir_kb)
  rt_write_status "stopped" "0" "$_started_ts" "$_samples" "$_anom_count" "$RT_INTERVAL" "$_sz_kb" "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')" "DISABLED"
  rm -f "$RT_PID_FILE" 2>/dev/null || true
}

cmd_daemon_start() {
  if rt_is_running; then
    _epid=$(cat "$RT_PID_FILE" 2>/dev/null || echo 0)
    echo "ALREADY_RUNNING pid=$_epid"
    return 0
  fi
  mkdir -p "$RT_DIR" 2>/dev/null || true
  rm -f "$RT_PID_FILE" 2>/dev/null || true
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$0" daemon-loop </dev/null >/dev/null 2>&1 &
  elif command -v nohup >/dev/null 2>&1; then
    nohup sh "$0" daemon-loop </dev/null >/dev/null 2>&1 &
  else
    sh "$0" daemon-loop </dev/null >/dev/null 2>&1 &
  fi
  _w=0
  while [ ! -s "$RT_PID_FILE" ] && [ "$_w" -lt 20 ]; do
    sleep 0.1 2>/dev/null || sleep 1
    _w=$((_w + 1))
  done
  _npid=$(cat "$RT_PID_FILE" 2>/dev/null || echo "$!")
  echo "STARTED pid=$_npid"
}

cmd_daemon_stop() {
  if rt_is_running; then
    _spid=$(cat "$RT_PID_FILE" 2>/dev/null || true)
    kill "$_spid" 2>/dev/null || true
    _w=0
    while kill -0 "$_spid" 2>/dev/null && [ "$_w" -lt 10 ]; do
      sleep 0.1 2>/dev/null || sleep 1
      _w=$((_w + 1))
    done
    if kill -0 "$_spid" 2>/dev/null; then
      kill -9 "$_spid" 2>/dev/null || true
    fi
  fi
  rm -f "$RT_PID_FILE" 2>/dev/null || true
  rt_load_settings
  _prev_samples=$(rt_read_status_field samples 0)
  _prev_anom=$(rt_read_status_field anomalies 0)
  _prev_started=$(rt_read_status_field started "-")
  _sz=$(rt_dir_kb)
  rt_write_status "stopped" "0" "$_prev_started" "$_prev_samples" "$_prev_anom" "$RT_INTERVAL" "$_sz" "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')" "STOPPED"
  echo "STOPPED"
}

cmd_daemon_status() {
  rt_load_settings
  _state="stopped"
  _pid=0
  if rt_is_running; then
    _state="running"
    _pid=$(cat "$RT_PID_FILE" 2>/dev/null || echo 0)
  fi
  _samples=$(rt_read_status_field samples 0)
  _anom=$(rt_read_status_field anomalies 0)
  _iv=$(rt_read_status_field interval_s "$RT_INTERVAL")
  _ts=$(rt_read_status_field last_ts "never")
  _fl=$(rt_read_status_field last_flags "OK")
  _sz=$(rt_dir_kb)
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$_state" "$_pid" "$_samples" "$_anom" "$_sz" "$_iv" "$_ts" "$_fl"
}

cmd_daemon_export() {
  mkdir -p "$DIAG_DIR" "$RT_DIR" 2>/dev/null || true
  _stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo "00000000-000000")
  _bname="caventus-realtime-${_stamp}.log"
  _out="$DIAG_DIR/$_bname"

  {
    echo "######################################################################"
    echo "# CAVENTUS REALTIME MULTI-HOUR FORENSIC BUNDLE"
    echo "# File: $_bname"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown)"
    echo "# DaemonStatus: $(cmd_daemon_status)"
    echo "######################################################################"
    echo ""
    echo "===== SECTION 01: SESSION METADATA, CONFIG & MODULE INVENTORY ====="
    if [ -r "$RT_META" ]; then
      cat "$RT_META" 2>/dev/null || true
    else
      echo "(no $RT_META yet)"
    fi
    echo ""
    echo "===== SECTION 02: MULTI-HOUR AUTOMATED STATISTICAL SUMMARY ====="
    if [ -r "$RT_METRICS" ]; then
      awk -F '\t' '
        /^(ts|#|$)/ { next }
        {
          n++;
          ma = $3 + 0; su = $7 + 0; st = $8 + 0; zm = $11 + 0;
          pin += ($13 + 0); pout += ($14 + 0); maj += ($15 + 0); ast += ($17 + 0); oom += ($18 + 0);
          dm = $15 + 0;
          big = $23 + 0; mid = $24 + 0; bat = $25 + 0;
          fl = $32;
          if (n == 1) {
            first_ts = $1; first_up = $2 + 0;
            min_ma = ma; max_ma = ma;
            min_su = su; max_su = su;
            max_zm = zm; max_dm = dm;
            min_big = big; max_big = big;
            min_mid = mid; max_mid = mid;
            min_bat = bat; max_bat = bat;
          }
          last_ts = $1; last_up = $2 + 0;
          sum_ma += ma; if (ma < min_ma) min_ma = ma; if (ma > max_ma) max_ma = ma;
          sum_su += su; if (su < min_su) min_su = su; if (su > max_su) max_su = su;
          if (zm > max_zm) max_zm = zm;
          if (dm > max_dm) max_dm = dm;
          sum_big += big; if (big < min_big) min_big = big; if (big > max_big) max_big = big;
          sum_mid += mid; if (mid < min_mid) min_mid = mid; if (mid > max_mid) max_mid = mid;
          sum_bat += bat; if (bat < min_bat) min_bat = bat; if (bat > max_bat) max_bat = bat;
          if (fl ~ /THERMAL/) c_therm++;
          if (fl ~ /THRASH/) c_thrash++;
          if (fl ~ /LOWMEM/) c_low++;
          if (fl ~ /SWAPFULL/) c_swap++;
          if (fl ~ /PSI_MEM/) c_pmem++;
          if (fl ~ /PSI_IO/) c_pio++;
        }
        END {
          if (n == 0) {
            print "SAMPLES=0";
            exit;
          }
          span_s = (last_up >= first_up) ? (last_up - first_up) : 0;
          printf "SAMPLES=%d SPAN_S=%.0f FIRST_TS=%s LAST_TS=%s\n", n, span_s, first_ts, last_ts;
          printf "MEM_AVAIL_MB=min:%.0f avg:%.1f max:%.0f\n", min_ma, sum_ma/n, max_ma;
          printf "SWAP_USED_MB=min:%.0f avg:%.1f max:%.0f MAX_ZRAM_MEM_MB=%.0f\n", min_su, sum_su/n, max_su, max_zm;
          printf "TOTAL_PSWPIN=%.0f TOTAL_PSWPOUT=%.0f TOTAL_PGMAJFAULT=%.0f MAX_TICK_PGMAJFAULT=%.0f TOTAL_ALLOCSTALL=%.0f TOTAL_OOM=%.0f\n", pin, pout, maj, max_dm, ast, oom;
          printf "BIG_C=min:%.1f avg:%.1f max:%.1f | MID_C=min:%.1f avg:%.1f max:%.1f | BATT_C=min:%.1f avg:%.1f max:%.1f\n", min_big, sum_big/n, max_big, min_mid, sum_mid/n, max_mid, min_bat, sum_bat/n, max_bat;
          printf "ANOMALY_TICKS: THERMAL=%d(%.1f%%) THRASH=%d(%.1f%%) LOWMEM=%d(%.1f%%) SWAPFULL=%d(%.1f%%) PSI_MEM=%d(%.1f%%) PSI_IO=%d(%.1f%%)\n",
            c_therm+0, (c_therm+0)*100/n, c_thrash+0, (c_thrash+0)*100/n, c_low+0, (c_low+0)*100/n,
            c_swap+0, (c_swap+0)*100/n, c_pmem+0, (c_pmem+0)*100/n, c_pio+0, (c_pio+0)*100/n;
        }
      ' "$RT_METRICS" 2>/dev/null || echo "SAMPLES=0"
    else
      echo "SAMPLES=0"
    fi
    echo ""
    echo "===== SECTION 03: END-OF-SESSION LIVE SNAPSHOT ====="
    echo "[/proc/meminfo top 35]"
    head -n 35 /proc/meminfo 2>/dev/null || true
    echo ""
    echo "[/sys/block/zram0]"
    for _zf in disksize comp_algorithm backing_dev mm_stat bd_stat io_stat; do
      [ -r "/sys/block/zram0/$_zf" ] && echo "zram0/$_zf: $(cat "/sys/block/zram0/$_zf" 2>/dev/null | tr '\n' ' ')"
    done
    echo ""
    echo "[PSI]"
    for _pf in cpu io memory; do
      echo "$_pf: $(cat "/proc/pressure/$_pf" 2>/dev/null | tr '\n' ' ')"
    done
    echo ""
    echo "[thermal & cooling]"
    echo "BIG=$(read_thermal_c BIG)C MID=$(read_thermal_c MID)C LITTLE=$(read_thermal_c LITTLE)C G3D=$(read_thermal_c G3D)C batt=$(read_thermal_c battery)C"
    echo "cool: p0=$(read_cool_state thermal-cpufreq-0) p4=$(read_cool_state thermal-cpufreq-1) p6=$(read_cool_state thermal-cpufreq-2) gpu=$(read_cool_state thermal-gpufreq-0)"
    echo "vendor_sched latency_ns=$(read_first_line /proc/vendor_sched/latency_ns) | sda_ra=$(read_first_line /sys/block/sda/queue/read_ahead_kb) | mglru_ttl=$(read_first_line /sys/kernel/mm/lru_gen/min_ttl_ms)"
    if command -v dumpsys >/dev/null 2>&1; then
      echo ""
      echo "[dumpsys meminfo --short]"
      dumpsys meminfo --short 2>/dev/null | head -n 65 || true
    fi
    echo ""
    echo "===== SECTION 04: CAPTURED ANOMALY & CHECKPOINT SNAPSHOTS ====="
    if [ -r "$RT_ANOM" ]; then
      tail -n 1500 "$RT_ANOM" 2>/dev/null || true
    else
      echo "(no anomalies captured)"
    fi
    echo ""
    echo "===== SECTION 05: CAPTURED KERNEL & LOGCAT EVENTS ====="
    if [ -r "$RT_EVENTS" ]; then
      tail -n 1500 "$RT_EVENTS" 2>/dev/null || true
    else
      echo "(no kernel/logcat events captured)"
    fi
    echo ""
    echo "===== SECTION 06: REALTIME TIME-SERIES TELEMETRY (metrics.tsv) ====="
    if [ -r "$RT_METRICS" ]; then
      rt_metrics_header
      grep -v '^ts	' "$RT_METRICS" 2>/dev/null | tail -n 4000 || true
    else
      echo "(no metrics recorded)"
    fi
    echo ""
  } > "$_out"

  _exp_path=""
  if mkdir -p "$EXPORT_DIR" 2>/dev/null && cp -f "$_out" "$EXPORT_DIR/$_bname" 2>/dev/null; then
    cp -f "$_out" "$EXPORT_DIR/latest-caventus-realtime.log" 2>/dev/null || true
    _exp_path="$EXPORT_DIR/$_bname"
  fi
  if [ -d "$PROJECT_EXPORT_DIR" ] && [ -w "$PROJECT_EXPORT_DIR" ]; then
    cp -f "$_out" "$PROJECT_EXPORT_DIR/latest-caventus-realtime.log" 2>/dev/null || true
  fi

  _tar_path=""
  if command -v tar >/dev/null 2>&1; then
    _tar_int="$DIAG_DIR/caventus-realtime-raw-latest.tar.gz"
    if tar -czf "$_tar_int" -C "$RT_DIR" . 2>/dev/null; then
      _tar_path="$_tar_int"
      if [ -d "$EXPORT_DIR" ] && [ -w "$EXPORT_DIR" ]; then
        cp -f "$_tar_int" "$EXPORT_DIR/caventus-realtime-raw-latest.tar.gz" 2>/dev/null || true
      fi
    fi
  fi

  _sum=$(grep -m1 '^SAMPLES=' "$_out" 2>/dev/null || echo "SAMPLES=0")
  echo "SAVED_INTERNAL=$_out"
  [ -n "$_exp_path" ] && echo "SAVED_EXPORT=$_exp_path"
  [ -n "$_tar_path" ] && echo "SAVED_TAR=$_tar_path"
  echo "SUMMARY=$_sum"
}

cmd_daemon_clear() {
  mkdir -p "$RT_DIR" 2>/dev/null || true
  rt_metrics_header > "$RT_METRICS"
  : > "$RT_ANOM"
  : > "$RT_EVENTS"
  rm -f "${RT_METRICS}.prev" "${RT_ANOM}.prev" "${RT_EVENTS}.prev" "$RT_STATE_DM" "$RT_STATE_LC" 2>/dev/null || true
  echo "Realtime logs cleared ($RT_DIR)."
}

cmd_list() {
  mkdir -p "$DIAG_DIR" 2>/dev/null || true
  _count=0
  for _f in $(ls -1t "$DIAG_DIR"/caventus-realtime-*.log "$DIAG_DIR"/caventus-diag-*.log "$DIAG_DIR"/last-boot.log 2>/dev/null || true); do
    [ -f "$_f" ] || continue
    _sz_b=$(wc -c < "$_f" 2>/dev/null | tr -d ' ' || echo 0)
    _sz_kb=$(( (_sz_b + 1023) / 1024 ))
    echo "$(basename "$_f")|${_sz_kb}KB"
    _count=$((_count + 1))
    [ "$_count" -ge 15 ] && break
  done
  if [ "$_count" -eq 0 ]; then
    echo "NONE|0KB"
  fi
}

cmd_read() {
  _fn=""
  _tail_n=0
  for _arg in "$@"; do
    case "$_arg" in
      --tail=*) _tail_n=${_arg#--tail=} ;;
      *)        _fn="$_arg" ;;
    esac
  done
  if [ -n "$_tail_n" ] && ! is_uint "$_tail_n"; then
    echo "Invalid --tail value" >&2
    return 1
  fi

  if [ -z "$_fn" ]; then
    _newest=$(ls -1t "$DIAG_DIR"/caventus-realtime-*.log "$DIAG_DIR"/caventus-diag-*.log 2>/dev/null | head -n 1 || true)
    if [ -z "$_newest" ] && [ -f "$BOOT_LOG" ]; then
      _newest="$BOOT_LOG"
    fi
    if [ -z "$_newest" ]; then
      echo "No diagnostic logs found in $DIAG_DIR" >&2
      return 1
    fi
    _fn=$(basename "$_newest")
  fi

  if ! validate_diag_filename "$_fn"; then
    echo "Invalid diagnostic filename: $_fn" >&2
    return 1
  fi

  _target="$DIAG_DIR/$_fn"
  if [ ! -r "$_target" ]; then
    echo "Diagnostic file not found: $_target" >&2
    return 1
  fi

  if [ "$_tail_n" -gt 0 ]; then
    tail -n "$_tail_n" "$_target"
  else
    cat "$_target"
  fi
}

cmd_clear() {
  rm -f "$DIAG_DIR"/caventus-diag-*.log "$DIAG_DIR"/caventus-realtime-*.log "$BOOT_LOG" 2>/dev/null || true
  echo "Diagnostic logs cleared ($DIAG_DIR)."
}

cmd="${1:-list}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
  boot-snapshot)
    cmd_boot_snapshot "$@"
    ;;
  capture)
    cmd_capture "$@"
    ;;
  daemon-start)
    cmd_daemon_start
    ;;
  daemon-stop)
    cmd_daemon_stop
    ;;
  daemon-status)
    cmd_daemon_status
    ;;
  daemon-loop)
    cmd_daemon_loop
    ;;
  daemon-export)
    cmd_daemon_export
    ;;
  daemon-clear)
    cmd_daemon_clear
    ;;
  list)
    cmd_list
    ;;
  read)
    cmd_read "$@"
    ;;
  clear)
    cmd_clear
    ;;
  help|-h|--help)
    echo "Usage: $0 {boot-snapshot <pre|post>|capture [--duration=15] [--interval=3] [--export=1] [--tag=manual]|daemon-start|daemon-stop|daemon-status|daemon-export|daemon-clear|list|read [filename] [--tail=N]|clear}"
    ;;
  *)
    echo "Unknown diag command: $cmd" >&2
    exit 1
    ;;
esac
