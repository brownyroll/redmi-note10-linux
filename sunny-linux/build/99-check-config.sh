#!/usr/bin/env bash
# 99-check-config.sh — ตรวจว่า driver ที่จำเป็นต่อการบูตเข้า rootfs ถูกเปิดไว้จริง
C="${1:-${SUNNY_ROOT:-/root/sunny}/out/.config}"
[ -f "$C" ] || { echo "ไม่พบ $C"; exit 1; }

need='
CONFIG_BLK_DEV_INITRD
CONFIG_DEVTMPFS
CONFIG_DEVTMPFS_MOUNT
CONFIG_TMPFS
CONFIG_EXT4_FS
CONFIG_SCSI_UFSHCD
CONFIG_SCSI_UFSHCD_PLATFORM
CONFIG_SCSI_UFS_QCOM
CONFIG_PHY_QCOM_UFS
CONFIG_USB_GADGET
CONFIG_USB_CONFIGFS
CONFIG_USB_CONFIGFS_RNDIS
CONFIG_USB_CONFIGFS_ECM
CONFIG_USB_CONFIGFS_F_FS
CONFIG_USB_DWC3
CONFIG_USB_DWC3_MSM
CONFIG_USB_MSM_SSPHY_QMP
CONFIG_SERIAL_MSM_GENI
CONFIG_QCOM_GENI_SE
CONFIG_ARM_SMMU
CONFIG_THERMAL_TSENS
CONFIG_REGULATOR_RPMH
CONFIG_MSM_CLK_RPMH
CONFIG_QTI_RPMH_API
CONFIG_PINCTRL_SM6150
CONFIG_ARCH_SM6150
'

bad=0
for s in $need; do
  line=$(grep -m1 -E "^$s=|^# $s is not set" "$C" || true)
  case "$line" in
    "$s=y") printf '  ✓ %s\n' "$s" ;;
    "")     printf '  ? %s  (ไม่มีในไฟล์ — อาจถูก rename หรือขึ้นกับ symbol อื่น)\n' "$s"; bad=1 ;;
    *)      printf '  ✗ %s   <<< %s\n' "$s" "$line"; bad=1 ;;
  esac
done

echo
if [ "$bad" -eq 0 ]; then echo "ผล: ครบทุกตัว"; else echo "ผล: มีตัวที่ยังไม่ครบ (ดู ✗ / ? ด้านบน)"; fi
