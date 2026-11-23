# SIAP NEO Native iOS (`.ipa`)

Aplikasi **100% Native SwiftUI iOS** (standalone — langsung terhubung dari iPhone ke server SIAP tanpa butuh server PC/VPS), siap di-compile menjadi file **`SIAPNeo-iOS.ipa`** otomatis lewat **GitHub Actions (`macos-15`, GRATIS)**.

## Fitur Native iOS
- **Login & Sesi SIAP FB + SIAP 3.0** (MD5 API key + Kodular Base64 + cookie web session)
- **Daftar Tugas PIB, Kontainer, Instruksi Lorong, Tambah Dokumen Manual, Selesai/Batal Periksa**
- **Kamera iPhone + CoreLocation GPS + Watermark WIB/PIB/Kontainer + Upload FTP Passive Binary langsung (`ftp.bcpriok.net`)**
- **Apple Vision OCR Nomor Kontainer** (`VNRecognizeTextRequest` bawaan iOS — deteksi otomatis pola ISO 4 huruf + 7 angka seperti `MSCU1234567`)
- **Galeri Foto Online + Hapus Foto**
- **Signature Pad TTD PJ & TTD PPF** (`ttd_ppf/<NIP>.png`)
- **Browse Pendok (SIAP 3.0)** & **Monitoring TPS Live (Graha, NPCT1, TPSL)**
- **Template WhatsApp Cepat**

## Cara Mendapatkan File `SIAPNeo-iOS.ipa` (Gratis Tanpa Mac, ~2 Menit)
1. Buat repositori baru (boleh **Private**) di https://github.com/new (misalnya `siapneo-ios`).
2. Push isi folder `siapneo-ios-native` ini ke repositori tersebut:
   ```powershell
   cd C:\Users\ACER\.gemini\antigravity\scratch\siapneo-ios-native
   git init -b main
   git add .
   git commit -m "Initial SIAP NEO native iOS"
   git remote add origin https://github.com/<USERNAME>/<REPO>.git
   git push -u origin main
   ```
3. Buka tab **Actions** di repositori GitHub Anda → tunggu workflow **Build SIAP NEO iOS IPA** selesai (~2 menit) → klik **Artifacts → `SIAPNeo-iOS-IPA`** untuk mengunduh **`SIAPNeo-iOS.ipa`**.
4. Install **`SIAPNeo-iOS.ipa`** ke iPhone menggunakan:
   - **Sideloadly** (Windows/Mac) / **AltStore** / **SideStore** (dengan Apple ID gratis), atau
   - **TrollStore / ESign / Sertifikat Developer** (tanpa batas 7 hari).
