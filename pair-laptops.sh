#!/usr/bin/env bash
# Otomatis tukar & authorize fingerprint lan-mouse dua arah lewat SSH,
# supaya tidak perlu copy-paste manual fingerprint.
#
# Syarat: lan-mouse-setup.sh sudah pernah dijalankan di KEDUA laptop
# (jadi ~/.config/lan-mouse/lan-mouse.pem sudah ada di keduanya),
# dan SSH ke laptop lawan bisa diakses (openssh-server terinstall di lawan).
#
# Usage (jalankan di salah satu laptop saja, sekali):
#   ./pair-laptops.sh <user@hostname-laptop-lawan>
#
# Contoh:
#   ./pair-laptops.sh dnayaka@laptop-kiri.local

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <user@hostname-laptop-lawan>" >&2
  exit 1
fi

PEER="$1"
CERT="$HOME/.config/lan-mouse/lan-mouse.pem"
LAN_MOUSE="$HOME/.cargo/bin/lan-mouse"

if [ ! -f "$CERT" ]; then
  echo "Sertifikat belum ada di laptop ini ($CERT)." >&2
  echo "Jalankan lan-mouse-setup.sh dulu (minimal sampai systemd service start sekali)." >&2
  exit 1
fi

MY_HOST="$(hostname)"
MY_FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2 | tr 'A-F' 'a-f')
echo "==> Fingerprint laptop ini ($MY_HOST): $MY_FP"

echo "==> Menghubungi $PEER via SSH untuk ambil fingerprint-nya..."
PEER_HOST=$(ssh "$PEER" 'hostname')
PEER_FP=$(ssh "$PEER" 'openssl x509 -in "$HOME/.config/lan-mouse/lan-mouse.pem" -noout -fingerprint -sha256' | cut -d= -f2 | tr 'A-F' 'a-f')
echo "==> Fingerprint $PEER_HOST: $PEER_FP"

echo "==> Authorize $PEER_HOST di laptop ini..."
"$LAN_MOUSE" cli authorize-key "$PEER_HOST" "$PEER_FP"
"$LAN_MOUSE" cli save-config

echo "==> Authorize $MY_HOST di $PEER_HOST (lewat SSH)..."
ssh "$PEER" "\"\$HOME/.cargo/bin/lan-mouse\" cli authorize-key '$MY_HOST' '$MY_FP' && \"\$HOME/.cargo/bin/lan-mouse\" cli save-config"

echo ""
echo "==> Pairing selesai dua arah. Coba geser kursor ke tepi layar untuk tes."
