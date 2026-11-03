#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d /tmp/sunny-usb-role-test.XXXXXX)
PID=
cleanup(){ [ -z "$PID" ] || kill "$PID" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
SYS="$TMP/sys"; CFG="$TMP/configfs"; RUN="$TMP/run"
mkdir -p "$SYS/class/dual_role_usb/otg_default" "$SYS/class/power_supply/usb" \
  "$SYS/class/udc/dummy_udc" "$SYS/bus/usb/devices/usb1" "$CFG/usb_gadget/g1" "$RUN"
printf 'ufp\n' > "$SYS/class/dual_role_usb/otg_default/mode"
printf 'device\n' > "$SYS/class/dual_role_usb/otg_default/data_role"
printf 'sink\n' > "$SYS/class/dual_role_usb/otg_default/power_role"
printf '1\n' > "$SYS/class/power_supply/usb/present"
printf 'Source attached (default current)\n' > "$SYS/class/power_supply/usb/typec_mode"
printf '0\n' > "$SYS/bus/usb/devices/usb1/devpath"
printf 'dummy_udc\n' > "$CFG/usb_gadget/g1/UDC"
SCRIPT=${1:-$(cd "$(dirname "$0")/.." && pwd)/build/sunny-usb-role}
env SUNNY_SYS_ROOT="$SYS" SUNNY_CONFIGFS_ROOT="$CFG" SUNNY_USB_ROLE_RUN="$RUN" \
  SUNNY_SKIP_MDEV=1 "$SCRIPT" >"$TMP/log" 2>&1 & PID=$!
sleep 4
grep -q '^STATE=PC/device connected' "$RUN/status"
printf '0\n' > "$SYS/class/power_supply/usb/present"
sleep 7
grep -q '^ufp$' "$SYS/class/dual_role_usb/otg_default/mode"
printf 'Sink attached\n' > "$SYS/class/power_supply/usb/typec_mode"
sleep 7
grep -q '^dfp$' "$SYS/class/dual_role_usb/otg_default/mode"
grep -q '^STATE=OTG Host - waiting for hub/device' "$RUN/status"
[ -z "$(cat "$CFG/usb_gadget/g1/UDC")" ]
mkdir -p "$SYS/bus/usb/devices/1-1"; printf '1\n' > "$SYS/bus/usb/devices/1-1/devpath"
sleep 4
grep -q '^STATE=OTG Connected' "$RUN/status"
rm -rf "$SYS/bus/usb/devices/1-1"
printf '1\n' > "$SYS/class/power_supply/usb/present"
printf 'Source attached (default current)\n' > "$SYS/class/power_supply/usb/typec_mode"
sleep 4
grep -q '^ufp$' "$SYS/class/dual_role_usb/otg_default/mode"
grep -q '^dummy_udc$' "$CFG/usb_gadget/g1/UDC"
grep -q '^STATE=PC/device connected' "$RUN/status"
echo 'PASS: gadget -> waiting host -> OTG connected -> PC gadget'
