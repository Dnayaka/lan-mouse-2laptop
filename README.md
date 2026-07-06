# Share 1 Keyboard & Mouse antara 2 Laptop Ubuntu (GNOME/Wayland)

Setup otomatis untuk berbagi satu keyboard & mouse antara 2 laptop Ubuntu lewat jaringan LAN/WiFi, menggunakan [lan-mouse](https://github.com/feschber/lan-mouse) — bukan Barrier/Synergy/Input Leap, karena tools tersebut berbasis X11 dan sering gagal total di GNOME Wayland (default Ubuntu modern).

Setelah setup, begitu kedua laptop **nyala + login ke desktop + satu jaringan yang sama**, kedua daemon otomatis saling connect via systemd service — tidak perlu jalankan perintah apa pun lagi setiap hari.

## Kenapa lan-mouse?

- Native Wayland: pakai backend `libei` / `xdg-desktop-portal` yang didukung GNOME ≥ 45 dan KDE Plasma ≥ 6.1.
- Auto-reconnect: hostname di-resolve via mDNS (`.local`), jadi tetap nyambung walau IP DHCP berubah-ubah.
- Enkripsi peer-to-peer (DTLS) dengan pairing sertifikat sekali saja — bukan cuma "asal nyambung ke device manapun di jaringan".

## Requirement

- Ubuntu dengan GNOME ≥ 45 (Ubuntu 24.04+). Kalau masih Ubuntu 22.04 / GNOME 42, backend Wayland-nya tidak didukung — pilih "Ubuntu on Xorg" di layar login lalu pakai Barrier/Input Leap sebagai gantinya.
- Kedua laptop satu jaringan LAN/WiFi yang sama.

## Instalasi

Jalankan script ini di **kedua laptop** (copy/scp dulu ke laptop satunya), dengan argumen saling berkebalikan:

```bash
# di laptop-kiri (posisi laptop-kanan ada di sebelah KANAN laptop-kiri):
./lan-mouse-setup.sh laptop-kanan right

# di laptop-kanan (mirror, kebalikannya):
./lan-mouse-setup.sh laptop-kiri left
```

Script otomatis melakukan:
1. Install dependency build + `avahi-daemon` (mDNS) + `openssh-server` (dipakai buat auto-pairing di langkah selanjutnya).
2. Install Rust toolchain (kalau belum ada) + build `lan-mouse` dari source.
3. Tulis config di `~/.config/lan-mouse/config.toml`.
4. Pasang systemd **user service** (`~/.config/systemd/user/lan-mouse.service`) yang auto-start begitu login ke desktop.
5. Buka firewall UDP `4242` kalau `ufw` aktif.
6. Cetak fingerprint, hostname, dan username SSH laptop tersebut di akhir.

## Pairing (sekali saja)

Ini satu-satunya langkah manual, demi keamanan — supaya bukan sembarang device di jaringan yang bisa kontrol keyboard/mouse kamu (lan-mouse menolak koneksi dari sertifikat yang belum di-authorize, tidak ada cara bypass). Setelah pairing ini, semuanya otomatis selamanya.

### Cara mudah: otomatis lewat SSH

`lan-mouse-setup.sh` sudah otomatis install & aktifkan `openssh-server` di kedua laptop, jadi tinggal jalankan **satu perintah ini saja** di salah satu laptop — otomatis tukar & authorize fingerprint dua arah, tanpa copy-paste manual:

```bash
./pair-laptops.sh dnayaka@laptop-kiri.local
```

(ganti `dnayaka` dan `laptop-kiri.local` sesuai user/hostname laptop lawan)

### Cara manual (kalau tidak ada akses SSH antar laptop)

Di **laptop-kanan**, authorize fingerprint laptop-kiri (yang dicetak script `lan-mouse-setup.sh` di atas):

```bash
lan-mouse cli authorize-key "laptop-kiri" "<fingerprint-laptop-kiri>"
lan-mouse cli save-config
```

Di **laptop-kiri**, authorize fingerprint laptop-kanan:

```bash
lan-mouse cli authorize-key "laptop-kanan" "<fingerprint-laptop-kanan>"
lan-mouse cli save-config
```

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

Config `lan-mouse` tetap sama persis seperti instalasi di atas:

```toml
# laptop-kiri: ~/.config/lan-mouse/config.toml
[[clients]]
position = "right"
hostname = "laptop-kanan"
```

```toml
# laptop-kanan: ~/.config/lan-mouse/config.toml
[[clients]]
position = "left"
hostname = "laptop-kiri"
```

**Tes**: taruh kursor di monitor eksternal, geser ke kanan sampai mentok tepi kanan monitor itu → kursor harus lompat ke laptop-kanan. Kalau malah nyangkut balik ke layar bawaan laptop-kiri dulu, berarti urutan di Settings → Displays belum sesuai — drag ulang.

## Troubleshooting

```bash
# cek log service
journalctl --user -u lan-mouse -f

# cek hostname lawan bisa di-resolve via mDNS
ping laptop-kanan.local

# lihat status client yang terkonfigurasi
lan-mouse cli list
```

## Opsional: auto-login (zero-touch setelah nyala)

Service `lan-mouse` baru jalan setelah ada sesi GNOME yang login (butuh akses compositor). Kalau mau benar-benar hands-off dari saat laptop dinyalakan (tanpa perlu ketik password login), aktifkan auto-login lewat **Settings → Users**. Trade-off: siapa pun yang menyalakan laptop bisa langsung akses tanpa password.
