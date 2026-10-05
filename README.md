# E-SKRIPSI

Aplikasi pendataan skripsi Program Studi Teknik Elektro, Fakultas Rekayasa Sistem, Universitas Teknologi Sumbawa.

- **Tampilan**: satu berkas `index.html`, dipasang gratis di GitHub Pages.
- **Database dan login**: Supabase (paket gratis).
- Tidak perlu server kampus.

## Isi folder

| Berkas | Fungsi |
|---|---|
| `index.html` | Aplikasinya (tampilan untuk Admin, Dosen, Mahasiswa) |
| `config.js` | Alamat dan kunci Supabase. **Satu-satunya berkas yang perlu Anda ubah.** |
| `supabase/eskripsi.sql` | Skrip pembuat tabel dan aturan di database |
| `.github/workflows/jaga-database.yml` | Menyapa database 2x seminggu agar tidak dijeda Supabase |

## Cara memasang

### 1. Siapkan database di Supabase
1. Masuk ke https://supabase.com, klik **New project**. Pilih region **Southeast Asia (Singapore)**. Simpan *database password* di tempat aman (tidak dipakai aplikasi, tetapi dibutuhkan bila suatu saat perlu pemulihan).
2. Setelah proyek siap, buka **SQL Editor** > **New query**.
3. Buka berkas `supabase/eskripsi.sql`, salin seluruh isinya, tempel ke SQL Editor, klik **Run**. Hasil yang benar: `Success. No rows returned`.

### 2. Sambungkan aplikasi ke database
1. Di Supabase buka **Project Settings** > **API** (atau tombol **Connect** di atas).
2. Salin **Project URL** dan kunci **anon public** (pada tampilan baru bernama **publishable key**).
3. Buka `config.js`, ganti kedua nilainya, simpan.

> Jangan pernah memasukkan kunci **service_role** atau **secret** ke `config.js`. Kunci anon/publishable memang boleh terlihat umum: semua tabel dikunci, dan aplikasi hanya bisa lewat satu pintu yang memeriksa login dan peran.

### 3. Unggah ke GitHub dan nyalakan GitHub Pages
1. Buat repository baru di GitHub (boleh **Public**; GitHub Pages gratis memerlukan repository publik).
2. Unggah seluruh isi folder ini, termasuk folder `.github` dan `supabase`.
3. Buka **Settings** > **Pages**. Pada **Source** pilih **Deploy from a branch**, branch **main**, folder **/ (root)**, lalu **Save**.
4. Tunggu 1–2 menit. Alamat aplikasi muncul di halaman itu, bentuknya `https://NAMAAKUN.github.io/NAMAREPO/`.

### 4. Buat akun Admin pertama
Buka alamat aplikasi. Saat database masih kosong, muncul formulir **Buat Akun Admin Pertama**. Isi nama, username, dan password. Formulir ini hanya muncul satu kali, jadi lakukan segera setelah aplikasi terpasang.

### 5. Mulai dipakai
Masuk sebagai Admin, lalu:
1. **Periode Pendaftaran**: buat periode yang sedang berjalan.
2. **Manajemen User**: buat akun dosen.
3. **Penanda Tangan**: isi nama dan NIDN Dekan serta Ketua Program Studi (dicetak pada undangan, Berita Acara, dan Halaman Pengesahan).
4. **Dokumen**: tambahkan link pedoman dan template.
5. Bagikan alamat aplikasi ke mahasiswa. Mereka mendaftar akun sendiri, lalu Anda setujui.

## Hal yang perlu diketahui

- **Jeda otomatis Supabase.** Paket gratis menjeda proyek yang tidak dipakai 7 hari. Berkas `jaga-database.yml` mencegahnya. Periksa sesekali di tab **Actions** bahwa tugasnya masih berjalan: GitHub mematikan tugas terjadwal bila repository tidak berubah selama 60 hari (cukup klik **Enable workflow** lagi). Jika proyek sempat terjeda, buka dashboard Supabase dan klik **Restore**; data tidak hilang.
- **Lupa password.** Dosen dan mahasiswa: Admin menekan **Reset** di menu Manajemen User, password kembali ke NIM/NIDN dan harus segera diganti pemiliknya. Admin: masuk dengan akun Admin lain. Karena itu sebaiknya buat **dua akun Admin**.
- **Cadangan data.** Paket gratis tidak menyediakan cadangan otomatis yang bisa diunduh. Unduh Excel di menu **Arsip** dan **Periode Pendaftaran** setiap akhir semester.
- **Berkas tidak disimpan di aplikasi.** Syarat seminar, naskah, dan berita acara hanya berupa link (misalnya Google Drive), sehingga database tetap kecil.
- **Memperbarui aplikasi.** Ganti `index.html` di GitHub. Bila `eskripsi.sql` ikut berubah, jalankan ulang di SQL Editor; data yang sudah ada tidak dihapus.
- **Jam dan tanggal** memakai waktu WITA (Asia/Makassar).
