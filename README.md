# Share 1 Keyboard & Mouse antara 2 Laptop Ubuntu (GNOME/Wayland)

Setup otomatis untuk berbagi satu keyboard & mouse antara 2 laptop Ubuntu lewat jaringan LAN/WiFi, menggunakan [lan-mouse](https://github.com/feschber/lan-mouse) — bukan Barrier/Synergy/Input Leap, karena tools tersebut berbasis X11 dan sering gagal total di GNOME Wayland (default Ubuntu modern).

Setelah setup, begitu kedua laptop **nyala + login ke desktop + satu jaringan yang sama**, kedua daemon otomatis saling connect via systemd service — tidak perlu jalankan perintah apa pun lagi setiap hari.

> **Catatan penting**: `lan-mouse-setup.sh` install lan-mouse langsung dari branch `main` GitHub, **bukan** dari crates.io. Versi 0.11.0 yang dipublish di crates.io masih pakai resolver DNS murni Rust (`hickory-resolver`) yang tidak lewat avahi/mDNS sama sekali — hostname `.local` tidak akan pernah bisa di-resolve dengan versi itu (bakal loop "could not resolve" terus di log). Fix-nya (pakai resolver OS asli via `getaddrinfo`, yang baru lewat `nsswitch.conf`/avahi) baru ada di `main`, belum dirilis versi barunya.
>
> **Kedua laptop wajib pakai build dari commit `main` yang SAMA** (idealnya di-install dalam rentang waktu berdekatan). `main` itu branch development, bukan rilis stabil — protokol jaringannya bisa berubah antar-commit. Kalau satu laptop pakai crates.io/commit lama dan satunya commit baru, koneksi akan "connected" sebentar lalu langsung putus dengan error semacam `invalid event id: No discriminant in enum EventType matches the value N` di log — itu tandanya versi protokol beda, bukan masalah izin/firewall. Fix: install ulang KEDUA laptop dengan perintah git yang sama di waktu yang berdekatan.

## Kenapa lan-mouse?

- Native Wayland: pakai backend `libei` / `xdg-desktop-portal` yang didukung GNOME ≥ 45 dan KDE Plasma ≥ 6.1.
- Auto-reconnect: hostname di-resolve via mDNS (`.local`), jadi tetap nyambung walau IP DHCP berubah-ubah.
- Enkripsi peer-to-peer (DTLS) dengan pairing sertifikat sekali saja — bukan cuma "asal nyambung ke device manapun di jaringan".
- Di setup ini, kedua laptop **saling menemukan otomatis lewat mDNS** — tidak perlu tahu/ketik hostname, IP, atau username laptop satunya sama sekali.

## Requirement

- Ubuntu dengan GNOME ≥ 45 (Ubuntu 24.04+). Kalau masih Ubuntu 22.04 / GNOME 42, backend Wayland-nya tidak didukung — pilih "Ubuntu on Xorg" di layar login lalu pakai Barrier/Input Leap sebagai gantinya.
- Kedua laptop satu jaringan LAN/WiFi yang sama.

## Instalasi

Jalankan script ini di **kedua laptop** (copy/scp dulu ke laptop satunya). Argumennya cuma **posisi laptop itu sendiri** (bukan posisi laptop lawan, dan bukan hostname siapa pun):

```bash
# di laptop yang posisinya di kiri:
./lan-mouse-setup.sh left

# di laptop yang posisinya di kanan:
./lan-mouse-setup.sh right
```

Script otomatis melakukan:
1. Install dependency build + `avahi-daemon` + `avahi-utils` (mDNS & auto-discovery).
2. Install Rust toolchain (kalau belum ada) + build `lan-mouse` dari source.
3. Tulis config awal di `~/.config/lan-mouse/config.toml`.
4. Pasang systemd **user service** (`~/.config/systemd/user/lan-mouse.service`) yang auto-start begitu login ke desktop.
5. Pasang **watchdog auto-retry DNS** (`~/.local/bin/lan-mouse-watchdog.sh` + timer systemd tiap 30 detik) — lihat penjelasan bug di bawah.
6. Buka firewall UDP `4242` kalau `ufw` aktif.
7. **Broadcast identitas laptop ini** (posisi + fingerprint sertifikat) ke jaringan lokal lewat mDNS, supaya laptop lain bisa menemukannya otomatis.

## Pairing (sekali saja, sepenuhnya otomatis)

Setelah `lan-mouse-setup.sh` dijalankan di **kedua** laptop (dengan posisi yang saling berkebalikan, misal `left` & `right`), jalankan di salah satu atau kedua laptop:

```bash
./discover-and-pair.sh
```

Script ini otomatis:
1. Mencari laptop lain di jaringan lokal lewat mDNS (`avahi-browse`) — tanpa perlu tahu hostname/IP/username sama sekali.
2. Membaca posisi & fingerprint yang di-broadcast laptop tersebut.
3. Meng-authorize fingerprint-nya dan menambahkan sebagai client dengan posisi yang benar.
4. Menyimpan konfigurasi secara permanen.

Fingerprint tetap ada di balik layar (itu gerbang keamanan lan-mouse, supaya bukan sembarang device di WiFi yang sama bisa kontrol keyboard/mouse kamu — tidak ada cara bypass), tapi kamu tidak perlu melihat, mengetik, atau menyalin apa pun secara manual.

## Kasus: laptop-kiri pakai monitor eksternal (HDMI out)

Kalau susunan fisik di meja adalah:

```
[layar bawaan laptop-kiri] -- [monitor eksternal (HDMI out dari laptop-kiri)] -- [laptop-kanan]
```

`lan-mouse` **tidak tahu soal monitor individual** — dia cuma peduli pada tepi kanan dari keseluruhan ruang layar milik satu mesin (laptop-kiri), sesuai susunan yang diatur di GNOME. Jadi tidak ada perubahan di config `lan-mouse` sama sekali. Yang perlu diatur adalah **susunan monitor di laptop-kiri**:

1. Buka **Settings → Displays** di laptop-kiri.
2. Drag kotak-kotak layar supaya urutannya cocok dengan meja beneran:
   - Kalau laptop-kiri dipakai clamshell (layar bawaan ditutup, cuma monitor eksternal aktif) → otomatis beres, monitor itu satu-satunya layar sehingga otomatis jadi "tepi kanan".
   - Kalau layar bawaan laptop-kiri masih aktif juga (extended desktop) → susun: **layar bawaan di kiri, monitor eksternal (HDMI out) di kanan**, sesuai posisi fisik meja.
3. Klik **Apply**.

Dengan susunan ini, titik keluar mouse yang memicu lompat ke laptop-kanan adalah **tepi kanan monitor eksternal** (yang secara fisik bersebelahan dengan laptop-kanan) — bukan tepi layar bawaan laptop-kiri.

Config `lan-mouse` yang dihasilkan `discover-and-pair.sh` tetap sama persis seperti setup normal (`position = "right"` di laptop-kiri, `position = "left"` di laptop-kanan) — tidak ada perubahan apa pun di sisi lan-mouse untuk kasus ini.

**Tes**: taruh kursor di monitor eksternal, geser ke kanan sampai mentok tepi kanan monitor itu → kursor harus lompat ke laptop-kanan. Kalau malah nyangkut balik ke layar bawaan laptop-kiri dulu, berarti urutan di Settings → Displays belum sesuai — drag ulang.

## Troubleshooting

```bash
# cek log service
journalctl --user -u lan-mouse -f

# cek laptop lain kelihatan di mDNS
avahi-browse -r -t _lanmouse._udp

# lihat status client yang terkonfigurasi
lan-mouse cli list
```

Kalau `discover-and-pair.sh` bilang "tidak ada laptop lain ditemukan":
- Pastikan `lan-mouse-setup.sh` sudah selesai dijalankan (sampai baris "Broadcast identitas...") di laptop satunya.
- Beberapa WiFi publik/kantor memblokir multicast (mDNS) antar-device — coba di jaringan rumah/hotspot pribadi.
- `sudo systemctl status avahi-daemon` di kedua laptop, pastikan `active (running)`.

Kalau di `journalctl --user -u lan-mouse -f` muncul **`could not resolve <hostname>`** terus-menerus (loop tanpa henti), cek dua hal:

1. **Versi lan-mouse yang ke-install harus dari source `main`, bukan crates.io.** Cek dengan:
   ```bash
   lan-mouse --version
   ```
   Kalau outputnya cuma `lan-mouse 0.11.0` tanpa info commit/branch di baris `commit_hash:`, berarti ke-install dari crates.io (buggy, tidak akan pernah resolve `.local`). Install ulang dengan:
   ```bash
   cargo install --locked --force --git https://github.com/feschber/lan-mouse lan-mouse
   systemctl --user restart lan-mouse.service
   ```

2. Field `hostname` di `~/.config/lan-mouse/config.toml` bagian `[[clients]]` **wajib** diakhiri `.local` (misal `laptop-kiri.local`, bukan cuma `laptop-kiri`). Kalau salah, perbaiki dengan:
   ```bash
   lan-mouse cli set-host <id-dari-'lan-mouse cli list'> <hostname-lawan>.local
   lan-mouse cli save-config
   ```

Kalau muncul **`emulation is disabled on the target device`** atau connection langsung putus setelah "connected" dengan error **`invalid event id`** di log laptop lawan: itu **bukan** soal izin GNOME — itu tanda kedua laptop pakai build lan-mouse yang **beda versi/commit** (satu dari crates.io, satu dari git `main`, atau commit `main` yang beda). Samakan dengan install ulang keduanya pakai perintah `cargo install --git ...` yang sama, lalu `systemctl --user restart lan-mouse.service` di kedua laptop. Cek dengan `lan-mouse --version` — baris `commit_hash:` di kedua laptop harus identik.

Kalau mouse/keyboard **berhenti pindah sama sekali** dan `journalctl --user -u lan-mouse -f` spam `connecting ... (ips: [])` tanpa henti, tapi `lan-mouse cli list` juga nunjukkan `ips: {}` kosong terus: ini bug di lan-mouse sendiri — **hostname cuma di-resolve sekali saat client di-`activate`, tidak ada retry DNS otomatis sama sekali**. Kalau pas service ini start laptop lawan belum kelihatan di mDNS (baru nyala / belum login), resolve gagal sekali dan `ips` nyangkut kosong selamanya. Fix manual sekali pakai:
```bash
lan-mouse cli deactivate <id>
lan-mouse cli activate <id>
```
`lan-mouse-setup.sh` sudah otomatis memasang **watchdog** (`~/.local/bin/lan-mouse-watchdog.sh` + systemd timer tiap 30 detik) yang melakukan fix ini otomatis begitu ada client aktif dengan `ips` kosong, jadi harusnya tidak perlu campur tangan manual lagi — tunggu maksimal ~30 detik setelah laptop lawan nyala/kelihatan di jaringan.

## Opsional: auto-login (zero-touch setelah nyala)

Service `lan-mouse` baru jalan setelah ada sesi GNOME yang login (butuh akses compositor). Kalau mau benar-benar hands-off dari saat laptop dinyalakan (tanpa perlu ketik password login), aktifkan auto-login lewat **Settings → Users**. Trade-off: siapa pun yang menyalakan laptop bisa langsung akses tanpa password.
