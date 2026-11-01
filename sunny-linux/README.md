# sunny-linux — Ubuntu Server แบบ native บน Redmi Note 10 4G (sunny)

> เป้าหมาย: บูต Ubuntu Server ARM64 ตรง ๆ บนเครื่อง (ไม่ใช่ proot, ไม่ใช่ Android)
> แนวเดียวกับ BareDroid: kernel + initramfs + rootfs ของเราเอง บนพาร์ทิชันจริง

---

## 0. ข้อเท็จจริงของเครื่อง (จาก `redmi-getvar-all.txt`)

| รายการ | ค่า |
|---|---|
| product | `sunny` (Redmi Note 10 4G อินเดีย, SD678) |
| hw-revision | 10001 |
| serial | 579a9d18 |
| anti | 1 |
| slots | A/B, ปัจจุบัน `a` |
| storage | UFS (`variant: SM6 UFS`) |
| kernel ปัจจุบัน | 4.14.x (Qualcomm LA.UM.9.1) |
| max-download-size | 805306368 (768 MB) |
| secure | yes (AVB เปิด — ต้อง disable-verity/verification ตอนแฟลช) |

ขนาดพาร์ทิชันที่เกี่ยวกับงานนี้:

```
boot_a        0x08000000  128 MB     ← Image (kernel) + cmdline
vendor_boot_a 0x06000000   96 MB     ← ramdisk (initramfs) อยู่ที่นี่ ไม่ใช่ boot
dtbo_a        0x01800000   24 MB     ← DTB/DTBO overlay
super         0x220000000  8.5 GB    ← dynamic partitions (system/vendor/product)
userdata      0x1A2CBD3000 ~105 GB   ← ที่จะวาง rootfs
modem_a       0x10000000  256 MB     ← สำรองก่อน!
persist       0x02000000   32 MB     ← สำรองก่อน! (sensor/mac/wifi cal)
misc/metadata/frp/keystore          ← สำรอง metadata + persist พอ
```

จุดสำคัญ: **sunny มี `vendor_boot`** → boot header เป็น v3/v4 และ **ramdisk อยู่ใน vendor_boot ไม่ใช่ boot**
ถ้าแพ็กผิดที่ เครื่องจะไม่บูต (แต่กู้ได้ด้วย fastboot เพราะ bootloader ปลดแล้ว)

---

## 1. ลำดับงาน (ทำตามเลข)

| ขั้น | ไฟล์ | ทำอะไร |
|---|---|---|
| 0 | `00-verify.ps1` | ยืนยันว่าเป็น sunny จริง + บันทึก log ลง `logs/` |
| 1 | `01-backup.ps1` | สำรอง getvar, fastboot ROM เดิม, modem/persist/metadata (ผ่าน TWRP) |
| 2 | `build/00-env.sh` | เตรียม WSL/Ubuntu: aarch64 toolchain, deps, mkbootimg |
| 3 | `build/01-sources.sh` | โคลน kernel (NetErnels) + device tree (YAAP) |
| 4 | `build/02-kernel.sh` | cross-compile `Image`, `dtbs`, `modules` |
| 5 | `build/03-rootfs.sh` | สร้าง `rootfs.img` จาก ubuntu-base-24.04 arm64 + sshd + user |
| 6 | `build/04-initramfs.sh` | initramfs หา root ด้วย PARTUUID, mount, switch_root, เปิด USB net |
| 7 | `build/05-bootimg.sh` | แพ็ก `boot.img` (kernel) + `vendor_boot.img` (ramdisk) |
| 8 | `build/06-flash.sh` | แฟลช + ปิด AVB + ฟอร์แมต userdata |

---

## 2. แหล่งซอร์สที่ใช้

| ชิ้นส่วน | ที่มา | หมายเหตุ |
|---|---|---|
| Kernel 4.14.206 (CAF LA.UM.9.1) | `github.com/Neternels/android_kernel_xiaomi_sunny` (branch `LA.UM.9.1`) | ใช้เป็น base — มี defconfig + DTS ของ sunny/mojito ครบ |
| Device tree / DTB / DTBO | `github.com/yaap/device_xiaomi_sunny` (branch `sixteen`) + kernel `arch/arm64/boot/dts/vendor/qcom` | เอา `BoardConfig.mk` (base address, cmdline, page size) มาใช้กับ mkbootimg |
| แนวคิด BareDroid | `github.com/ucsb-seclab/baredroid` | โครง backup/restore/partition ก่อนเขียนทับ — ยืมสคริปต์ backup มาใช้ |
| rootfs | `cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.*-base-arm64.tar.gz` | ไม่ใช้ cloud image (ใหญ่เกิน/ไม่ต้องใช้) |

> ⚠️ kernel 4.14 ของ CAF ยังพึ่ง `techpack/` และ module เยอะ — งานรอบแรก **ตัด techpack ออก** (audio/camera ไม่ต้องใช้กับ server) เพื่อลดจุดพัง

---

## 3. สถาปัตยกรรมที่จะได้

```
UFS ─┬─ boot_a      : Image (kernel 4.14, defconfig แก้เป็น systemd-friendly)
     ├─ vendor_boot_a: initramfs (busybox) → หา root, mount, switch_root
     ├─ userdata    : ext4 → Ubuntu 24.04 arm64 (systemd, sshd:22)
     └─ persist/modem: ของเดิม ไม่แตะ

network: USB (dwc3 gadget, RNDIS/ECM → 192.168.42.x) + WiFi (wlan driver จาก techpack ถ้าเปิด)
```

---

## 4. สิ่งที่จะ "ไม่" ทำงาน (ต้องยอมรับตั้งแต่ต้น)

native Ubuntu บน SoC โทรศัพท์ = ไม่มี Android HAL เลย:

- ❌ โทรศัพท์/SMS/4G (ต้องใช้ modem + RIL — ยากมาก)
- ❌ กล้อง (techpack camera)
- ❌ จอ/ทัช (ถ้า DTS ไม่มี panel driver ที่ mainline รู้จัก → ได้แค่ framebuffer/หรือดำ)
- ✅ SSH ผ่าน USB net / WiFi (ถ้า driver ขึ้น)
- ✅ CPU/RAM/UFS/thermal พื้นฐาน, apt, docker-arm64 (แบบช้า)

ถ้าต้องการ "ใช้เป็นมือถือได้" → ทางนั้นคือ Halium/Ubuntu Touch (คนละเส้น ใช้ Android HAL) ไม่ใช่ BareDroid-style

---

## 5. กติกาความปลอดภัย

1. **ห้ามแฟลชอะไรก่อน `01-backup.ps1` เสร็จ** — modemst1/2, fsg, fsc, persist หายแล้วเครื่องจะไม่ติด сет็จถาวร
2. ทุกครั้งที่แฟลช boot/vendor_boot ให้เก็บ `.img` เดิมไว้ (`logs/backup/boot_stock.img`)
3. เครื่องต้องชาร์จ > 60% (getvar บอก battery 4427 mV ≈ ยังไม่เต็ม)
4. ถ้า bootloop → `fastboot flash boot boot_stock.img` กลับได้เสมอ เพราะ bootloader ปลดแล้ว
