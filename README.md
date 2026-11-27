# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system` atau `/vendor`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)), **ART `speed-profile` recompile (`-f`)**, serta **Forensic Diagnostic Log Capture (`caventus-diag.sh`)** untuk merekam dan mengekspor telemetri lengkap (boot trace, `logcat`, `dmesg`, thermal, PSI, CPUFreq, zRAM/vmstat, LMKD) ke `/sdcard/Download/Caventus-Logs/`.

---

## Pembaruan Utama `v1.4.0` (Thermal-Safe, Anti-Lag & Forensic Diagnostics)

1. **Pencegahan `odrefresh` Recompile Saat Boot (`ART_BOOT_PROPS=0`):** `dalvik.vm.dex2oat-filter` dan `dalvik.vm.image-dex2oat-filter` tidak lagi diinjeksi ke `system.prop` secara default (karena dapat memicu `odrefresh` mengkompilasi ulang ART framework saat boot). Filter `speed-profile` diterapkan ke `pm.dexopt.install`/`bg-dexopt` dan ART Recompile Studio.
2. **Bebas *Freeze* `swapoff` Pasca-Boot (`ZRAM_RUNTIME_RESIZE=0`):** Jika `mmd` boot-sync tidak mengubah ukuran/algoritma `zram0`, skrip runtime tidak lagi membongkar-pasang (`swapoff`/`reset`) 3–4 GB zRAM di background saat UI baru menyala.
3. **GS101 Thermal-Safe Default (`SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock`):** `reduce_prefer_idle=true` dan `groups/sys/prefer_idle=false` dipertahankan sesuai bawaan Pixel 6 agar thread kernel tidak membangunkan core besar dan memicu thermal throttling.
4. **LMKD PSI Longgar (`70/700/80/10%/95%`):** Mencegah badai *kill-respawn* aplikasi latar belakang ketika RAM & zRAM padat.
5. **Forensic Diagnostic Capture (`bin/caventus-diag.sh`):**
   * **Otomatis saat boot (`AUTO_BOOT_DIAG=1`):** merekam `last-boot.log` (`pre`/`post` apply) dan laporan lengkap `--tag=boot`.
   * **On-demand via WebUI (`Tools` → *Diagnostic Log Capture* / tombol cepat *Home*) atau KernelSU Action:** menghasilkan laporan 13 seksi termasuk time-series sampling (`0s` / `15s` / `30s`) yang diekspor ke `/sdcard/Download/Caventus-Logs/latest-caventus-diag.log`.

---

## Profil Default Otomatis `v1.4.0` (*Oriole Safe & Cool*)

| Komponen | Nilai Default (`v1.4.0`) | Keterangan |
| :--- | :--- | :--- |
| **zRAM + `mmd`** | `4096 MB`, `lz77eh`, `mmd_sync=1`, `runtime_resize=0` | Hardware Emerald Hill GS101 tanpa risiko `swapoff` freeze pasca-boot. |
| **ART / `dex2oat`** | `pm.dexopt=speed-profile`, `madvise=64 MB`, `ART_BOOT_PROPS=0` | Tanpa memicu `odrefresh` saat boot. |
| **LMKD (PSI)** | `partial=70ms`, `complete=700ms`, `thrashing=80`, `swap_low=10%`, `swap_util=95%` | Menghindari kill berulang yang membuat app lambat dibuka. |
| **Kernel VM & MGLRU** | `swappiness=70`, `watermark_scale=55`, `dirty=10/20`, `MGLRU=1 (0x0003)`, `THP=never` | Seimbang dan hemat RAM tanpa memicu direct reclaim / thermal tinggi. |
| **GS101 Sched & CPUFreq** | `SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock` | Bebas panas berlebih; profil `balanced`/`responsive` tetap tersedia opt-in. |
| **UFS 3.1 & Mali** | `mq-deadline`, `read_ahead=256 KB`, `nr_requests=128`, `async_depth=64`, `adaptive` | `iostats` dipertahankan aktif untuk analisis diagnostik. |
| **SurfaceFlinger** | `off` | Tidak mengubah properti Composer HAL saat boot. |

---

## Cara Mengambil & Mengirim Log Diagnostik Lengkap

1. Flash **`caventus-oriole-v1.4.0.zip`** di **KernelSU Manager** → **Modules** → **Install**, lalu **Reboot**.
2. Buka **KernelSU Manager** → tap **WebUI** pada Caventus → buka tab **Tools** (atau tap *Tangkap Log Diagnostik (15s)* di **Home**).
3. Pilih durasi (**Instan 0s**, **Normal 15s**, atau **Uji Buka App 30s** sambil membuka aplikasi yang terasa lambat) → tap **Rekam & Ekspor Log Lengkap**.
4. File laporan lengkap tersimpan di **`/sdcard/Download/Caventus-Logs/latest-caventus-diag.log`** dan bisa langsung dilihat/disalin dari modal WebUI.

---

## Pemulihan Tanpa PC (*KernelSU Safe Mode*)

Jika terjadi kendala boot: tahan tombol **Power ±10–15 detik** hingga restart, lalu begitu logo **Google** muncul **tekan-lepas tombol Volume Down berulang (>3 kali)** untuk masuk ke **KernelSU Safe Mode** (menonaktifkan semua modul).

---

## Build & Verifikasi Lokal

```bash
python3 scripts/build_zip.py
python3 scripts/verify_module.py
```
