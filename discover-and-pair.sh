#!/usr/bin/env bash
# Auto-discover laptop lain di jaringan lokal (mDNS) yang menjalankan lan-mouse-setup.sh,
# lalu authorize fingerprint & tambahkan sebagai client secara otomatis - dua arah,
# tanpa perlu tahu hostname/user/IP laptop lawan.
#
# Syarat: lan-mouse-setup.sh sudah dijalankan di laptop ini DAN laptop lawan
# (dengan posisi left/right/top/bottom yang saling berkebalikan).
#
# Usage: ./discover-and-pair.sh   (tanpa argumen, jalankan di kedua laptop atau salah satu)

set -euo pipefail

CERT="$HOME/.config/lan-mouse/lan-mouse.pem"
LAN_MOUSE="$HOME/.cargo/bin/lan-mouse"
MY_HOST="$(hostname)"

if [ ! -f "$CERT" ]; then
  echo "Sertifikat belum ada ($CERT). Jalankan lan-mouse-setup.sh dulu di laptop ini." >&2
  exit 1
fi

echo "==> Mencari laptop lain di jaringan (mDNS)..."

FOUND_ANY=0
for attempt in 1 2 3; do
  RESULTS=$(avahi-browse -r -p -t _lanmouse._udp 2>/dev/null | grep '^=' || true)
  [ -n "$RESULTS" ] && break
  echo "    belum ketemu, coba lagi (${attempt}/3)..."
  sleep 3
done

if [ -z "$RESULTS" ]; then
  echo ""
  echo "Tidak ada laptop lain ditemukan di jaringan ini." >&2
  echo "Pastikan: (1) lan-mouse-setup.sh sudah dijalankan di laptop satunya," >&2
  echo "(2) kedua laptop di jaringan WiFi/LAN yang sama," >&2
  echo "(3) mDNS tidak diblok router (beberapa WiFi publik/guest network memblokir multicast)." >&2
  exit 1
fi

while IFS=';' read -r _flag _iface _proto _name _type _domain host _addr _port txt; do
  # PENTING: simpan hostname LENGKAP dengan akhiran .local - itu yang dipakai
  # nss-mdns/avahi buat resolve. Tanpa .local, lan-mouse malah nyoba DNS publik
  # biasa dan gagal terus-terusan (bukan ke avahi/mDNS sama sekali).
  peer_fqdn="$host"
  bare_host="${peer_fqdn%.local}"

  # skak diri sendiri, case-insensitive (avahi kadang lowercase-kan hostname)
  if [ "${bare_host,,}" = "${MY_HOST,,}" ]; then
    continue
  fi

  role=$(grep -oP '(?<=role=)[a-z]+' <<< "$txt" || true)
  fp=$(grep -oP '(?<=fp=)[0-9a-f:]+' <<< "$txt" || true)

  if [ -z "$role" ] || [ -z "$fp" ]; then
    continue
  fi

  echo ""
  echo "==> Ketemu: $peer_fqdn (posisi relatif ke laptop ini: $role)"
  FOUND_ANY=1

  echo "    Authorize fingerprint..."
  "$LAN_MOUSE" cli authorize-key "$bare_host" "$fp"

  existing_id=$("$LAN_MOUSE" cli list | grep -oP "id \K[0-9]+(?=: ${peer_fqdn}:)" || true)
  if [ -z "$existing_id" ]; then
    echo "    Tambah client baru..."
    "$LAN_MOUSE" cli add-client --hostname "$peer_fqdn"
    sleep 1
    existing_id=$("$LAN_MOUSE" cli list | grep -oP "id \K[0-9]+(?=: ${peer_fqdn}:)" || true)
  fi

  if [ -z "$existing_id" ]; then
    echo "    Gagal menambahkan client $peer_fqdn, skip." >&2
    continue
  fi

  echo "    Set posisi = $role, aktifkan..."
  "$LAN_MOUSE" cli set-position "$existing_id" "$role"
  "$LAN_MOUSE" cli activate "$existing_id"
done <<< "$RESULTS"

if [ "$FOUND_ANY" -eq 0 ]; then
  echo "Tidak ada entri valid (role/fingerprint) ditemukan dari laptop lain." >&2
  exit 1
fi

"$LAN_MOUSE" cli save-config

echo ""
echo "================================================================"
echo " Pairing selesai. Konfigurasi tersimpan permanen (activate_on_startup)."
echo " Coba geser kursor ke tepi layar untuk tes perpindahan ke laptop lain."
echo "================================================================"
