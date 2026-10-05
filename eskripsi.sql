-- =====================================================================
-- E-SKRIPSI · skrip database untuk Supabase
-- Jalankan seluruh isi berkas ini di Supabase: SQL Editor > New query > Run.
-- Aman dijalankan ulang: tabel tidak dihapus, fungsi diperbarui.
--
-- Rancangan keamanan:
--   * Semua tabel ada di skema "app" yang TIDAK dibuka ke internet.
--   * Satu-satunya pintu masuk adalah fungsi public.api(token, aksi, data).
--   * Setiap aksi memeriksa sesi dan peran pengguna di dalam database.
--   * Password disimpan sebagai hash bcrypt, token sesi disimpan sebagai hash.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create schema if not exists app;
revoke all on schema app from public;

-- ---------------------------------------------------------------- tabel
create table if not exists app.pengguna (
  id bigint generated always as identity primary key,
  role text not null check (role in ('admin','dosen','mahasiswa')),
  nama text not null,
  username text not null,
  sandi text not null,
  nomor text,                       -- NIM (mahasiswa), NIDN (dosen), NIP (admin)
  angkatan text, jk text, tlahir text, tgllahir date,
  email text, hp text, alamat text, jabatan text, keahlian text,
  foto text,
  nonaktif boolean not null default false,
  nonaktif_arsip boolean not null default false,
  pw_reset date,
  dibuat timestamptz not null default now()
);
create unique index if not exists pengguna_username_uq on app.pengguna (lower(username));
create unique index if not exists pengguna_nomor_uq on app.pengguna (nomor) where nomor is not null;

create table if not exists app.sesi (
  token_hash text primary key,
  pengguna_id bigint not null references app.pengguna(id) on delete cascade,
  kedaluwarsa timestamptz not null
);
create table if not exists app.login_gagal (username text not null, waktu timestamptz not null default now());
create index if not exists login_gagal_ix on app.login_gagal (username, waktu);

create table if not exists app.akun_req (
  id bigint generated always as identity primary key,
  nama text not null, nim text not null, angkatan text, email text, hp text,
  status text not null default 'menunggu' check (status in ('menunggu','disetujui','ditolak')),
  username text, tgl date not null
);

create table if not exists app.periode (
  id bigint generated always as identity primary key,
  ta text not null, sem text not null check (sem in ('Ganjil','Genap')),
  buka date not null, tutup date not null,
  manual_tutup boolean not null default false,
  akses_skripsi boolean not null default true,
  akses_proposal boolean not null default true,
  akses_sidang boolean not null default true,
  unique (ta, sem)
);

create table if not exists app.skripsi (
  id bigint generated always as identity primary key,
  mhs_id bigint not null unique references app.pengguna(id),
  judul text not null, bidang text, ipk text, sks text,
  periode_id bigint references app.periode(id),
  status text not null default 'menunggu' check (status in ('menunggu','disetujui','ditolak')),
  tgl date not null,
  arsip date,
  naskah_link text, naskah_tgl date,
  survey jsonb, survey_tgl date,
  judul_lama jsonb not null default '[]'::jsonb
);

create table if not exists app.tim (
  skripsi_id bigint not null references app.skripsi(id) on delete cascade,
  peran text not null check (peran in ('Pembimbing','Penguji 1','Penguji 2')),
  dosen_id bigint not null references app.pengguna(id),
  status text not null default 'menunggu' check (status in ('menunggu','diterima','ditolak')),
  acc_status text check (acc_status in ('menunggu','disetujui','revisi')),
  acc_cat text, acc_tgl date,
  primary key (skripsi_id, peran)
);
create index if not exists tim_dosen_ix on app.tim (dosen_id);

-- pendaftaran seminar proposal dan sidang akhir (alurnya sama)
create table if not exists app.daftar (
  id bigint generated always as identity primary key,
  jenis text not null check (jenis in ('proposal','sidang')),
  skripsi_id bigint not null references app.skripsi(id) on delete cascade,
  mhs_id bigint not null references app.pengguna(id),
  periode_id bigint references app.periode(id),
  link text not null, ket text not null default '', tgl date not null,
  status text not null check (status in ('menunggu_pembimbing','menunggu_admin','disetujui','ditolak_pembimbing','dikembalikan_admin','mengulang')),
  cat_pb text not null default '', cat_adm text not null default '',
  j_tgl date, j_jam text, j_ruang text, j_no int,
  h_nilai text check (h_nilai in ('lulus','revisi','ulang')), h_cat text, h_link text, h_tgl date,
  unique (jenis, skripsi_id)
);

-- jalur non skripsi dan nilai akhir (ditambahkan belakangan; aman dijalankan ulang)
alter table app.skripsi add column if not exists jalur text not null default 'skripsi';
alter table app.skripsi add column if not exists rekognisi text;
alter table app.daftar add column if not exists h_angka numeric(5,2);

create table if not exists app.notif (
  id bigint generated always as identity primary key,
  ke bigint not null references app.pengguna(id) on delete cascade,
  msg text not null, t date not null, baru boolean not null default true
);
create index if not exists notif_ke_ix on app.notif (ke, id desc);

create table if not exists app.dokumen (
  id bigint generated always as identity primary key,
  nama text not null, ket text not null default '', link text not null, tgl date not null
);

create table if not exists app.pengaturan (kunci text primary key, nilai jsonb not null);
insert into app.pengaturan values ('pejabat','{"dekan":"","dekanNidn":"","kp":"","kpNidn":""}') on conflict do nothing;

-- kunci tabel: tidak ada peran internet yang boleh menyentuh tabel secara langsung
alter table app.pengguna enable row level security;   alter table app.sesi enable row level security;
alter table app.login_gagal enable row level security; alter table app.akun_req enable row level security;
alter table app.periode enable row level security;     alter table app.skripsi enable row level security;
alter table app.tim enable row level security;         alter table app.daftar enable row level security;
alter table app.notif enable row level security;       alter table app.dokumen enable row level security;
alter table app.pengaturan enable row level security;

-- -------------------------------------------------------------- pembantu
create or replace function app.hari() returns date language sql stable as
$$ select (now() at time zone 'Asia/Makassar')::date $$;

create or replace function app.tgl_id(d date) returns text language sql immutable as
$$ select case when d is null then null else extract(day from d)::int || ' ' ||
  (array['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'])[extract(month from d)::int] || ' ' || extract(year from d)::int end $$;

create or replace function app.tgl_panjang(d date) returns text language sql immutable as
$$ select extract(day from d)::int || ' ' ||
  (array['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'])[extract(month from d)::int] || ' ' || extract(year from d)::int $$;

create or replace function app.hari_tgl(d date) returns text language sql immutable as
$$ select (array['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'])[extract(dow from d)::int + 1] || ', ' || app.tgl_panjang(d) $$;

create or replace function app.huruf(n numeric) returns text language sql immutable as
$$ select case when n is null then null when n >= 85 then 'A' when n >= 80 then 'A-' when n >= 75 then 'B+' when n >= 70 then 'B' when n >= 65 then 'B-'
            when n >= 60 then 'C+' when n >= 55 then 'C' else 'Tidak Lulus' end $$;

create or replace function app.galat(pesan text) returns void language plpgsql as
$$ begin raise exception '%', pesan using errcode = 'P0001'; end $$;

create or replace function app.teks(d jsonb, k text) returns text language sql immutable as
$$ select nullif(btrim(d ->> k), '') $$;

create or replace function app.link_sah(l text) returns boolean language sql immutable as
$$ select l ~* '^https?://[^[:space:]]+\.[^[:space:]]+' $$;

create or replace function app.notif(p_ke bigint, p_msg text) returns void language plpgsql as $$
begin
  if p_ke is null then return; end if;
  if (select msg from app.notif where ke = p_ke order by id desc limit 1) is not distinct from p_msg then return; end if;
  insert into app.notif (ke, msg, t) values (p_ke, p_msg, app.hari());
end $$;

create or replace function app.notif_role(p_role text, p_msg text) returns void language plpgsql as $$
declare r record;
begin
  for r in select id from app.pengguna where role = p_role and not nonaktif loop perform app.notif(r.id, p_msg); end loop;
end $$;

create or replace function app.notif_tim(p_skripsi bigint, p_msg text, p_mhs boolean default true) returns void language plpgsql as $$
declare r record;
begin
  if p_mhs then perform app.notif((select mhs_id from app.skripsi where id = p_skripsi), p_msg); end if;
  for r in select dosen_id from app.tim where skripsi_id = p_skripsi loop perform app.notif(r.dosen_id, p_msg); end loop;
end $$;

-- periode yang sedang berjalan; jika p_jenis diisi, aksesnya juga harus terbuka
create or replace function app.periode_aktif(p_jenis text default null) returns bigint language sql stable as $$
  select id from app.periode
  where buka <= app.hari() and tutup >= app.hari() and not manual_tutup
    and (p_jenis is null or (p_jenis = 'skripsi' and akses_skripsi) or (p_jenis = 'proposal' and akses_proposal) or (p_jenis = 'sidang' and akses_sidang))
  limit 1 $$;

create or replace function app.status_periode(p app.periode) returns text language sql stable as $$
  select case when p.manual_tutup and app.hari() between p.buka and p.tutup then 'ditutup'
              when app.hari() < p.buka then 'terjadwal' when app.hari() > p.tutup then 'berakhir' else 'dibuka' end $$;

create or replace function app.acc_lengkap(p_skripsi bigint) returns boolean language sql stable as
$$ select count(*) filter (where acc_status = 'disetujui') = 3 from app.tim where skripsi_id = p_skripsi $$;

-- tahap skripsi mengikuti alur: 0 Penyusunan Proposal, 1 Seminar Proposal, 2 Penelitian,
-- 3 Sidang Akhir, 4 Persetujuan Dosen, 5 Survey Kepuasan, 6 Selesai
create or replace function app.tahap(p_skripsi bigint) returns int language plpgsql stable as $$
declare pr app.daftar; sd app.daftar; s app.skripsi;
begin
  select * into s from app.skripsi where id = p_skripsi;
  select * into pr from app.daftar where skripsi_id = p_skripsi and jenis = 'proposal' and status = 'disetujui';
  select * into sd from app.daftar where skripsi_id = p_skripsi and jenis = 'sidang' and status = 'disetujui';
  if (s.jalur = 'nonskripsi' and pr.id is not null and pr.h_nilai in ('lulus','revisi')) or (sd.id is not null and sd.h_nilai in ('lulus','revisi')) then
    return case when s.survey is not null then 6 when app.acc_lengkap(p_skripsi) then 5 else 4 end;
  end if;
  if s.jalur = 'nonskripsi' then return case when pr.id is not null then 1 else 0 end; end if;
  if sd.id is not null then return 3; end if;
  if pr.id is not null and pr.h_nilai in ('lulus','revisi') then return 2; end if;
  if pr.id is not null then return 1; end if;
  return 0;
end $$;

create or replace function app.identitas_kurang(u app.pengguna) returns boolean language sql immutable as
$$ select u.role in ('dosen','mahasiswa') and (u.jk is null or u.tlahir is null or u.tgllahir is null or u.email is null or u.hp is null) $$;

create or replace function app.sandi_sah(p text) returns void language plpgsql as
$$ begin if p is null or length(p) < 6 then perform app.galat('Password minimal 6 karakter'); end if; end $$;

create or replace function app.hash_sandi(p text) returns text language sql as
$$ select extensions.crypt(p, extensions.gen_salt('bf', 10)) $$;

-- --------------------------------------------------------- data untuk layar
create or replace function app.j_pengguna(u app.pengguna, p_lengkap boolean, p_admin boolean) returns jsonb language sql stable as $$
  select jsonb_strip_nulls(
    jsonb_build_object('id', u.id, 'nama', u.nama, 'role', u.role,
      case u.role when 'mahasiswa' then 'nim' when 'dosen' then 'nidn' else 'nip' end, u.nomor,
      'adaFoto', case when u.foto is not null then true end)
    || case when p_lengkap then jsonb_build_object('username', u.username, 'angkatan', u.angkatan, 'jk', u.jk, 'tlahir', u.tlahir,
         'tgllahir', u.tgllahir::text, 'email', u.email, 'hp', u.hp, 'alamat', u.alamat, 'jabatan', u.jabatan, 'keahlian', u.keahlian,
         'nonaktif', case when u.nonaktif then true end, 'pwReset', app.tgl_id(u.pw_reset)) else '{}'::jsonb end
    || case when p_admin and u.pw_reset is not null then jsonb_build_object('password', coalesce(u.nomor, u.username)) else '{}'::jsonb end) $$;

create or replace function app.j_skripsi(s app.skripsi) returns jsonb language sql stable as $$
  select jsonb_strip_nulls(jsonb_build_object('id', s.id, 'mhsId', s.mhs_id, 'judul', s.judul, 'bidang', s.bidang, 'ipk', s.ipk, 'sks', s.sks,
    'periodeId', s.periode_id, 'jalur', s.jalur, 'rekognisi', s.rekognisi, 'status', s.status, 'tgl', app.tgl_id(s.tgl), 'arsip', s.arsip::text,
    'naskah', case when s.naskah_link is not null then jsonb_build_object('link', s.naskah_link, 'tgl', app.tgl_id(s.naskah_tgl)) end,
    'acc', (select jsonb_object_agg(t.peran, jsonb_build_object('status', t.acc_status, 'cat', coalesce(t.acc_cat, ''), 'tgl', coalesce(app.tgl_id(t.acc_tgl), '')))
            from app.tim t where t.skripsi_id = s.id and t.acc_status is not null),
    'survey', case when s.survey is not null then s.survey || jsonb_build_object('tgl', app.tgl_id(s.survey_tgl), 'iso', s.survey_tgl::text) end))
    || jsonb_build_object('tim', (select coalesce(jsonb_agg(jsonb_build_object('dosenId', t.dosen_id, 'peran', t.peran, 'status', t.status) order by t.peran), '[]'::jsonb)
                                  from app.tim t where t.skripsi_id = s.id),
                          'judulLama', s.judul_lama) $$;

create or replace function app.j_daftar(p app.daftar) returns jsonb language sql stable as $$
  select jsonb_strip_nulls(jsonb_build_object('id', p.id, 'jenis', p.jenis, 'periodeId', p.periode_id, 'skripsiId', p.skripsi_id, 'mhsId', p.mhs_id,
    'link', p.link, 'tgl', app.tgl_id(p.tgl), 'status', p.status,
    'jadwal', case when p.j_tgl is not null then jsonb_build_object('tgl', p.j_tgl::text, 'jam', p.j_jam, 'ruang', p.j_ruang, 'no', p.j_no) end,
    'hasil', case when p.h_nilai is not null then jsonb_build_object('nilai', p.h_nilai, 'angka', p.h_angka, 'huruf', app.huruf(p.h_angka), 'cat', coalesce(p.h_cat, ''), 'link', coalesce(p.h_link, ''), 'tgl', app.tgl_id(p.h_tgl)) end))
    || jsonb_build_object('ket', p.ket, 'catPb', p.cat_pb, 'catAdm', p.cat_adm) $$;

-- seluruh data yang boleh dilihat pengguna ini, dalam bentuk yang dipakai tampilan
create or replace function app.muat(u app.pengguna) returns jsonb language plpgsql stable as $$
declare ids bigint[]; hasil jsonb;
begin
  if u.role = 'admin' then
    select array_agg(id) into ids from app.skripsi;
  elsif u.role = 'dosen' then
    select array_agg(s.id) into ids from app.skripsi s where s.arsip is null and exists (select 1 from app.tim t where t.skripsi_id = s.id and t.dosen_id = u.id);
  else
    select array_agg(id) into ids from app.skripsi where mhs_id = u.id;
  end if;
  ids := coalesce(ids, '{}');
  hasil := jsonb_build_object(
    'me', u.id,
    'hari', app.hari()::text,
    'users', (select coalesce(jsonb_agg(app.j_pengguna(p, u.role = 'admin' or p.id = u.id, u.role = 'admin') order by p.id), '[]'::jsonb) from app.pengguna p
              where u.role = 'admin' or p.id = u.id
                 or (u.role = 'dosen' and (p.role = 'dosen' or p.id in (select mhs_id from app.skripsi where id = any(ids))))
                 or (u.role = 'mahasiswa' and p.id in (select dosen_id from app.tim where skripsi_id = any(ids)))),
    'akunReq', case when u.role = 'admin' then (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', id, 'nama', nama, 'nim', nim, 'angkatan', angkatan,
                 'email', email, 'hp', hp, 'status', status, 'username', username, 'tgl', app.tgl_id(tgl))) order by id), '[]'::jsonb) from app.akun_req) else '[]'::jsonb end,
    'skripsi', (select coalesce(jsonb_agg(app.j_skripsi(s) order by s.id), '[]'::jsonb) from app.skripsi s where s.id = any(ids)),
    'proposal', (select coalesce(jsonb_agg(app.j_daftar(p) order by p.id), '[]'::jsonb) from app.daftar p where p.jenis = 'proposal' and p.skripsi_id = any(ids)),
    'sidang', (select coalesce(jsonb_agg(app.j_daftar(p) order by p.id), '[]'::jsonb) from app.daftar p where p.jenis = 'sidang' and p.skripsi_id = any(ids)),
    'notif', (select coalesce(jsonb_agg(jsonb_build_object('to', n.ke, 'msg', n.msg, 't', app.tgl_id(n.t), 'baru', n.baru) order by n.id desc), '[]'::jsonb)
              from (select * from app.notif where ke = u.id order by id desc limit 60) n),
    'periode', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ta', ta, 'sem', sem, 'buka', buka::text, 'tutup', tutup::text, 'manualTutup', manual_tutup,
                 'akses', jsonb_build_object('skripsi', akses_skripsi, 'proposal', akses_proposal, 'sidang', akses_sidang)) order by buka), '[]'::jsonb) from app.periode),
    'dokumen', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nama', nama, 'ket', ket, 'link', link, 'tgl', app.tgl_id(tgl)) order by id), '[]'::jsonb) from app.dokumen),
    'pejabat', (select nilai from app.pengaturan where kunci = 'pejabat'));
  return hasil;
end $$;

-- ------------------------------------------------------------------ sesi
create or replace function app.siapa(p_token text) returns app.pengguna language plpgsql as $$
declare u app.pengguna; h text;
begin
  if p_token is null or length(p_token) < 32 then raise exception 'Sesi berakhir. Silakan masuk kembali.' using errcode = 'P0002'; end if;
  h := encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  select p.* into u from app.sesi s join app.pengguna p on p.id = s.pengguna_id where s.token_hash = h and s.kedaluwarsa > now();
  if u.id is null or u.nonaktif then
    delete from app.sesi where token_hash = h;
    raise exception 'Sesi berakhir. Silakan masuk kembali.' using errcode = 'P0002';
  end if;
  update app.sesi set kedaluwarsa = now() + interval '12 hours' where token_hash = h and kedaluwarsa < now() + interval '11 hours';
  return u;
end $$;

create or replace function app.buat_sesi(p_id bigint) returns text language plpgsql as $$
declare tok text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  delete from app.sesi where kedaluwarsa < now();
  insert into app.sesi values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), p_id, now() + interval '12 hours');
  return tok;
end $$;

-- ================================================================== AKSI
-- Setiap fungsi a_* menjalankan satu aksi dan mengembalikan pesan untuk ditampilkan.

create or replace function app.a_profil(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare dulu boolean := app.identitas_kurang(u); baru app.pengguna; tgl date;
begin
  if app.teks(d, 'nama') is null then perform app.galat('Nama tidak boleh kosong'); end if;
  begin tgl := app.teks(d, 'tgllahir')::date; exception when others then perform app.galat('Tanggal lahir tidak sah'); end;
  if app.teks(d, 'jk') is not null and app.teks(d, 'jk') not in ('Laki-laki','Perempuan') then perform app.galat('Jenis kelamin tidak sah'); end if;
  update app.pengguna set nama = left(app.teks(d, 'nama'), 120), jk = app.teks(d, 'jk'), tlahir = left(app.teks(d, 'tlahir'), 80), tgllahir = tgl,
    email = left(app.teks(d, 'email'), 120), hp = left(app.teks(d, 'hp'), 30), alamat = left(app.teks(d, 'alamat'), 300),
    angkatan = case when role = 'mahasiswa' then left(app.teks(d, 'angkatan'), 10) else angkatan end,
    jabatan = case when role <> 'mahasiswa' then app.teks(d, 'jabatan') else jabatan end,
    keahlian = case when role <> 'mahasiswa' then left(app.teks(d, 'keahlian'), 120) else keahlian end
  where id = u.id returning * into baru;
  if app.identitas_kurang(baru) then return 'Tersimpan, tetapi data wajib belum lengkap'; end if;
  return case when dulu then 'Identitas lengkap. Semua menu sudah bisa digunakan.' else 'Identitas diri tersimpan' end;
end $$;

create or replace function app.a_foto(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare f text := d ->> 'foto';
begin
  if f is null then update app.pengguna set foto = null where id = u.id; return 'Foto dihapus'; end if;
  if f !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$' then perform app.galat('Format foto harus JPG atau PNG'); end if;
  if length(f) > 120000 then perform app.galat('Ukuran foto terlalu besar'); end if;
  update app.pengguna set foto = f where id = u.id;
  return 'Foto diperbarui';
end $$;

create or replace function app.a_sandi(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare lama text := d ->> 'lama'; baru text := d ->> 'baru';
begin
  if u.sandi <> extensions.crypt(coalesce(lama, ''), u.sandi) then perform app.galat('Password lama tidak sesuai'); end if;
  perform app.sandi_sah(baru);
  if baru = lama then perform app.galat('Password baru harus berbeda dari password lama'); end if;
  update app.pengguna set sandi = app.hash_sandi(baru), pw_reset = null where id = u.id;
  return 'Password berhasil diganti';
end $$;

create or replace function app.a_notif_baca(u app.pengguna, d jsonb) returns text language plpgsql as
$$ begin update app.notif set baru = false where ke = u.id and baru; return null; end $$;

-- ---- akun (Admin)
create or replace function app.cek_akun_baru(p_username text, p_sandi text, p_nomor text) returns void language plpgsql as $$
begin
  if p_username is null or p_username !~ '^[A-Za-z0-9._-]{3,40}$' then perform app.galat('Username 3–40 karakter: huruf, angka, titik, garis bawah, atau tanda hubung'); end if;
  perform app.sandi_sah(p_sandi);
  if exists (select 1 from app.pengguna where lower(username) = lower(p_username)) then perform app.galat('Username sudah dipakai, gunakan yang lain'); end if;
  if p_nomor is not null and exists (select 1 from app.pengguna where nomor = p_nomor) then perform app.galat('Nomor induk sudah terdaftar'); end if;
end $$;

create or replace function app.a_akun_setujui(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare r app.akun_req; un text := app.teks(d, 'username'); pw text := d ->> 'sandi'; idb bigint;
begin
  select * into r from app.akun_req where id = (d ->> 'id')::bigint and status = 'menunggu' for update;
  if r.id is null then perform app.galat('Pendaftaran akun ini sudah diproses'); end if;
  perform app.cek_akun_baru(un, pw, r.nim);
  insert into app.pengguna (role, nama, username, sandi, nomor, angkatan, email, hp)
    values ('mahasiswa', r.nama, un, app.hash_sandi(pw), r.nim, r.angkatan, r.email, r.hp) returning id into idb;
  update app.akun_req set status = 'disetujui', username = un where id = r.id;
  perform app.notif(idb, 'Selamat datang! Akun Anda sudah aktif. Lengkapi Identitas Diri, lalu ajukan pendaftaran skripsi.');
  return 'Akun dibuat untuk ' || r.nama || '. Sampaikan username dan password awalnya.';
end $$;

create or replace function app.a_akun_tolak(u app.pengguna, d jsonb) returns text language plpgsql as $$
begin
  update app.akun_req set status = 'ditolak' where id = (d ->> 'id')::bigint and status = 'menunggu';
  return 'Pendaftaran akun ditolak';
end $$;

create or replace function app.a_akun_tambah(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare r text := d ->> 'role'; un text := app.teks(d, 'username'); no text := app.teks(d, 'nomor'); idb bigint;
begin
  if r not in ('mahasiswa','dosen','admin') then perform app.galat('Peran tidak sah'); end if;
  if app.teks(d, 'nama') is null then perform app.galat('Nama tidak boleh kosong'); end if;
  if no is null then perform app.galat('Nomor induk tidak boleh kosong'); end if;
  perform app.cek_akun_baru(un, d ->> 'sandi', no);
  insert into app.pengguna (role, nama, username, sandi, nomor, email)
    values (r, left(app.teks(d, 'nama'), 120), un, app.hash_sandi(d ->> 'sandi'), no, app.teks(d, 'email')) returning id into idb;
  perform app.notif(idb, 'Selamat datang! Akun Anda sudah aktif. Lengkapi Identitas Diri Anda.');
  return 'Akun ' || initcap(r) || ' dibuat: ' || un;
end $$;

create or replace function app.a_akun_reset(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare t app.pengguna;
begin
  select * into t from app.pengguna where id = (d ->> 'id')::bigint;
  if t.id is null or t.id = u.id then perform app.galat('Akun tidak dapat direset'); end if;
  update app.pengguna set sandi = app.hash_sandi(coalesce(t.nomor, t.username)), pw_reset = app.hari() where id = t.id;
  delete from app.sesi where pengguna_id = t.id;
  perform app.notif(t.id, 'Password Anda direset ke default oleh Admin. Segera ganti password setelah masuk.');
  return 'Password ' || t.username || ' direset ke default';
end $$;

create or replace function app.a_akun_toggle(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare t app.pengguna;
begin
  select * into t from app.pengguna where id = (d ->> 'id')::bigint;
  if t.id is null or t.id = u.id then perform app.galat('Akun tidak dapat diubah'); end if;
  update app.pengguna set nonaktif = not t.nonaktif, nonaktif_arsip = false where id = t.id;
  if not t.nonaktif then delete from app.sesi where pengguna_id = t.id; end if;
  return 'Akun ' || t.username || case when t.nonaktif then ' diaktifkan' else ' dinonaktifkan' end;
end $$;

create or replace function app.a_akun_hapus(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare t app.pengguna;
begin
  select * into t from app.pengguna where id = (d ->> 'id')::bigint;
  if t.id is null or t.id = u.id then perform app.galat('Akun tidak dapat dihapus'); end if;
  if t.role = 'mahasiswa' and exists (select 1 from app.skripsi where mhs_id = t.id) then
    perform app.galat('Akun ini punya data skripsi, jadi tidak bisa dihapus. Nonaktifkan saja.'); end if;
  if t.role = 'dosen' and exists (select 1 from app.tim where dosen_id = t.id) then
    perform app.galat('Dosen ini masih tercatat sebagai pembimbing/penguji, jadi tidak bisa dihapus. Nonaktifkan saja.'); end if;
  if t.role = 'admin' and (select count(*) from app.pengguna where role = 'admin' and not nonaktif) <= 1 then
    perform app.galat('Admin terakhir tidak bisa dihapus'); end if;
  delete from app.pengguna where id = t.id;
  return 'Akun ' || t.username || ' dihapus';
end $$;

-- ---- periode (Admin)
create or replace function app.cek_tanggal_periode(p_id bigint, p_buka date, p_tutup date) returns void language plpgsql as $$
declare o app.periode;
begin
  if p_buka is null or p_tutup is null or p_tutup < p_buka then perform app.galat('Tanggal ditutup harus sama atau setelah tanggal dibuka'); end if;
  select * into o from app.periode where id is distinct from p_id and p_buka <= tutup and p_tutup >= buka limit 1;
  if o.id is not null then perform app.galat('Tanggal bentrok dengan periode ' || o.ta || ' ' || o.sem); end if;
end $$;

create or replace function app.a_periode_tambah(u app.pengguna, d jsonb) returns text language plpgsql as $$
<<f>> declare ta text := app.teks(d, 'ta'); sem text := app.teks(d, 'sem'); b date; t date; p app.periode;
begin
  begin b := (d ->> 'buka')::date; t := (d ->> 'tutup')::date; exception when others then perform app.galat('Tanggal tidak sah'); end;
  if ta is null or ta !~ '^\d{4}/\d{4}$' or sem not in ('Ganjil','Genap') then perform app.galat('Tahun akademik atau semester tidak sah'); end if;
  perform app.cek_tanggal_periode(null, b, t);
  if exists (select 1 from app.periode where periode.ta = f.ta and periode.sem = f.sem) then perform app.galat('Periode ' || ta || ' ' || sem || ' sudah ada'); end if;
  insert into app.periode (ta, sem, buka, tutup) values (ta, sem, b, t) returning * into p;
  if app.status_periode(p) = 'dibuka' then perform app.notif_role('mahasiswa', 'Periode ' || ta || ' Semester ' || sem || ' dibuka sampai ' || app.tgl_panjang(t) || '.'); end if;
  return 'Periode tersimpan';
end $$;

create or replace function app.a_periode_tanggal(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.periode; q app.periode; nb date; nt date; s0 text; s1 text;
begin
  select * into p from app.periode where id = (d ->> 'id')::bigint for update;
  if p.id is null then perform app.galat('Periode tidak ditemukan'); end if;
  begin nb := case when d ->> 'f' = 'buka' then (d ->> 'nilai')::date else p.buka end;
        nt := case when d ->> 'f' = 'tutup' then (d ->> 'nilai')::date else p.tutup end;
  exception when others then perform app.galat('Tanggal tidak sah'); end;
  perform app.cek_tanggal_periode(p.id, nb, nt);
  s0 := app.status_periode(p);
  update app.periode set buka = nb, tutup = nt, manual_tutup = false where id = p.id returning * into q;
  s1 := app.status_periode(q);
  if s0 <> s1 and 'dibuka' in (s0, s1) then
    perform app.notif_role('mahasiswa', 'Periode ' || p.ta || ' Semester ' || p.sem || case when s1 = 'dibuka' then ' dibuka sampai ' || app.tgl_panjang(nt) || '.' else ' telah ditutup.' end);
  end if;
  return 'Tanggal periode diperbarui';
end $$;

create or replace function app.a_periode_aksi(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.periode; a text := d ->> 'aksi'; vbuka boolean;
begin
  select * into p from app.periode where id = (d ->> 'id')::bigint for update;
  if p.id is null then perform app.galat('Periode tidak ditemukan'); end if;
  if a = 'tutup' then update app.periode set manual_tutup = true where id = p.id;
  elsif a = 'bukalagi' then update app.periode set manual_tutup = false where id = p.id;
  elsif a = 'buka' then
    perform app.cek_tanggal_periode(p.id, app.hari(), p.tutup);
    update app.periode set buka = app.hari(), manual_tutup = false where id = p.id;
  else perform app.galat('Aksi tidak dikenal'); end if;
  vbuka := a <> 'tutup';
  perform app.notif_role('mahasiswa', 'Periode ' || p.ta || ' Semester ' || p.sem || case when vbuka then ' dibuka sampai ' || app.tgl_panjang(p.tutup) || '.' else ' telah ditutup.' end);
  return case when vbuka then 'Periode pendaftaran dibuka' else 'Periode pendaftaran ditutup' end;
end $$;

create or replace function app.a_periode_akses(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare pid bigint := app.periode_aktif(); j text := d ->> 'jenis'; nyala boolean; nama text;
begin
  if pid is null then perform app.galat('Tidak ada periode yang sedang berjalan'); end if;
  if j = 'skripsi' then update app.periode set akses_skripsi = not akses_skripsi where id = pid returning akses_skripsi into nyala; nama := 'skripsi';
  elsif j = 'proposal' then update app.periode set akses_proposal = not akses_proposal where id = pid returning akses_proposal into nyala; nama := 'seminar proposal';
  elsif j = 'sidang' then update app.periode set akses_sidang = not akses_sidang where id = pid returning akses_sidang into nyala; nama := 'sidang akhir';
  else perform app.galat('Jenis akses tidak dikenal'); end if;
  perform app.notif_role('mahasiswa', 'Pendaftaran ' || nama || case when nyala then ' dibuka kembali.' else ' telah ditutup.' end);
  return 'Akses pendaftaran ' || nama || case when nyala then ' dibuka' else ' ditutup' end;
end $$;

-- ---- skripsi
create or replace function app.a_skripsi_daftar(u app.pengguna, d jsonb) returns text language plpgsql as $$
<<f>> declare pid bigint := app.periode_aktif('skripsi'); s app.skripsi; judul text := app.teks(d, 'judul'); vjalur text := coalesce(app.teks(d, 'jalur'), 'skripsi'); vrek text := app.teks(d, 'rekognisi');
begin
  if pid is null then perform app.galat('Periode pendaftaran skripsi sedang ditutup'); end if;
  if judul is null or length(judul) < 10 then perform app.galat('Judul terlalu pendek'); end if;
  if vjalur not in ('skripsi','nonskripsi') then perform app.galat('Jalur tidak dikenal'); end if;
  if vjalur = 'nonskripsi' and (vrek is null or not app.link_sah(vrek)) then perform app.galat('Jalur non skripsi wajib melampirkan link surat rekognisi (diawali http:// atau https://)'); end if;
  if vjalur = 'skripsi' then vrek := null; end if;
  select * into s from app.skripsi where mhs_id = u.id for update;
  if s.id is not null and s.status <> 'ditolak' then perform app.galat('Anda sudah terdaftar sebagai mahasiswa skripsi'); end if;
  if s.id is null then
    insert into app.skripsi (mhs_id, judul, bidang, ipk, sks, periode_id, tgl, jalur, rekognisi) values (u.id, left(judul, 300), app.teks(d, 'bidang'), left(app.teks(d, 'ipk'), 8), left(app.teks(d, 'sks'), 8), pid, app.hari(), vjalur, left(vrek, 500));
  else
    update app.skripsi set judul = left(f.judul, 300), bidang = app.teks(d, 'bidang'), ipk = left(app.teks(d, 'ipk'), 8), sks = left(app.teks(d, 'sks'), 8),
      periode_id = pid, status = 'menunggu', tgl = app.hari(), jalur = vjalur, rekognisi = left(vrek, 500) where id = s.id;
  end if;
  perform app.notif_role('admin', u.nama || ' (' || u.nomor || ') mengajukan pendaftaran skripsi.');
  return 'Pendaftaran skripsi diajukan';
end $$;

create or replace function app.a_skripsi_putus(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; ok boolean := (d ->> 'setuju')::boolean;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and status = 'menunggu' for update;
  if s.id is null then perform app.galat('Pendaftaran ini sudah diproses'); end if;
  update app.skripsi set status = case when ok then 'disetujui' else 'ditolak' end where id = s.id;
  perform app.notif(s.mhs_id, case when ok then 'Pendaftaran skripsi Anda disetujui Admin. Menunggu penetapan dosen.' else 'Pendaftaran skripsi Anda ditolak Admin. Silakan ajukan ulang.' end);
  return case when ok then 'Pendaftaran skripsi disetujui' else 'Pendaftaran skripsi ditolak' end;
end $$;

create or replace function app.judul_terkunci(s app.skripsi) returns boolean language sql stable as
$$ select s.arsip is not null or s.survey is not null or exists (select 1 from app.tim where skripsi_id = s.id and acc_status = 'disetujui') $$;

create or replace function app.a_judul_ubah(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; baru text := regexp_replace(coalesce(app.teks(d, 'judul'), ''), '\s+', ' ', 'g'); r record;
begin
  select * into s from app.skripsi where mhs_id = u.id and status = 'disetujui' for update;
  if s.id is null or app.judul_terkunci(s) then perform app.galat('Judul tidak bisa diubah lagi'); end if;
  if length(baru) < 10 then perform app.galat('Judul terlalu pendek'); end if;
  if baru = s.judul then return 'Judul tidak berubah'; end if;
  update app.skripsi set judul = left(baru, 300), judul_lama = judul_lama || jsonb_build_object('judul', s.judul, 'tgl', app.tgl_id(app.hari())) where id = s.id;
  for r in select dosen_id from app.tim where skripsi_id = s.id loop perform app.notif(r.dosen_id, u.nama || ' (' || u.nomor || ') mengubah judul skripsi menjadi: ' || baru); end loop;
  perform app.notif_role('admin', u.nama || ' (' || u.nomor || ') mengubah judul skripsi menjadi: ' || baru);
  return 'Judul skripsi diperbarui';
end $$;

-- ---- penentuan dosen
create or replace function app.a_tim_tetapkan(u app.pengguna, d jsonb) returns text language plpgsql as $$
<<f>> declare s app.skripsi; peran text[] := array['Pembimbing','Penguji 1','Penguji 2']; ids bigint[] := '{}'; t app.tim; i int; did bigint; m app.pengguna;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and status = 'disetujui' and arsip is null for update;
  if s.id is null then perform app.galat('Skripsi tidak ditemukan'); end if;
  select * into m from app.pengguna where id = s.mhs_id;
  for i in 1..3 loop
    select x.* into t from app.tim x where x.skripsi_id = s.id and x.peran = f.peran[i];
    if t.dosen_id is not null and t.status <> 'ditolak' then did := t.dosen_id;
    else
      did := nullif(d -> 'dosen' ->> (i - 1), '')::bigint;
      if did is null or not exists (select 1 from app.pengguna where id = did and role = 'dosen' and not nonaktif) then perform app.galat('Pilih dosen untuk ' || peran[i]); end if;
    end if;
    ids := ids || did;
  end loop;
  if ids[1] = ids[2] or ids[1] = ids[3] or ids[2] = ids[3] then perform app.galat('Satu dosen tidak boleh memegang dua peran untuk mahasiswa yang sama'); end if;
  for i in 1..3 loop
    select x.* into t from app.tim x where x.skripsi_id = s.id and x.peran = f.peran[i];
    if t.dosen_id is not null and t.status <> 'ditolak' then continue; end if;
    insert into app.tim (skripsi_id, peran, dosen_id, status) values (s.id, peran[i], ids[i], 'menunggu')
      on conflict on constraint tim_pkey do update set dosen_id = excluded.dosen_id, status = 'menunggu', acc_status = null, acc_cat = null, acc_tgl = null;
    perform app.notif(ids[i], 'Anda ditunjuk sebagai ' || peran[i] || ' untuk ' || m.nama || ' (' || m.nomor || ').');
  end loop;
  perform app.notif(m.id, 'Dosen pembimbing dan penguji Anda sudah ditetapkan. Menunggu konfirmasi dosen.');
  return 'Dosen ditetapkan, notifikasi terkirim';
end $$;

create or replace function app.a_tim_jawab(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare t app.tim; ok boolean := (d ->> 'terima')::boolean; m app.pengguna; pesan text;
begin
  select * into t from app.tim where skripsi_id = (d ->> 'id')::bigint and dosen_id = u.id and status = 'menunggu' for update;
  if t.skripsi_id is null then perform app.galat('Penugasan ini sudah dijawab'); end if;
  update app.tim set status = case when ok then 'diterima' else 'ditolak' end where skripsi_id = t.skripsi_id and peran = t.peran;
  select p.* into m from app.pengguna p join app.skripsi s on s.mhs_id = p.id where s.id = t.skripsi_id;
  pesan := u.nama || case when ok then ' menerima' else ' menolak' end || ' sebagai ' || t.peran;
  perform app.notif_role('admin', pesan || ' untuk ' || m.nama || '.');
  perform app.notif(m.id, pesan || ' Anda.');
  return case when ok then 'Anda menerima sebagai ' || t.peran else 'Penugasan ditolak' end;
end $$;

-- ---- pendaftaran seminar proposal / sidang akhir
-- Admin membatalkan penetapan dosen (misalnya ada yang berhalangan). Tanpa "peran": ketiganya dibatalkan
-- sekaligus, persetujuan naskah ikut dihapus, lalu Admin menetapkan ulang dan dosen menyetujui ulang.
create or replace function app.a_tim_batal(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; m app.pengguna; r record; vperan text := app.teks(d, 'peran'); n int := 0;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and status = 'disetujui' and arsip is null for update;
  if s.id is null then perform app.galat('Skripsi tidak ditemukan'); end if;
  if s.survey is not null then perform app.galat('Skripsi ini sudah selesai, dosennya tidak bisa diganti'); end if;
  select * into m from app.pengguna where id = s.mhs_id;
  for r in select x.peran as pr, x.dosen_id as did from app.tim x where x.skripsi_id = s.id and x.status = 'diterima' and (vperan is null or x.peran = vperan) loop
    update app.tim x set status = 'ditolak', acc_status = null, acc_cat = null, acc_tgl = null where x.skripsi_id = s.id and x.peran = r.pr;
    perform app.notif(r.did, 'Penugasan Anda sebagai ' || r.pr || ' untuk ' || m.nama || ' (' || m.nomor || ') dibatalkan Admin.');
    n := n + 1;
  end loop;
  if n = 0 then perform app.galat('Penugasan ini tidak bisa dibatalkan'); end if;
  if vperan is null then update app.tim x set acc_status = null, acc_cat = null, acc_tgl = null where x.skripsi_id = s.id; end if;
  perform app.notif(m.id, 'Penetapan dosen pembimbing dan penguji Anda dibatalkan Admin. Tunggu penetapan ulang.');
  return 'Penetapan dosen ' || m.nama || ' dibatalkan. Tetapkan ulang di Penentuan Baru.';
end $$;

create or replace function app.nama_jenis(j text) returns text language sql immutable as
$$ select case j when 'proposal' then 'seminar proposal' else 'sidang akhir' end $$;

create or replace function app.a_daftar_kirim(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare j text := d ->> 'jenis'; vlink text := app.teks(d, 'link'); s app.skripsi; p app.daftar; pid bigint; nm text; pb bigint;
begin
  if j not in ('proposal','sidang') then perform app.galat('Jenis pendaftaran tidak dikenal'); end if;
  nm := app.nama_jenis(j);
  pid := app.periode_aktif(j);
  if pid is null then perform app.galat('Pendaftaran ' || nm || ' sedang ditutup'); end if;
  if vlink is null or not app.link_sah(vlink) then perform app.galat('Link harus diawali http:// atau https://'); end if;
  select * into s from app.skripsi where mhs_id = u.id and status = 'disetujui' and arsip is null for update;
  if s.id is null or (select count(*) filter (where status = 'diterima') from app.tim where skripsi_id = s.id) < 3 then
    perform app.galat('Pendaftaran ' || nm || ' dibuka setelah pembimbing dan kedua penguji menerima penugasan'); end if;
  if j = 'sidang' and s.jalur = 'nonskripsi' then perform app.galat('Jalur non skripsi tidak memerlukan sidang akhir'); end if;
  if j = 'sidang' and app.tahap(s.id) < 2 then perform app.galat('Hasil seminar proposal Anda harus sudah dinyatakan lulus'); end if;
  select dosen_id into pb from app.tim where skripsi_id = s.id and peran = 'Pembimbing';
  select x.* into p from app.daftar x where x.jenis = j and x.skripsi_id = s.id for update;
  if p.id is null then
    insert into app.daftar (jenis, skripsi_id, mhs_id, periode_id, link, ket, tgl, status)
      values (j, s.id, u.id, pid, left(vlink, 500), left(coalesce(app.teks(d, 'ket'), ''), 500), app.hari(), 'menunggu_pembimbing');
  elsif p.status = 'dikembalikan_admin' then
    update app.daftar set link = left(vlink, 500), ket = left(coalesce(app.teks(d, 'ket'), ''), 500), tgl = app.hari(), periode_id = pid, status = 'menunggu_admin', cat_adm = '' where id = p.id;
    perform app.notif_role('admin', u.nama || ' (' || u.nomor || ') mengajukan ulang pendaftaran ' || nm || ' setelah melengkapi syarat.');
    return 'Pengajuan ulang ' || nm || ' dikirim ke Admin';
  elsif p.status in ('ditolak_pembimbing','mengulang') then
    update app.daftar set link = left(vlink, 500), ket = left(coalesce(app.teks(d, 'ket'), ''), 500), tgl = app.hari(), periode_id = pid, status = 'menunggu_pembimbing',
      cat_pb = '', cat_adm = '', h_nilai = null, h_angka = null, h_cat = null, h_link = null, h_tgl = null where id = p.id;
  else perform app.galat('Pendaftaran ' || nm || ' Anda sedang diproses'); end if;
  perform app.notif(pb, u.nama || ' (' || u.nomor || ') mendaftar ' || nm || ' dan menunggu persetujuan Anda.');
  return 'Pendaftaran ' || nm || ' dikirim ke pembimbing';
end $$;

create or replace function app.a_daftar_putus(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.daftar; ok boolean := (d ->> 'setuju')::boolean; cat text := coalesce(app.teks(d, 'cat'), ''); nm text; m app.pengguna; pb bigint;
begin
  select * into p from app.daftar where id = (d ->> 'id')::bigint for update;
  if p.id is null then perform app.galat('Pendaftaran tidak ditemukan'); end if;
  if not ok and cat = '' then perform app.galat('Isi catatan agar mahasiswa tahu apa yang perlu diperbaiki'); end if;
  nm := app.nama_jenis(p.jenis); cat := left(cat, 1500);
  select * into m from app.pengguna where id = p.mhs_id;
  select dosen_id into pb from app.tim where skripsi_id = p.skripsi_id and peran = 'Pembimbing';
  if u.role = 'dosen' then
    if pb is distinct from u.id or p.status <> 'menunggu_pembimbing' or not exists (select 1 from app.tim where skripsi_id = p.skripsi_id and peran = 'Pembimbing' and dosen_id = u.id and status = 'diterima') then perform app.galat('Pendaftaran ini tidak menunggu persetujuan Anda'); end if;
    update app.daftar set cat_pb = cat, cat_adm = '', status = case when ok then 'menunggu_admin' else 'ditolak_pembimbing' end where id = p.id;
    perform app.notif(m.id, case when ok then 'Pembimbing menyetujui pendaftaran ' || nm || ' Anda. Menunggu pemeriksaan syarat oleh Admin.' else 'Pembimbing menolak pendaftaran ' || nm || ' Anda: ' || cat end);
    if ok then perform app.notif_role('admin', 'Pendaftaran ' || nm || ' ' || m.nama || ' disetujui pembimbing. Periksa kelengkapan syaratnya.'); end if;
    return case when ok then 'Pendaftaran disetujui, diteruskan ke Admin' else 'Pendaftaran ditolak' end;
  elsif u.role = 'admin' then
    if p.status <> 'menunggu_admin' then perform app.galat('Pendaftaran ini belum bisa diproses Admin'); end if;
    update app.daftar set cat_adm = cat, status = case when ok then 'disetujui' else 'dikembalikan_admin' end where id = p.id;
    perform app.notif(m.id, case when ok then 'Pendaftaran ' || nm || ' Anda disetujui. Syarat dinyatakan lengkap.' else 'Syarat ' || nm || ' Anda belum lengkap: ' || cat end);
    perform app.notif(pb, 'Pendaftaran ' || nm || ' ' || m.nama || case when ok then ' disetujui Admin.' else ' dikembalikan Admin karena syarat belum lengkap.' end);
    return case when ok then 'Pendaftaran ' || nm || ' disetujui' else 'Pendaftaran dikembalikan ke mahasiswa' end;
  end if;
  perform app.galat('Anda tidak berhak memproses pendaftaran ini'); return null;
end $$;

create or replace function app.a_daftar_batal(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.daftar; nm text; m app.pengguna; pb bigint;
begin
  select * into p from app.daftar where id = (d ->> 'id')::bigint for update;
  if p.id is null then perform app.galat('Pendaftaran tidak ditemukan'); end if;
  nm := app.nama_jenis(p.jenis);
  select * into m from app.pengguna where id = p.mhs_id;
  select dosen_id into pb from app.tim where skripsi_id = p.skripsi_id and peran = 'Pembimbing';
  if u.role = 'dosen' and pb = u.id and p.status = 'menunggu_admin' and exists (select 1 from app.tim where skripsi_id = p.skripsi_id and peran = 'Pembimbing' and dosen_id = u.id and status = 'diterima') then
    update app.daftar set status = 'menunggu_pembimbing', cat_pb = '' where id = p.id;
    perform app.notif(m.id, 'Pembimbing membatalkan persetujuan pendaftaran ' || nm || ' Anda. Pendaftaran kembali menunggu persetujuan pembimbing.');
    perform app.notif_role('admin', 'Pembimbing membatalkan persetujuan ' || nm || ' ' || m.nama || '.');
  elsif u.role = 'admin' and p.status = 'disetujui' then
    if p.h_nilai is not null then perform app.galat('Persetujuan tidak bisa dibatalkan karena hasil pelaksanaannya sudah diisi'); end if;
    update app.daftar set status = 'menunggu_admin', cat_adm = '', j_tgl = null, j_jam = null, j_ruang = null, j_no = null where id = p.id;
    perform app.notif(m.id, 'Persetujuan pendaftaran ' || nm || ' Anda dibatalkan Admin. Pendaftaran kembali menunggu pemeriksaan syarat.');
    perform app.notif(pb, 'Persetujuan ' || nm || ' ' || m.nama || ' dibatalkan Admin.');
  else perform app.galat('Persetujuan ini sudah tidak bisa dibatalkan'); end if;
  return 'Persetujuan dibatalkan';
end $$;

-- ---- jadwal dan hasil (Admin)
create or replace function app.a_jadwal_simpan(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.daftar; o record; vtgl date; vjam text := app.teks(d, 'jam'); vruang text := app.teks(d, 'ruang'); nm text; m app.pengguna; baru boolean; bentrok text; vno int;
begin
  select * into p from app.daftar where id = (d ->> 'id')::bigint and status = 'disetujui' for update;
  if p.id is null then perform app.galat('Pendaftaran ini belum disetujui'); end if;
  if p.h_nilai is not null then perform app.galat('Jadwal tidak bisa diubah karena hasilnya sudah diisi'); end if;
  begin vtgl := (d ->> 'tgl')::date; exception when others then perform app.galat('Tanggal tidak sah'); end;
  if vtgl is null or vjam is null or vjam !~ '^\d{2}:\d{2}$' or vruang is null then perform app.galat('Tanggal, jam, dan tempat wajib diisi'); end if;
  if vtgl < app.hari() then perform app.galat('Tanggal yang dipilih sudah lewat'); end if;
  nm := app.nama_jenis(p.jenis);
  for o in select q.*, mm.nama as mhs_nama from app.daftar q join app.pengguna mm on mm.id = q.mhs_id where q.id <> p.id and q.j_tgl = vtgl and q.j_jam = vjam loop
    if lower(o.j_ruang) = lower(vruang) then perform app.galat(vruang || ' sudah dipakai ' || app.nama_jenis(o.jenis) || ' ' || o.mhs_nama || ' pada waktu itu'); end if;
    select dd.nama into bentrok from app.tim a join app.tim b on b.dosen_id = a.dosen_id join app.pengguna dd on dd.id = a.dosen_id
      where a.skripsi_id = p.skripsi_id and b.skripsi_id = o.skripsi_id limit 1;
    if bentrok is not null then perform app.galat(bentrok || ' sudah ada jadwal ' || app.nama_jenis(o.jenis) || ' ' || o.mhs_nama || ' pada waktu itu'); end if;
  end loop;
  baru := p.j_tgl is null;
  vno := coalesce(p.j_no, (select coalesce(max(x.j_no), 0) + 1 from app.daftar x where x.jenis = p.jenis));
  update app.daftar set j_tgl = vtgl, j_jam = vjam, j_ruang = left(vruang, 120), j_no = vno where id = p.id;
  select * into m from app.pengguna where id = p.mhs_id;
  perform app.notif_tim(p.skripsi_id, case when baru then 'Undangan ' else 'Perubahan jadwal ' end || nm || ' ' || m.nama || ': ' || app.hari_tgl(vtgl) || ', ' || replace(vjam, ':', '.') || ' WITA, ' || vruang || '.');
  return case when baru then 'Jadwal disimpan, undangan terkirim' else 'Jadwal diperbarui' end;
end $$;

create or replace function app.a_jadwal_hapus(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.daftar; m app.pengguna;
begin
  select * into p from app.daftar where id = (d ->> 'id')::bigint and j_tgl is not null for update;
  if p.id is null then perform app.galat('Jadwal tidak ditemukan'); end if;
  if p.h_nilai is not null then perform app.galat('Jadwal tidak bisa dihapus karena hasilnya sudah diisi'); end if;
  update app.daftar set j_tgl = null, j_jam = null, j_ruang = null where id = p.id;
  select * into m from app.pengguna where id = p.mhs_id;
  perform app.notif_tim(p.skripsi_id, 'Jadwal ' || app.nama_jenis(p.jenis) || ' ' || m.nama || ' dibatalkan. Tunggu jadwal baru.');
  return 'Jadwal dihapus';
end $$;

create or replace function app.a_hasil_simpan(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare p app.daftar; nilai text := d ->> 'nilai'; cat text := left(coalesce(app.teks(d, 'cat'), ''), 1500); vlink text := app.teks(d, 'link'); nm text; m app.pengguna; s app.skripsi; lanjut boolean; label text; akhir boolean; vangka numeric;
begin
  select * into p from app.daftar where id = (d ->> 'id')::bigint and status = 'disetujui' and j_tgl is not null for update;
  if p.id is null then perform app.galat('Jadwal belum ditetapkan'); end if;
  if p.j_tgl > app.hari() then perform app.galat('Hasil pelaksanaan bisa diisi mulai tanggal ' || app.tgl_panjang(p.j_tgl)); end if;
  if nilai is null or nilai not in ('lulus','revisi','ulang') then perform app.galat('Pilih hasil pelaksanaan terlebih dahulu'); end if;
  if vlink is not null and not app.link_sah(vlink) then perform app.galat('Link harus diawali http:// atau https://'); end if;
  if nilai = 'ulang' and cat = '' then perform app.galat('Isi catatan agar mahasiswa tahu alasan harus mengulang'); end if;
  select * into s from app.skripsi where id = p.skripsi_id;
  -- nilai akhir: sidang akhir (jalur skripsi) atau seminar proposal (jalur non skripsi)
  akhir := p.jenis = 'sidang' or s.jalur = 'nonskripsi';
  if akhir then
    vangka := nullif(replace(coalesce(app.teks(d, 'angka'), ''), ',', '.'), '')::numeric;
    if vangka is not null and (vangka < 0 or vangka > 100) then perform app.galat('Nilai angka harus antara 0 dan 100'); end if;
    if nilai in ('lulus','revisi') and vangka is null then perform app.galat('Isi nilai angka'); end if;
    if nilai in ('lulus','revisi') and vangka < 55 then perform app.galat('Nilai di bawah 55 berarti Tidak Lulus. Pilih hasil Mengulang.'); end if;
    vangka := round(vangka, 2);
  end if;
  lanjut := case when p.jenis = 'proposal' and s.jalur <> 'nonskripsi' then exists (select 1 from app.daftar where skripsi_id = p.skripsi_id and jenis = 'sidang') else s.naskah_link is not null end;
  if p.h_nilai is not null and lanjut then perform app.galat('Hasil tidak bisa diubah karena mahasiswa sudah melanjutkan ke tahap berikutnya'); end if;
  nm := app.nama_jenis(p.jenis);
  label := case nilai when 'lulus' then 'Lulus' when 'revisi' then 'Lulus dengan revisi' else 'Mengulang' end;
  update app.daftar set h_nilai = nilai, h_angka = vangka, h_cat = cat, h_link = left(vlink, 500), h_tgl = app.hari() where id = p.id;
  select * into m from app.pengguna where id = p.mhs_id;
  perform app.notif_tim(p.skripsi_id, 'Hasil ' || nm || ' ' || m.nama || ': ' || label || case when vangka is not null then ', nilai ' || vangka || ' (' || app.huruf(vangka) || ')' else '' end || '.' || case when cat <> '' then ' Catatan: ' || cat else '' end);
  if nilai = 'ulang' then
    update app.daftar set status = 'mengulang', j_tgl = null, j_jam = null, j_ruang = null where id = p.id;
    perform app.notif(m.id, 'Anda harus mendaftar ' || nm || ' kembali.');
  end if;
  return 'Hasil ' || nm || ' disimpan';
end $$;

-- ---- persetujuan naskah akhir
create or replace function app.a_naskah_kirim(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; link text := app.teks(d, 'link'); r record;
begin
  if link is null or not app.link_sah(link) then perform app.galat('Link harus diawali http:// atau https://'); end if;
  select * into s from app.skripsi where mhs_id = u.id and status = 'disetujui' and arsip is null for update;
  if s.id is null or app.tahap(s.id) <> 4 then perform app.galat('Naskah belum bisa dikirim pada tahap ini'); end if;
  if (select count(*) filter (where status = 'diterima') from app.tim where skripsi_id = s.id) < 3 then perform app.galat('Dosen pembimbing atau penguji Anda sedang diganti. Tunggu sampai ketiganya menerima penugasan.'); end if;
  update app.skripsi set naskah_link = left(link, 500), naskah_tgl = app.hari() where id = s.id;
  for r in update app.tim set acc_status = 'menunggu', acc_cat = null, acc_tgl = null
           where skripsi_id = s.id and acc_status is distinct from 'disetujui' returning dosen_id loop
    perform app.notif(r.dosen_id, u.nama || ' (' || u.nomor || ') mengirim naskah skripsi hasil revisi untuk Anda periksa.');
  end loop;
  return 'Naskah dikirim ke dosen';
end $$;

create or replace function app.a_acc(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; t app.tim; a text := d ->> 'aksi'; cat text := left(coalesce(app.teks(d, 'cat'), ''), 1500); m app.pengguna;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and arsip is null for update;
  select * into t from app.tim where skripsi_id = s.id and dosen_id = u.id and status = 'diterima';
  if s.id is null or t.skripsi_id is null or app.tahap(s.id) < 4 then perform app.galat('Anda tidak berhak memproses naskah ini'); end if;
  select * into m from app.pengguna where id = s.mhs_id;
  if a = 'batal' then
    if s.survey is not null then perform app.galat('Survey sudah diisi, persetujuan tidak bisa dibatalkan'); end if;
    if t.acc_status is distinct from 'disetujui' then perform app.galat('Belum ada persetujuan untuk dibatalkan'); end if;
    update app.tim set acc_status = 'menunggu', acc_cat = null, acc_tgl = null where skripsi_id = s.id and peran = t.peran;
    perform app.notif(m.id, u.nama || ' (' || t.peran || ') membatalkan persetujuan naskah Anda.');
    return 'Persetujuan dibatalkan';
  end if;
  if s.naskah_link is null or t.acc_status is distinct from 'menunggu' then perform app.galat('Naskah ini tidak menunggu pemeriksaan Anda'); end if;
  if a = 'setuju' then
    update app.tim set acc_status = 'disetujui', acc_cat = cat, acc_tgl = app.hari() where skripsi_id = s.id and peran = t.peran;
    perform app.notif(m.id, u.nama || ' (' || t.peran || ') menyetujui naskah skripsi Anda.');
    if app.acc_lengkap(s.id) then
      perform app.notif(m.id, 'Naskah Anda sudah disetujui pembimbing dan kedua penguji. Silakan isi Survey Kepuasan.');
      perform app.notif_role('admin', 'Naskah skripsi ' || m.nama || ' sudah disetujui semua dosen.');
    end if;
    return 'Naskah disetujui';
  elsif a = 'revisi' then
    if cat = '' then perform app.galat('Isi catatan agar mahasiswa tahu bagian yang perlu direvisi'); end if;
    update app.tim set acc_status = 'revisi', acc_cat = cat, acc_tgl = app.hari() where skripsi_id = s.id and peran = t.peran;
    perform app.notif(m.id, u.nama || ' (' || t.peran || ') meminta revisi naskah: ' || cat);
    return 'Permintaan revisi dikirim ke mahasiswa';
  end if;
  perform app.galat('Aksi tidak dikenal'); return null;
end $$;

-- ---- survey
create or replace function app.a_survey_kirim(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; k text; n int; v jsonb; e text;
begin
  select * into s from app.skripsi where mhs_id = u.id and status = 'disetujui' and arsip is null for update;
  if s.id is null or app.tahap(s.id) <> 5 then perform app.galat('Survey belum bisa diisi pada tahap ini'); end if;
  foreach k in array array['dosen','prodi'] loop
    n := case k when 'dosen' then 13 else 8 end;
    if jsonb_typeof(d -> k) <> 'array' or jsonb_array_length(d -> k) <> n then perform app.galat('Jawaban survey belum lengkap'); end if;
    for v in select * from jsonb_array_elements(d -> k) loop
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not in (1, 2, 3, 4) then perform app.galat('Jawaban survey belum lengkap'); end if;
    end loop;
  end loop;
  foreach e in array array['dosenBaik','dosenHarap','prodiBaik','prodiHarap'] loop
    if app.teks(d, e) is null then perform app.galat('Masih ada pertanyaan isian yang kosong'); end if;
  end loop;
  update app.skripsi set survey = jsonb_build_object('dosen', d -> 'dosen', 'prodi', d -> 'prodi', 'dosenBaik', left(app.teks(d, 'dosenBaik'), 2000),
    'dosenHarap', left(app.teks(d, 'dosenHarap'), 2000), 'prodiBaik', left(app.teks(d, 'prodiBaik'), 2000), 'prodiHarap', left(app.teks(d, 'prodiHarap'), 2000)),
    survey_tgl = app.hari() where id = s.id;
  perform app.notif_role('admin', u.nama || ' (' || u.nomor || ') telah mengisi survey. Skripsinya berstatus Selesai dan bisa diarsipkan.');
  perform app.notif(u.id, 'Skripsi Anda dinyatakan selesai. Halaman Pengesahan bisa diunduh di menu Survey Kepuasan.');
  return 'Survey terkirim. Skripsi Anda dinyatakan selesai.';
end $$;

create or replace function app.a_survey_batal(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; m app.pengguna;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and survey is not null for update;
  if s.id is null then perform app.galat('Survey tidak ditemukan'); end if;
  if s.arsip is not null then perform app.galat('Skripsi ini sudah diarsipkan. Kembalikan dari arsip terlebih dahulu.'); end if;
  update app.skripsi set survey = null, survey_tgl = null where id = s.id;
  select * into m from app.pengguna where id = s.mhs_id;
  perform app.notif(m.id, 'Survey kepuasan Anda dibatalkan Admin. Status skripsi kembali ke tahap Survey Kepuasan. Silakan isi ulang setelah perubahan selesai.');
  perform app.notif_tim(s.id, 'Survey ' || m.nama || ' dibatalkan Admin. Status skripsinya kembali ke tahap Survey Kepuasan.', false);
  return 'Survey ' || m.nama || ' dibatalkan';
end $$;

-- ---- arsip
create or replace function app.arsipkan(p_id bigint) returns void language plpgsql as $$
declare mid bigint;
begin
  update app.skripsi set arsip = app.hari() where id = p_id returning mhs_id into mid;
  update app.pengguna set nonaktif = true, nonaktif_arsip = true where id = mid;
  delete from app.sesi where pengguna_id = mid;
  delete from app.notif where ke = mid;
end $$;

create or replace function app.a_arsip(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi; r record; n int := 0;
begin
  if (d ->> 'semua')::boolean is true then
    for r in select id from app.skripsi where status = 'disetujui' and arsip is null and app.tahap(id) = 6 loop perform app.arsipkan(r.id); n := n + 1; end loop;
    return n || ' skripsi diarsipkan';
  end if;
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and arsip is null for update;
  if s.id is null or app.tahap(s.id) <> 6 then perform app.galat('Hanya skripsi berstatus Selesai yang bisa diarsipkan'); end if;
  perform app.arsipkan(s.id);
  return 'Skripsi ' || (select nama from app.pengguna where id = s.mhs_id) || ' diarsipkan';
end $$;

create or replace function app.a_arsip_buka(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare s app.skripsi;
begin
  select * into s from app.skripsi where id = (d ->> 'id')::bigint and arsip is not null for update;
  if s.id is null then perform app.galat('Arsip tidak ditemukan'); end if;
  update app.skripsi set arsip = null where id = s.id;
  update app.pengguna set nonaktif = false, nonaktif_arsip = false where id = s.mhs_id and nonaktif_arsip;
  return 'Skripsi ' || (select nama from app.pengguna where id = s.mhs_id) || ' dikembalikan ke daftar aktif';
end $$;

-- ---- dokumen dan penanda tangan
create or replace function app.a_dokumen_simpan(u app.pengguna, d jsonb) returns text language plpgsql as $$
<<f>> declare idd bigint := nullif(d ->> 'id', '')::bigint; nama text := app.teks(d, 'nama'); link text := app.teks(d, 'link'); ket text := left(coalesce(app.teks(d, 'ket'), ''), 500);
begin
  if nama is null then perform app.galat('Nama dokumen tidak boleh kosong'); end if;
  if link is null or not app.link_sah(link) then perform app.galat('Link harus diawali http:// atau https://'); end if;
  if exists (select 1 from app.dokumen x where x.id is distinct from idd and lower(x.nama) = lower(f.nama)) then perform app.galat('Dokumen dengan nama itu sudah ada'); end if;
  if idd is not null then
    update app.dokumen set nama = left(f.nama, 150), link = left(f.link, 500), ket = f.ket, tgl = app.hari() where id = idd;
    return 'Dokumen diperbarui';
  end if;
  insert into app.dokumen (nama, link, ket, tgl) values (left(nama, 150), left(link, 500), ket, app.hari());
  perform app.notif_role('dosen', 'Dokumen baru tersedia di menu Dokumen: ' || nama || '.');
  perform app.notif_role('mahasiswa', 'Dokumen baru tersedia di menu Dokumen: ' || nama || '.');
  return 'Dokumen ditambahkan';
end $$;

create or replace function app.a_dokumen_hapus(u app.pengguna, d jsonb) returns text language plpgsql as $$
declare nm text;
begin
  delete from app.dokumen where id = (d ->> 'id')::bigint returning nama into nm;
  return 'Dokumen ' || coalesce(nm, '') || ' dihapus';
end $$;

create or replace function app.a_pejabat(u app.pengguna, d jsonb) returns text language plpgsql as $$
begin
  update app.pengaturan set nilai = jsonb_build_object('dekan', left(coalesce(app.teks(d, 'dekan'), ''), 120), 'dekanNidn', left(coalesce(app.teks(d, 'dekanNidn'), ''), 30),
    'kp', left(coalesce(app.teks(d, 'kp'), ''), 120), 'kpNidn', left(coalesce(app.teks(d, 'kpNidn'), ''), 30)) where kunci = 'pejabat';
  return 'Penanda tangan dokumen disimpan';
end $$;

-- ============================================================ PINTU MASUK
-- Dipanggil dari tampilan: POST /rest/v1/rpc/api  { "token": ..., "aksi": ..., "data": {...} }
create or replace function public.api(token text default null, aksi text default null, data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare u app.pengguna; d jsonb := coalesce(data, '{}'::jsonb); pesan text; un text; tok text; peran text;
  admin_saja text[] := array['akun_setujui','akun_tolak','akun_tambah','akun_reset','akun_toggle','akun_hapus','periode_tambah','periode_tanggal','periode_aksi','periode_akses',
    'skripsi_putus','tim_tetapkan','tim_batal','jadwal_simpan','jadwal_hapus','hasil_simpan','survey_batal','arsip','arsip_buka','dokumen_simpan','dokumen_hapus','pejabat'];
  dosen_saja text[] := array['tim_jawab','acc'];
  mhs_saja text[] := array['skripsi_daftar','judul_ubah','daftar_kirim','naskah_kirim','survey_kirim'];
begin
  -- ---------- tanpa sesi
  if aksi = 'ping' then perform 1 from app.pengaturan limit 1; return jsonb_build_object('ok', true); end if;
  if aksi = 'status' then return jsonb_build_object('ok', true, 'adaAdmin', exists (select 1 from app.pengguna where role = 'admin')); end if;

  if aksi = 'setup' then
    perform pg_advisory_xact_lock(4711);
    if exists (select 1 from app.pengguna where role = 'admin') then perform app.galat('Admin sudah ada. Silakan masuk.'); end if;
    if app.teks(d, 'nama') is null then perform app.galat('Nama tidak boleh kosong'); end if;
    perform app.cek_akun_baru(app.teks(d, 'username'), d ->> 'sandi', null);
    insert into app.pengguna (role, nama, username, sandi) values ('admin', left(app.teks(d, 'nama'), 120), app.teks(d, 'username'), app.hash_sandi(d ->> 'sandi')) returning * into u;
    return jsonb_build_object('ok', true, 'pesan', 'Akun Admin dibuat', 'token', app.buat_sesi(u.id), 'state', app.muat(u));
  end if;

  if aksi = 'masuk' then
    un := lower(coalesce(app.teks(d, 'username'), ''));
    delete from app.login_gagal where waktu < now() - interval '1 day';
    if (select count(*) from app.login_gagal g where g.username = un and g.waktu > now() - interval '10 minutes') >= 8 then
      return jsonb_build_object('ok', false, 'pesan', 'Terlalu banyak percobaan masuk. Coba lagi 10 menit lagi.');
    end if;
    select * into u from app.pengguna p where lower(p.username) = un;
    if u.id is null or u.role <> coalesce(d ->> 'role', '') or u.sandi <> extensions.crypt(coalesce(d ->> 'sandi', ''), u.sandi) then
      insert into app.login_gagal (username) values (un);
      return jsonb_build_object('ok', false, 'pesan', 'Username, password, atau peran tidak cocok');
    end if;
    if u.nonaktif then return jsonb_build_object('ok', false, 'pesan', 'Akun ini dinonaktifkan. Hubungi Admin.'); end if;
    delete from app.login_gagal g where g.username = un;
    return jsonb_build_object('ok', true, 'token', app.buat_sesi(u.id), 'state', app.muat(u));
  end if;

  if aksi = 'daftar_akun' then
    if app.teks(d, 'nama') is null or coalesce(app.teks(d, 'nim'), '') !~ '^\d{8,12}$' or app.teks(d, 'email') is null or app.teks(d, 'hp') is null then
      perform app.galat('Lengkapi data pendaftaran. NIM berupa 8–12 digit angka.'); end if;
    if exists (select 1 from app.pengguna where nomor = app.teks(d, 'nim')) then perform app.galat('NIM ini sudah punya akun. Hubungi Admin jika lupa password.'); end if;
    if exists (select 1 from app.akun_req where nim = app.teks(d, 'nim') and status = 'menunggu') then perform app.galat('Pendaftaran untuk NIM ini sedang menunggu persetujuan Admin'); end if;
    if (select count(*) from app.akun_req where status = 'menunggu') >= 300 then perform app.galat('Antrean pendaftaran penuh. Hubungi Admin.'); end if;
    insert into app.akun_req (nama, nim, angkatan, email, hp, tgl) values (left(app.teks(d, 'nama'), 120), app.teks(d, 'nim'), left(app.teks(d, 'angkatan'), 10), left(app.teks(d, 'email'), 120), left(app.teks(d, 'hp'), 30), app.hari());
    perform app.notif_role('admin', 'Pendaftaran akun baru dari ' || app.teks(d, 'nama') || ' (' || app.teks(d, 'nim') || ') menunggu persetujuan.');
    return jsonb_build_object('ok', true, 'pesan', 'Pendaftaran terkirim. Tunggu persetujuan Admin.');
  end if;

  -- ---------- dengan sesi
  u := app.siapa(token);
  if aksi = 'keluar' then
    delete from app.sesi where token_hash = encode(sha256(convert_to(token, 'UTF8')), 'hex');
    return jsonb_build_object('ok', true);
  end if;
  if aksi = 'muat' then return jsonb_build_object('ok', true, 'state', app.muat(u)); end if;
  if aksi = 'foto_ambil' then
    return jsonb_build_object('ok', true, 'foto', (select coalesce(jsonb_object_agg(p.id::text, p.foto), '{}'::jsonb) from app.pengguna p
      where p.foto is not null and p.id in (select (x ->> 0)::bigint from jsonb_array_elements(coalesce(d -> 'ids', '[]'::jsonb)) x limit 60)
        and (u.role in ('admin','dosen') or p.id = u.id or p.role = 'dosen')));
  end if;

  if (aksi = any(admin_saja) and u.role <> 'admin') or (aksi = any(dosen_saja) and u.role <> 'dosen') or (aksi = any(mhs_saja) and u.role <> 'mahasiswa')
     or (aksi in ('daftar_putus','daftar_batal') and u.role not in ('admin','dosen')) then
    perform app.galat('Anda tidak berhak melakukan tindakan ini');
  end if;
  if app.identitas_kurang(u) and aksi not in ('profil','foto','sandi','notif_baca') then perform app.galat('Lengkapi Identitas Diri terlebih dahulu'); end if;

  pesan := case aksi
    when 'profil' then app.a_profil(u, d)             when 'foto' then app.a_foto(u, d)
    when 'sandi' then app.a_sandi(u, d)               when 'notif_baca' then app.a_notif_baca(u, d)
    when 'akun_setujui' then app.a_akun_setujui(u, d) when 'akun_tolak' then app.a_akun_tolak(u, d)
    when 'akun_tambah' then app.a_akun_tambah(u, d)   when 'akun_reset' then app.a_akun_reset(u, d)
    when 'akun_toggle' then app.a_akun_toggle(u, d)   when 'akun_hapus' then app.a_akun_hapus(u, d)
    when 'periode_tambah' then app.a_periode_tambah(u, d)   when 'periode_tanggal' then app.a_periode_tanggal(u, d)
    when 'periode_aksi' then app.a_periode_aksi(u, d)       when 'periode_akses' then app.a_periode_akses(u, d)
    when 'skripsi_daftar' then app.a_skripsi_daftar(u, d)   when 'skripsi_putus' then app.a_skripsi_putus(u, d)
    when 'judul_ubah' then app.a_judul_ubah(u, d)
    when 'tim_batal' then app.a_tim_batal(u, d)
    when 'tim_tetapkan' then app.a_tim_tetapkan(u, d)       when 'tim_jawab' then app.a_tim_jawab(u, d)
    when 'daftar_kirim' then app.a_daftar_kirim(u, d)       when 'daftar_putus' then app.a_daftar_putus(u, d)
    when 'daftar_batal' then app.a_daftar_batal(u, d)
    when 'jadwal_simpan' then app.a_jadwal_simpan(u, d)     when 'jadwal_hapus' then app.a_jadwal_hapus(u, d)
    when 'hasil_simpan' then app.a_hasil_simpan(u, d)
    when 'naskah_kirim' then app.a_naskah_kirim(u, d)       when 'acc' then app.a_acc(u, d)
    when 'survey_kirim' then app.a_survey_kirim(u, d)       when 'survey_batal' then app.a_survey_batal(u, d)
    when 'arsip' then app.a_arsip(u, d)                     when 'arsip_buka' then app.a_arsip_buka(u, d)
    when 'dokumen_simpan' then app.a_dokumen_simpan(u, d)   when 'dokumen_hapus' then app.a_dokumen_hapus(u, d)
    when 'pejabat' then app.a_pejabat(u, d)
    else '?' end;
  if pesan = '?' then perform app.galat('Aksi tidak dikenal'); end if;
  select * into u from app.pengguna where id = u.id;
  return jsonb_build_object('ok', true, 'pesan', pesan, 'state', app.muat(u));
exception
  when sqlstate 'P0001' then return jsonb_build_object('ok', false, 'pesan', sqlerrm);
  when sqlstate 'P0002' then return jsonb_build_object('ok', false, 'sesi', false, 'pesan', sqlerrm);
  when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok', false, 'pesan', 'Data yang dikirim tidak sah');
end $$;

revoke all on function public.api(text, text, jsonb) from public;
grant execute on function public.api(text, text, jsonb) to anon, authenticated;

-- agar Supabase langsung mengenali fungsi yang baru dibuat
notify pgrst, 'reload schema';
