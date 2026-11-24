# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)** berdasarkan hasil audit sistem langsung.

---

## Mengapa Modul Ini Dibuat? (Baseline Audit Pixel 6)

Dari hasil inspeksi `dumpsys meminfo`, `/proc/meminfo`, dan `/sys/block/zram0` pada Pixel 6 (`oriole`, Android 17):

| Komponen | Kondisi Bawaan (Sebelum) | Optimasi Caventus | Dampak |
| :--- | :--- | :--- | :--- |
| **zRAM** | 3 GB (`lz77eh`), terpakai ~90% (2.7 GB / 863 MB fisik) | **4 GB (`zstd`)**, mempertahankan `backing_dev` writeback + guard anti-OOM saat `swapoff` | Rasio kompresi lebih padat & kapasitas swap lebih lega untuk beban berat/container |
| **ART / dex2oat** | `dex2oat-filter=everything` & `madvise` 100 MB | **`speed-profile`** & `madvise` **32 MB** | Mengurangi pembengkakan `.odex`/`.art` mmap di RAM |
| **LMKD (PSI)** | Ambang standar membuat `Cached` menumpuk (~1.85 GB) sebelum dipangkas | **PSI tuning** (`partial=50ms`, `thrashing=60`, `swap_free_low=20%`) + `lmkd.reinit` | Memangkas app cached lebih dini sebelum zRAM penuh sesak |
| **VM & MGLRU** | `swappiness=60`, `watermark_scale_factor=49`, `dirty=10/20` | `swappiness=80`, `watermark_scale_factor=60`, `dirty=5/15`, MGLRU `min_ttl_ms=1000` | Menyeimbangkan reclaim halaman dingin ke zRAM `zstd` |

---

## Keamanan & Anti-Bootloop

* **Overlay-free:** Tidak ada direktori `system/` — bebas konflik *overlayfs*, *verity*, maupun *SUSFS*.
* **Device Guard:** `customize.sh` memverifikasi `arm64` dan `ro.product.device=oriole` (bisa di-override dengan membuat `/sdcard/.caventus_force`).
* **Writeback & OOM Guard:** `caventus-ctl.sh` mengecek `MemAvailable` sebelum `swapoff` agar tidak memicu OOM, mempertahankan `backing_dev` setelah `zram0/reset`, dan otomatis memulihkan konfigurasi lama jika terjadi error.
* **Uninstall Bersih:** `uninstall.sh` menghapus `/data/adb/caventus` sepenuhnya saat modul dihapus.

---

## Cara Instalasi

1. Unduh **`caventus-oriole-v1.0.0.zip`** dari halaman [**Releases**](https://github.com/aryarifki/caventus/releases) (atau folder `dist/`).
2. Buka **KernelSU Manager** → tab **Modules** → **Install** → pilih file zip tersebut.
3. **Reboot** perangkat.
4. *(Opsional, disarankan sekali saja sambil di-charge)* Jalankan recompile aplikasi yang sudah terlanjur terkompilasi `everything` agar beralih ke `speed-profile`:
   ```sh
   su -c "/data/adb/modules/caventus_oriole_ram/bin/caventus-ctl.sh recompile"
   ```

---

## Penggunaan & Kustomisasi

* **Tombol Action di KernelSU Manager:** Menjalankan `compact` zRAM + `lmkd.reinit` dan menampilkan ringkasan status RAM/zRAM/LMKD/ART.
* **Cek Status via Terminal:**
  ```sh
  su -c "/data/adb/modules/caventus_oriole_ram/bin/caventus-ctl.sh status"
  ```
* **Override Konfigurasi:** Edit `/data/adb/caventus/config.env` (otomatis dibuat saat boot pertama), uncomment parameter yang ingin diubah (mis. `ZRAM_SIZE_MB`, `ZRAM_ALGO`, `VM_SWAPPINESS`), lalu reboot.

---

## Build Lokal

```bash
python3 scripts/build_zip.py
python3 scripts/verify_module.py
```
