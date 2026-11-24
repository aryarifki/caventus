# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)) untuk memantau memori secara real-time, mengkustomisasi seluruh parameter tuning, dan menjalankan **ART `speed-profile` recompile (`-f`)** langsung dari WebUI maupun tombol **Action (Run/Execute)** di KernelSU Manager.

---

## Fitur Utama `v1.2.0`

* **Material 3 Expressive KSU WebUI (`webroot/`):**
  * 4 tab dengan *floating pill navigation bar* & indikator animasi *spring*: **Home**, **Tuning**, **Tools**, **Settings**.
  * 9 palet warna tonal Specter (`blue`, `purple`, `green`, `cyan`, `orange`, `pink`, `red`, `yellow`, `grey`) dalam mode **Auto**, **Light**, **Dark**, dan **AMOLED**.
  * Dukungan dwibahasa (**Indonesia** & **English**) serta 4 profil preset (**Balanced**, **Heavy / DroidSpaces**, **Pixel Tune GS101**, **Battery Saver**).
* **Kustomisasi Memori, zRAM & ART:**
  * **zRAM + Android 17 `mmd` Boot Sync:** ukuran (`1024–6144 MB`, default `4096 MB`), kompresor (`zstd`, `lz4`, `lzo-rle`, `lz77eh`), sinkronisasi `mmd.zram.*` saat boot, **OOM guard** sebelum `swapoff`, serta preservasi `backing_dev` writeback.
  * **ART / `dex2oat`:** filter kompilasi (`speed-profile`, `speed`, `quicken`, `verify`) & batas `madvise` odex/vdex (`32 MB`, turun dari 100 MB stok).
  * **LMKD (PSI):** `use_psi`, `psi_partial_stall_ms` (`50 ms`), `thrashing_limit` (`60`), `swap_free_low_percentage` (`20%`) + `lmkd.reinit` otomatis.
  * **Kernel VM, MGLRU & THP:** `vm.swappiness` (`80`), `vm.watermark_scale_factor` (`60`), `vm.vfs_cache_pressure` (`100`), toggle **MGLRU**, dan **Transparent Hugepages** (`never` default hemat RAM, `madvise`, `always`).
* **Fitur GS101 Teradopsi Aman dari Pixel Tune (`ptune`):**
  * **GS101 `vendor_sched` & `sched_pixel` CPUFreq:** profil `stock`, `balanced`/`responsive`, atau `ptune` tanpa membuka *cpuset* background ke big core.
  * **UFS 3.1 Storage I/O (`/sys/block/sd*`):** pilih scheduler (`mq-deadline`, `kyber`, `bfq`, `none`), `read_ahead_kb` (`128 KB` default), `nr_requests` / `async_depth` (`256`), serta `zram0/queue/read_ahead_kb=0`.
  * **Mali-G78 GPU (`1c500000.mali`):** atur `power_policy` (`adaptive`, `coarse_demand`, `always_on`), `dvfs_period` (`20 ms`), dan buka batas `hint_*` / `scaling_*`.
  * **SurfaceFlinger Grafis:** mode `off`, `ram_safe` (`clear_slots_with_set_layer_buffer`, `use_context_priority`, `force_hwc_copy_for_virtual_displays`), dan `ptune` (`max_frame_buffer_acquired_buffers=6`, `game_default_frame_rate_override=90`, `vendor.powerhal.adpf.rate=1000000`).
  * **Sysfs Drift Guard (Watchdog opsional):** loop shell murni ringan (interval `300s`) untuk menjaga node VM/sched/IO/GPU agar tidak di-reset sistem.
* **ART Recompile Studio & Tombol Run/Execute (`action.sh`):**
  * Memaksa aplikasi yang sebelumnya terkompilasi `everything` agar beralih ke `speed-profile` menggunakan `cmd package compile -m speed-profile -f <pkg>` (plus opsi `--reset` dan cakupan `Semua Paket` atau `Aplikasi User -3`).
  * Bisa dijalankan lewat **WebUI** (dengan terminal streaming progres `[i/N]` secara live) **atau** lewat tombol **Action (Run/Execute)** di KernelSU Manager.

---

## Cara Instalasi

1. Unduh **`caventus-oriole-v1.2.0.zip`** dari halaman [**Releases**](https://github.com/aryarifki/caventus/releases) (atau folder `dist/`).
2. Buka **KernelSU Manager** → tab **Modules** → **Install** → pilih zip tersebut, lalu **Reboot**.
3. Setelah reboot:
   * Tap **WebUI** pada kartu modul Caventus untuk memantau RAM/zRAM, mengatur tuning, atau menjalankan **Recompile Aplikasi (`speed-profile`)**.
   * Atau tap tombol **Action (Run/Execute)** di KernelSU Manager untuk menjalankan `compact` + `recompile` secara langsung.

---

## Build & Verifikasi Lokal

```bash
python3 scripts/build_zip.py
python3 scripts/verify_module.py
```
