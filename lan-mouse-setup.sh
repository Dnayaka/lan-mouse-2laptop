#!/usr/bin/env bash
# Setup lan-mouse: share 1 keyboard+mouse antara 2 laptop Ubuntu (GNOME/Wayland) via LAN.
# Jalankan script ini di KEDUA laptop, dengan argumen yang saling berkebalikan (lihat contoh di bawah).
#
# Usage:
#   ./lan-mouse-setup.sh <hostname-laptop-satunya> <posisi-laptop-satunya>
#
# <posisi-laptop-satunya> = left | right | top | bottom
#   -> posisi laptop LAWAN relatif terhadap laptop INI (arah mouse digeser untuk pindah ke sana)
#
# Contoh (laptop A di kiri, laptop B di kanan):
#   di laptop A: ./lan-mouse-setup.sh laptop-b right
#   di laptop B: ./lan-mouse-setup.sh laptop-a left

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <hostname-laptop-lawan> <left|right|top|bottom>" >&2
  exit 1
fi

PEER_HOST="$1"
PEER_POS="$2"

case "$PEER_POS" in
  left|right|top|bottom) ;;
  *) echo "Posisi harus salah satu dari: left right top bottom" >&2; exit 1 ;;
esac

echo "==> Install dependencies build + avahi (mDNS)"
sudo apt update
sudo apt install -y \
  libadwaita-1-dev libgtk-4-dev libx11-dev libxtst-dev pkg-config build-essential \
  avahi-daemon libnss-mdns curl openssl

echo "==> Pastikan avahi (mDNS) aktif supaya hostname .local auto-resolve"
sudo systemctl enable --now avahi-daemon

echo "==> Install Rust toolchain (kalau belum ada)"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1090
source "$HOME/.cargo/env"

echo "==> Build & install lan-mouse (bisa beberapa menit)"
cargo install lan-mouse --locked

mkdir -p "$HOME/.config/lan-mouse"
CONF="$HOME/.config/lan-mouse/config.toml"

if [ ! -f "$CONF" ]; then
  echo "==> Menulis config: $CONF"
  cat > "$CONF" <<EOF
port = 4242

[[clients]]
position = "$PEER_POS"
hostname = "$PEER_HOST"
activate_on_startup = true
EOF
else
  echo "==> $CONF sudah ada, tidak ditimpa. Cek/tambah manual bagian [[clients]] kalau perlu:"
  echo "    position = \"$PEER_POS\""
  echo "    hostname = \"$PEER_HOST\""
  echo "    activate_on_startup = true"
fi

echo "==> Pasang systemd user service (auto-start pas login ke desktop)"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/lan-mouse.service" <<'EOF'
[Unit]
Description=Lan Mouse
After=graphical-session.target
BindsTo=graphical-session.target

[Service]
ExecStart=%h/.cargo/bin/lan-mouse daemon
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now lan-mouse.service

echo "==> Buka firewall UDP 4242 kalau ufw aktif"
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 4242/udp comment "lan-mouse"
fi

echo "==> Tunggu sertifikat ter-generate..."
sleep 2

CERT="$HOME/.config/lan-mouse/lan-mouse.pem"
for i in $(seq 1 5); do
  [ -f "$CERT" ] && break
  sleep 1
done

echo ""
echo "================================================================"
echo " Setup di laptop ini SELESAI."
echo " Hostname laptop ini : $(hostname).local"
echo " Fingerprint laptop ini (kasih ke laptop satunya untuk di-authorize):"
echo ""
openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2 | tr 'A-F' 'a-f'
echo ""
echo " Langkah selanjutnya (SEKALI SAJA, di laptop LAWAN):"
echo "   lan-mouse cli authorize-key \"$(hostname)\" \"<fingerprint-di-atas>\""
echo "   lan-mouse cli save-config"
echo "================================================================"
