# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system` atau `/vendor`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)) untuk memantau memori secara real-time, mengkustomisasi seluruh parameter tuning, dan menjalankan **ART `speed-profile` recompile (`-f`)** langsung dari WebUI maupun tombol **Action (Run/Execute)** di KernelSU Manager.

---

## Profil Default Otomatis `v1.3.0` (*Oriole Optimal*)

Saat pertama kali modul di-flash dan perangkat di-reboot, Caventus otomatis membuat `/data/adb/caventus/config.env` dan menerapkan profil **Oriole Optimal** yang telah diaudit terhadap sysfs/procfs GS101 dan dirancang *boot-safe*:

| Komponen | Nilai Default (`v1.3.0`) | Alasan Teknis (Pixel 6 / GS101) |
| :--- | :--- | :--- |
| **zRAM + `mmd`** | `4096 MB`, `lz77eh`, `mmd_sync=1` | Memanfaatkan akselerator hardware Emerald Hill GS101 (`lz77eh`) dengan overhead CPU minimal; `zstd` tersedia sebagai pilihan di WebUI. |
| **ART / `dex2oat`** | `speed-profile`, `madvise=32 MB` | Menghindari bloat mmap `everything` sekaligus memangkas prefetch odex/vdex dari 100 MB stok ke 32 MB. |
| **LMKD (PSI)** | `use_psi=true`, `partial=50ms`, `thrashing=60`, `swap_low=20%` | Membersihkan app cached sebelum zRAM penuh tanpa mengganggu container/native workload. |
| **Kernel VM & MGLRU** | `swappiness=80`, `watermark_scale=65`, `MGLRU=on` (`0x0003` preserved), `THP=never` | Headroom `kswapd` lebih lega dan nol pemborosan RAM internal THP. |
| **GS101 `vendor_sched`** | `balanced` (`latency_ns=4166666`, `adpf_rampup=2`) | Membuka `sf`/`sys` tanpa membuka `uclamp_max=512` pada grup background. |
| **GS101 `sched_pixel`** | `responsive` per-cluster (`p0=4ms`, `p4=16ms`, `p6=60ms`) | Responsif di core Little/Mid tanpa memicu throttling termal X1. |
| **UFS 3.1 I/O & Mali** | `mq-deadline`, `read_ahead=128 KB`, `nr_requests=128`, `async_depth=64`, `adaptive`, `dvfs=20ms` | Memangkas page-cache RAM dari stok `512–1024 KB` sambil menjaga kestabilan antrean UFS. |
| **SurfaceFlinger** | `off` (stok aman, opt-in `ram_safe`/`ptune`) | Menghilangkan risiko bootloop/flicker Composer HAL pada boot pertama (khususnya tanpa PC/recovery). |

---

## Fitur Utama `v1.3.0`

* **Material 3 Expressive KSU WebUI (`webroot/`):**
  * 4 tab dengan *floating pill navigation bar* & indikator animasi *spring*: **Home**, **Tuning**, **Tools**, **Settings**.
  * 9 palet warna tonal Specter (`blue`, `purple`, `green`, `cyan`, `orange`, `pink`, `red`, `yellow`, `grey`) dalam mode **Auto**, **Light**, **Dark**, dan **AMOLED**.
  * Dukungan dwibahasa (**Indonesia** & **English**) serta 4 profil preset (**Oriole Optimal**, **Heavy / DroidSpaces**, **Pixel Tune GS101**, **Battery Saver**).
* **Kustomisasi Memori, zRAM, Scheduler, UFS & GPU:**
  * **zRAM + Android 17 `mmd` Boot Sync:** ukuran (`1024–6144 MB`), kompresor (`lz77eh`, `zstd`, `lz4`, `lzo-rle`), **OOM guard** sebelum `swapoff`, serta preservasi `backing_dev` & `writeback_limit_enable`.
  * **Sysfs Drift Guard (Watchdog opsional):** loop shell murni ringan (interval `300s`, default OFF) untuk menjaga node VM/sched/IO/GPU agar tidak di-reset sistem.
* **ART Recompile Studio & Tombol Run/Execute (`action.sh`):**
  * Memaksa aplikasi yang sebelumnya terkompilasi `everything` agar beralih ke `speed-profile` menggunakan `cmd package compile -m speed-profile -f <pkg>` (plus opsi `--reset` dan cakupan `Semua Paket` atau `Aplikasi User -3`).

---

## Cara Instalasi & Pemulihan Tanpa PC (*KernelSU Safe Mode*)

1. Unduh **`caventus-oriole-v1.3.0.zip`** dari halaman [**Releases**](https://github.com/aryarifki/caventus/releases) (atau folder `dist/`).
2. Buka **KernelSU Manager** → tab **Modules** → **Install** → pilih zip tersebut, lalu **Reboot**.
3. **Pemulihan Tanpa PC jika terjadi masalah boot:**
   * Saat logo Google muncul di awal boot, **tekan-lepas (tap) tombol Volume Down berulang-ulang (>3 kali)** hingga perangkat masuk ke **KernelSU Safe Mode**.
   * Semua modul otomatis dinonaktifkan; buka **KernelSU Manager** → hapus/nonaktifkan modul, lalu reboot normal.

---

## Build & Verifikasi Lokal

```bash
python3 scripts/build_zip.py
python3 scripts/verify_module.py
```
