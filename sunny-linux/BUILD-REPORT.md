# BUILD REPORT — Ubuntu Server บน Redmi Note 10 4G (sunny)

สร้างเมื่อ: 2026-10-30 · host: WSL2 Ubuntu 24.04.3 (8 core / 7 GB) · toolchain: GCC 13.2 aarch64

---

## 1. ผลลัพธ์ที่ได้ (คัดลอกมาไว้ที่ `sunny-linux/out/`)

| ไฟล์ | ขนาด | sha256 | ใช้ทำอะไร |
|---|---|---|---|
| `boot.img` | 42 MB | `2880d829…410d14` | kernel (header v4, ไม่มี ramdisk) |
| `vendor_boot.img` | 1.1 MB | `fb2d2806…f8e13e9` | initramfs + `sm6150.dtb` (header v4) |
| `Image` | 43,890,696 B | `50e7eb2c…4f9f279` | raw kernel (สำรอง) |
| `dtb` | 397,267 B | `e6089562…98e83a85` | sm6150.dtb (คอมไพล์จากซอร์ส) |
| `initramfs.cpio.gz` | 658 KB | `0074291a…2d74beb7` | busybox + `/init` |
| `rootfs.img` | 6.0 GB (จริง 6,442,450,944 B) | — | Ubuntu 24.04 arm64, label `sunny-root` |
| `rootfs.img.gz` | 75 MB | `9a38eaf3…daf253aa` | ไฟล์เดียวกันแบบ gzip (ใช้กับ dd ผ่าน TWRP) |
| `rootfs.simg` | 146 MB (sparse) | `02f7a5a9…47f8466` | พร้อมแฟลชด้วย `fastboot flash -S400M userdata` (ไม่ต้อง TWRP) |

`rootfs.img` ตรวจด้วย `99-verify-rootfs.sh` แล้ว: `systemd`, `sshd`, `ssh.service` (enabled), `/etc/systemd/network/10-usb0.network`, user `dev:1000`, fstab `LABEL=sunny-root / ext4` — ครบทุกไฟล์

`99-check-config.sh` ตรวจ driver ที่จำเป็นต่อการบูต: UFS (`SCSI_UFS_QCOM` + `PHY_QCOM_UFS`), ext4, initramfs, devtmpfs, USB gadget (`DWC3_MSM` + configfs RNDIS/ECM), RPMh regulator/clock, GENI serial, `ARCH_SM6150` → **ครบทั้ง 26 ตัว**

ตรวจแล้วด้วย `unpack_bootimg`:

```
boot.img        : ANDROID! header v4, kernel 43,890,696 B, ramdisk 0
vendor_boot.img : VNDRBOOT header v4, ramdisk 673,539 B, dtb 397,267 B
cmdline         : console=ttyMSM0,115200n8 loglevel=7 root=LABEL=sunny-root rw
                  androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3
                  loop.max_part=7 lpm_levels.sleep_disabled=1 service_locator.enable=1
                  swiotlb=1 msm_rtb.filter=0x237 kpti=off
```

## 2. ซอร์สที่ใช้ (commit จริง)

| ชิ้น | repo / branch | commit |
|---|---|---|
| kernel | `Neternels/android_kernel_xiaomi_sunny` @ `LA.UM.9.1` | `6f0680fc1` (2022-12-30) |
| device tree | `yaap/device_xiaomi_sunny` @ `sixteen` | `599a54d` (2023-10-09) |
| dtb (อ้างอิง) | `yaap/device_xiaomi_sunny-kernel` @ `seventeen` | `dtb/sm6150.dtb` |

kernel version: **4.14.206** · config: 1727 `=y`, 1 `=m` (wireguard.ko)

## 3. สิ่งที่ต้องแก้เพื่อให้คอมไพล์ผ่าน (ทั้งหมดอยู่ใน `build/`)

| # | อาการ | สาเหตุ | วิธีแก้ (ไฟล์) |
|---|---|---|---|
| 1 | kconfig ถามค้าง `LITTLE_CPU_MASK [] (NEW) aborted!` | defconfig ทิ้งค่า int ว่าง | `CONFIG_{LITTLE,BIG}_CPU_MASK=0`, `NR_CPUS=8` (`sunny.fragment`) |
| 2 | `make oldconfig </dev/null` วน `Error in reading or end of file` | EOF loop ของ kconfig | เปลี่ยนเป็น `olddefconfig` + ตรวจค่า (`02-kernel.sh`) |
| 3 | `expected string literal before ARM64_LSE_ATOMIC_INSN` | `cmpxchg.h` ไม่มี fallback, macro นิยามเฉพาะเมื่อเปิด LSE | `CONFIG_ARM64_LSE_ATOMICS=y` |
| 4 | `'last_input_time' undeclared` (`drm_atomic.c`) | hack Xiaomi cherry-pick ไม่ครบ | ตัดเงื่อนไข → `patches.sh` |
| 5 | `arrayval` / `profile_judge_done` / `camera_id` no member | ฟิลด์ถูก guard ด้วย `CONFIG_XIMI_MOJITO` แต่ defconfig ไม่เปิด | `CONFIG_XIMI_MOJITO=y` |
| 6 | `undefined reference to is_libcam` | techpack กล้องอ้างตัวแปรใน `init/userland_worker.c` ที่ไม่ถูกคอมไพล์ | `# CONFIG_SPECTRA_CAMERA is not set` |
| 7 | `cp: cannot stat './modules.order'` | เรียก `modules_install` ก่อน build modules | build `modules` ก่อน + ข้ามถ้าไม่มี `.ko` |

## 4. โครงสร้าง boot ที่ได้

```
boot_a        ← boot.img        (kernel 4.14.206, header v4)
vendor_boot_a ← vendor_boot.img (initramfs หา LABEL=sunny-root → switch_root, + dtb)
dtbo_a        ← ไม่แตะ (ใช้ของเดิมบนเครื่อง = overlay เฉพาะรุ่น)
userdata      ← rootfs.img (Ubuntu 24.04 arm64, sshd:22)
```

`/init` ใน initramfs:
1. mount `proc/sys/devtmpfs`, `mdev -s`
2. รอ `/dev/block/by-name/userdata` สูงสุด 60 วิ
3. mount ext4 → ตรวจว่ามี `/lib/systemd/systemd`
4. `switch_root` เข้า systemd (ถ้าล้ม = เปิด shell บน ttyGS0 ให้กู้)

## 5. ขั้นต่อไป (ต้องมีเครื่องต่อ USB)

> WSL มองไม่เห็น USB → สั่ง `fastboot` จากฝั่ง Windows เท่านั้น (`02-flash.ps1`)

```powershell
# 1) ยืนยันรุ่น + บันทึก log
.\00-verify.ps1

# 2) สำรองก่อน — ห้ามข้าม modem/persist
.\01-backup.ps1 -Mode partitions -Twrp twrp-sunny.img

# 3) แฟลช boot + vendor_boot
.\02-flash.ps1 -Mode boot

# 4) เขียน rootfs ลง userdata (sparse — ไม่ต้องใช้ TWRP)
.\02-flash.ps1 -Mode userdata

# 5) ย้อนกลับถ้าพัง
.\02-flash.ps1 -Mode stock
```

## 6. ข้อจำกัดที่ยังต้องยอมรับ

- native Ubuntu = ไม่มี Android HAL → **ไม่มี 4G/SMS/กล้อง/เสียง** (เราตัด techpack กล้องออกแล้ว)
- จอ: `DRM_MSM` คอมไพล์ติด แต่ panel driver ของ sunny อยู่ใน dtbo overlay — ถ้า overlay ไม่แมตช์กับ kernel ที่ไม่มี Xiaomi patch ครบ อาจได้จอดำ (ใช้ SSH แทน)
- USB net: ต้องมี `usb0` ขึ้นจาก configfs; ถ้าไม่ขึ้นให้ดู log ที่ `ttyGS0` (baud 115200)
- bootloop → `fastboot flash boot logs/backup_*/boot_a.img` กลับได้เสมอ

## 7. เข้าใช้หลังบูตติด

```
USB net (ผ่าน usb0)  : ssh dev@192.168.42.2   (รหัส ubuntu1234, port 22)
จอ/คีย์บอร์ด OTG      : console ttyGS0 ถ้า systemd ไม่ขึ้นจะได้ rescue shell
Tailscale            : apt install tailscale && tailscale up
```

`/etc/systemd/network/10-usb0.network` ตั้ง IP ฝั่งเครื่องไว้ `192.168.42.2/24` — ฝั่งคอมพิวเตอร์ให้ตั้ง adapter เป็น `192.168.42.1/24` แล้ว ssh เข้าได้ทันที

## 8. สคริปต์ใน `build/` (ฝั่ง WSL)

> ฝั่ง Windows: `00-verify.ps1` (ยืนยันรุ่น) · `01-backup.ps1` (สำรอง) · `02-flash.ps1` (แฟลช)

| ไฟล์ | หน้าที่ |
|---|---|
| `run-build.sh` | ตัวขับ: `env\|sources\|kernel\|rootfs\|initramfs\|bootimg\|all` |
| `00-env.sh` … `05-bootimg.sh` | แต่ละสเตจของ build |
| `06-flash.sh` | `boot\|userdata\|userdata-sparse\|stock` |
| `patches.sh` | แพตช์ซอร์ส (idempotent) — รันก่อน build อัตโนมัติ |
| `99-check-config.sh` | ตรวจ driver จำเป็น 26 ตัวใน `.config` |
| `99-verify-images.sh` | แตก boot/vendor_boot ด้วย `unpack_bootimg` + sha256 |
| `99-verify-rootfs.sh` | ตรวจไฟล์สำคัญใน `rootfs.img` ด้วย `debugfs` |
| `99-log-errors.sh` / `99-errors-by-file.sh` | สรุป error จาก `build.log` |
