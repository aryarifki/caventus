# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)) untuk memantau memori secara real-time, mengkustomisasi seluruh parameter tuning, dan menjalankan **ART `speed-profile` recompile (`-f`)** langsung dari WebUI maupun tombol **Action (Run/Execute)** di KernelSU Manager.

---

## Fitur Utama `v1.1.0`

* **Material 3 Expressive KSU WebUI (`webroot/`):**
  * 4 tab dengan *floating pill navigation bar* & indikator animasi *spring*: **Home**, **Tuning**, **Tools**, **Settings**.
  * 9 palet warna tonal Specter (`blue`, `purple`, `green`, `cyan`, `orange`, `pink`, `red`, `yellow`, `grey`) dalam mode **Auto**, **Light**, **Dark**, dan **AMOLED**.
  * Dukungan dwibahasa (**Indonesia** & **English**).
* **Kustomisasi Penuh & Sinkronisasi Langsung:**
  * **zRAM:** ukuran (`1024–6144 MB`, default `4096 MB`) & kompresor (`zstd`, `lz4`, `lzo-rle`, `lz77eh`) dengan **OOM guard** sebelum `swapoff` dan preservasi `backing_dev` writeback.
  * **ART / `dex2oat`:** filter kompilasi (`speed-profile`, `speed`, `quicken`, `verify`) & batas `madvise` odex/vdex (`32 MB`, turun dari 100 MB stok).
  * **LMKD (PSI):** `use_psi`, `psi_partial_stall_ms` (`50 ms`), `thrashing_limit` (`60`), `swap_free_low_percentage` (`20%`) + `lmkd.reinit` otomatis.
  * **Kernel VM & MGLRU:** `vm.swappiness` (`80`), `vm.watermark_scale_factor` (`60`), `vm.vfs_cache_pressure` (`100`), toggle **MGLRU**.
* **ART Recompile Studio & Tombol Run/Execute (`action.sh`):**
  * Memaksa aplikasi yang sebelumnya terkompilasi `everything` agar beralih ke `speed-profile` menggunakan `cmd package compile -m speed-profile -f <pkg>` (plus opsi `--reset` dan cakupan `Semua Paket` atau `Aplikasi User -3`).
  * Bisa dijalankan lewat **WebUI** (dengan terminal streaming progres `[i/N]` secara live) **atau** lewat tombol **Action (Run/Execute)** di KernelSU Manager.

---

## Cara Instalasi

1. Unduh **`caventus-oriole-v1.1.0.zip`** dari halaman [**Releases**](https://github.com/aryarifki/caventus/releases) (atau folder `dist/`).
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
