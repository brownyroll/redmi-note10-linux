#!/bin/sh
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! file -b /usr/bin/systemctl 2>/dev/null | grep -q ELF; then
  TMP="$(mktemp -d)"
  (cd "$TMP" && apt-get download systemd)
  DEB="$(ls "$TMP"/systemd_*.deb | head -n 1)"
  dpkg-deb --fsys-tarfile "$DEB" | tar -xO ./usr/bin/systemctl > /usr/bin/systemctl.new
  install -m 0755 /usr/bin/systemctl.new /usr/bin/systemctl
  rm -f /usr/bin/systemctl.new
  rm -rf "$TMP"
fi
file -b /usr/bin/systemctl | grep -q ELF
[ ! -e /usr/local/bin/systemctl ] || mv -f /usr/local/bin/systemctl /usr/local/bin/systemctl.sunny-disabled

DBUS=/usr/share/dbus-1/system-services/org.freedesktop.ModemManager1.service
[ ! -f "$DBUS.disabled" ] || mv -f "$DBUS.disabled" "$DBUS"

mkdir -p /etc/systemd/system /etc/systemd/system/multi-user.target.wants
ln -sfn /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target

install -m 0644 "$HERE/systemd-boot-ok.service" /etc/systemd/system/systemd-boot-ok.service
install -m 0644 "$HERE/modem-hold.service" /etc/systemd/system/modem-hold.service
mkdir -p /etc/systemd/system/rmtfs.service.d /etc/systemd/system/ModemManager.service.d
install -m 0644 "$HERE/rmtfs-override.conf" /etc/systemd/system/rmtfs.service.d/override.conf
install -m 0644 "$HERE/ModemManager-override.conf" /etc/systemd/system/ModemManager.service.d/override.conf

printf '%s\n' 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-pure-router.conf

enable_unit() {
  unit="$1"
  src=""
  for d in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
    if [ -f "$d/$unit" ]; then src="$d/$unit"; break; fi
  done
  [ -n "$src" ] || { echo "missing unit: $unit" >&2; exit 1; }
  ln -sfn "$src" "/etc/systemd/system/multi-user.target.wants/$unit"
}

for u in ssh.service NetworkManager.service ModemManager.service qrtr-ns.service rmtfs.service modem-hold.service systemd-boot-ok.service usb-gadget.service seatd.service tailscaled.service; do
  enable_unit "$u"
done

ln -sfn /dev/null /etc/systemd/system/connman.service
ln -sfn /dev/null /etc/systemd/system/systemd-networkd.service
ln -sfn /dev/null /etc/systemd/system/systemd-networkd.socket

TARGET=/usr/local/sbin/sunny-native-init
[ -f "$TARGET.sunny-backup" ] || cp -a "$TARGET" "$TARGET.sunny-backup"
install -m 0755 "$HERE/sunny-native-init.systemd" "$TARGET"
chattr +i "$TARGET"
sync

echo "pure-systemd staging installed; reboot required"
echo "real systemctl: $(file -b /usr/bin/systemctl)"
echo "PID1 wrapper: $TARGET (immutable, rollback in 180s if boot marker missing)"
