#!/usr/bin/env bash
# Setup lan-mouse: share 1 keyboard+mouse antara 2 laptop Ubuntu (GNOME/Wayland) via LAN.
# Jalankan script ini di KEDUA laptop, masing-masing dengan posisi DIRINYA SENDIRI
# (bukan posisi laptop lawan) - jadi tidak perlu tahu hostname laptop satunya sama sekali.
#
# Usage:
#   ./lan-mouse-setup.sh <posisi-laptop-ini>
#
# <posisi-laptop-ini> = left | right | top | bottom
#
# Contoh (2 laptop bersebelahan):
#   di laptop yang di kiri  : ./lan-mouse-setup.sh left
#   di laptop yang di kanan : ./lan-mouse-setup.sh right
#
# Setelah dijalankan di KEDUA laptop, jalankan ./discover-and-pair.sh (tanpa argumen)
# di salah satu/kedua laptop untuk saling menemukan & authorize otomatis lewat mDNS.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <left|right|top|bottom>" >&2
  exit 1
fi

MY_POS="$1"

case "$MY_POS" in
  left|right|top|bottom) ;;
  *) echo "Posisi harus salah satu dari: left right top bottom" >&2; exit 1 ;;
esac

echo "==> Install dependencies build + avahi (mDNS + auto-discovery)"
sudo apt update
sudo apt install -y \
  libadwaita-1-dev libgtk-4-dev libx11-dev libxtst-dev pkg-config build-essential \
  avahi-daemon avahi-utils libnss-mdns curl openssl

echo "==> Pastikan avahi (mDNS) aktif"
sudo systemctl enable --now avahi-daemon

echo "==> Install Rust toolchain (kalau belum ada)"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1090
source "$HOME/.cargo/env"

echo "==> Build & install lan-mouse dari source 'main' GitHub (bisa beberapa menit)"
# PENTING: JANGAN install dari crates.io ("cargo install lan-mouse" biasa).
# Versi 0.11.0 yang dipublish di crates.io masih pakai resolver DNS murni
# (hickory-resolver) yang TIDAK lewat nsswitch.conf/avahi sama sekali - jadi
# hostname .local TIDAK AKAN PERNAH ke-resolve (loop "could not resolve" terus).
# Fix-nya (pakai resolver OS asli / getaddrinfo) baru ada di branch main,
# belum dirilis sebagai versi baru. Makanya install langsung dari git:
cargo install --locked --force --git https://github.com/feschber/lan-mouse lan-mouse

mkdir -p "$HOME/.config/lan-mouse"
CONF="$HOME/.config/lan-mouse/config.toml"

if [ ! -f "$CONF" ]; then
  echo "==> Menulis config awal: $CONF"
  cat > "$CONF" <<EOF
port = 4242
EOF
else
  echo "==> $CONF sudah ada, tidak ditimpa."
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

echo "==> Pasang watchdog auto-retry DNS"
# Bug ketemu: lan-mouse cuma resolve hostname client SEKALI waktu activate -
# tidak ada retry otomatis. Kalau pas service ini start laptop lawan belum
# kelihatan di mDNS (misal baru nyala, atau belum login), ips client nyangkut
# kosong SELAMANYA dan mouse/keyboard tidak akan pernah pindah, sampai
# di-deactivate+activate manual. Watchdog ini jalan berkala lewat systemd timer,
# cari client aktif yang ips-nya kosong, dan paksa resolve ulang otomatis.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/lan-mouse-watchdog.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LAN_MOUSE="$HOME/.cargo/bin/lan-mouse"

"$LAN_MOUSE" cli list 2>/dev/null | while IFS= read -r line; do
  id=$(grep -oP '(?<=^id )[0-9]+' <<< "$line" || true)
  [ -z "$id" ] && continue
  active=$(grep -oP '(?<=active: )[a-z]+' <<< "$line" || true)
  ips=$(grep -oP '(?<=ips: \{)[^}]*' <<< "$line" || true)

  if [ "$active" = "true" ] && [ -z "$ips" ]; then
    echo "$(date '+%F %T') client $id: ips kosong, paksa resolve ulang..."
    "$LAN_MOUSE" cli deactivate "$id"
    sleep 1
    "$LAN_MOUSE" cli activate "$id"
  fi
done
EOF
chmod +x "$HOME/.local/bin/lan-mouse-watchdog.sh"

cat > "$HOME/.config/systemd/user/lan-mouse-watchdog.service" <<'EOF'
[Unit]
Description=Lan Mouse DNS watchdog (auto-retry resolve hostname yang gagal)
After=lan-mouse.service

[Service]
Type=oneshot
ExecStart=%h/.local/bin/lan-mouse-watchdog.sh
EOF

cat > "$HOME/.config/systemd/user/lan-mouse-watchdog.timer" <<'EOF'
[Unit]
Description=Jalankan lan-mouse watchdog tiap 30 detik

[Timer]
OnUnitActiveSec=30s
OnStartupSec=20s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now lan-mouse-watchdog.timer

echo "==> Buka firewall UDP 4242 kalau ufw aktif"
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 4242/udp comment "lan-mouse"
fi

echo "==> Tunggu sertifikat ter-generate..."
CERT="$HOME/.config/lan-mouse/lan-mouse.pem"
for i in $(seq 1 10); do
  [ -f "$CERT" ] && break
  sleep 1
done

MY_FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2 | tr 'A-F' 'a-f')

echo "==> Broadcast identitas laptop ini (posisi + fingerprint) lewat mDNS"
sudo mkdir -p /etc/avahi/services
cat <<EOF | sudo tee /etc/avahi/services/lan-mouse-pair.service > /dev/null
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_lanmouse._udp</type>
    <port>4242</port>
    <txt-record>role=${MY_POS}</txt-record>
    <txt-record>fp=${MY_FP}</txt-record>
  </service>
</service-group>
EOF
sudo systemctl restart avahi-daemon

echo ""
echo "================================================================"
echo " Setup di laptop ini SELESAI."
echo " Hostname laptop ini : $(hostname).local"
echo " Posisi laptop ini   : $MY_POS"
echo " Fingerprint         : $MY_FP"
echo ""
echo " Langkah selanjutnya, SEKALI SAJA (setelah script ini dijalankan di KEDUA laptop"
echo " dengan posisi yang saling berkebalikan, misal left & right):"
echo ""
echo "   ./discover-and-pair.sh"
echo ""
echo " (otomatis menemukan laptop satunya lewat mDNS dan authorize fingerprint,"
echo "  tanpa perlu tahu hostname/user laptop lawan sama sekali)"
echo "================================================================"
