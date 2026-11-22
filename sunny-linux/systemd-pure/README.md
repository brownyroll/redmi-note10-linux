# Handoff: Redmi Note 10 4G (sunny) → pure Linux/systemd

อัปเดต: 2026-11-22  
เครื่องเป้าหมาย: `100.100.2.1`, user `dev`, pass `ubuntu1234`, `sudo` ไม่ต้องใส่รหัส  
root pass: `ubuntu1234`

## สถานะปัจจุบัน

- Redmi ยังเป็น server เหมือนเดิม **ยังไม่มีอะไรถูกเปลี่ยน** จากรอบที่หยุดไป
- `/usr/bin/systemctl` ยังเป็น wrapper Python (ไม่ใช่ systemctl ตัวจริง)
- `/usr/local/bin/systemctl` ยังเป็น wrapper shell
- `/usr/local/sbin/sunny-native-init` ยังไม่ได้ตั้ง immutable
- ไม่มี process `install.sh` / `apt-get` ค้างอยู่
- D-Bus ModemManager ยังเป็น `.disabled`
- kernel รันอยู่คือ `4.14.206-NetErnels-PhoneSunny-Docker` และ cgroup ที่จำเป็นพร้อมแล้ว (`devices`, `pids`, `memory`, `IPC_NS`, `POSIX_MQUEUE`)
- โฟลเดอร์ staging อยู่ที่ `sunny-linux/systemd-pure/`

ตรวจสถานะก่อนเริ่ม:

```bash
ssh dev@100.100.2.1
file -b /usr/bin/systemctl
file -b /usr/local/bin/systemctl
lsattr /usr/local/sbin/sunny-native-init
```

ค่าที่ควรเห็นก่อนเริ่ม: `Python script`, `POSIX shell script`, และไม่มี `i` ใน `lsattr`

---

## ทางเลือก A — แนะนำ: ทำผ่าน SSH ไม่ต้องเสียบสาย/แฟลช

วิธีนี้ PID1 จะเป็น `/lib/systemd/systemd` โดยตรง ผ่าน wrapper ที่ถอดกลับได้อัตโนมัติใน 180 วินาทีถ้า systemd บูตไม่สำเร็จ

จาก PowerShell/WSL ที่เข้าถึง `100.100.2.1` ได้:

```powershell
scp -r .\systemd-pure dev@100.100.2.1:/tmp/systemd-pure
ssh dev@100.100.2.1
```

บนเครื่อง:

```bash
sudo sh /tmp/systemd-pure/install.sh
```

สิ่งที่สคริปต์ทำ:

- โหลดแพ็กเกจ `systemd` แล้วแทนที่ `/usr/bin/systemctl` ด้วย binary ตัวจริง
- ย้าย wrapper เก่าไป `/usr/local/bin/systemctl.sunny-disabled`
- คืน `/usr/share/dbus-1/system-services/org.freedesktop.ModemManager1.service`
- ตั้ง `default.target` เป็น `multi-user.target`
- ติดตั้ง/เปิด unit: `ssh`, `NetworkManager`, `ModemManager`, `qrtr-ns`, `rmtfs`, `modem-hold`, `systemd-boot-ok`, `usb-gadget`, `seatd`, `tailscaled`
- masked `connman`, `systemd-networkd` ออกไปเพราะชนกับ NetworkManager
- เขียน `/etc/sysctl.d/99-pure-router.conf` ให้ `net.ipv4.ip_forward=1`
- override `rmtfs.service` ให้ใช้ `/usr/bin/rmtfs -r -v` และสร้าง symlink `/dev/qcom_rmtfs_uio1 -> /dev/uio0`
- สำรอง `/usr/local/sbin/sunny-native-init` ไว้ที่ `.sunny-backup`
- แทนที่ด้วย wrapper ที่ `exec /lib/systemd/systemd` แล้ว `chattr +i`

หลัง install สำเร็จ ให้รีบูต:

```bash
sudo reboot
```

รอประมาณ 30–90 วินาทีแล้ว SSH เข้าใหม่

### ตรวจหลังรีบูต

```bash
ps -p 1 -o comm=
systemctl --version | head -n 1
systemctl --failed --no-pager
systemctl status ssh NetworkManager ModemManager qrtr-ns rmtfs modem-hold --no-pager
ip -br link
nmcli dev status
```

ควรเห็น `systemd` จากคำสั่งแรก

### ถ้า systemd ไม่ขึ้น

wrapper จะรอ 180 วินาที ถ้าไม่เจอ `/run/systemd-boot-ok` มันจะถอด immutable, กู้backup เก่า, แล้ว reboot เอง

กู้ด้วยมือ:

```bash
sudo chattr -i /usr/local/sbin/sunny-native-init
sudo cp /usr/local/sbin/sunny-native-init.sunny-backup /usr/local/sbin/sunny-native-init
sudo reboot
```

ดู log:

```bash
cat /var/log/systemd-rollback.log
journalctl -b -1 --no-pager | tail -n 100
```

---

## ทางเลือก B — แฟลชจริงจาก Windows (ไม่ผ่าน sunny เลย)

ใช้เมื่อต้องการให้ initramfs เรียก systemd โดยตรง ไม่มีสคริปต์ `sunny-*` เป็น PID1 เลย  
**ทำอย่างเดียวกับทางเลือก A เท่านั้น อย่าทำพร้อมกัน**

### 1) แก้ initramfs ใน WSL

บน WSL ที่มี repo ที่ `/root/sunny`:

```bash
cd /root/sunny/sunny-linux/build
cp native-initramfs-init native-initramfs-init.systemd.bak
```

แก้บรรทัดสุดท้ายของ `native-initramfs-init` จาก:

```sh
exec switch_root /newroot /usr/local/sbin/sunny-native-init
```

เป็น:

```sh
exec switch_root /newroot /lib/systemd/systemd
```

จากนั้น build ใหม่:

```bash
bash 60-build-native.sh
```

ผลลัพธ์: `$SUNNY/out/vendor_boot-native.img`

### 2) prepare ไฟล์ให้ Windows

จาก WSL คัดลอกไป `out\` ของ Windows:

```bash
cp /root/sunny/out/vendor_boot-native.img \
  "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot.img"
sha256sum /root/sunny/out/vendor_boot-native.img
```

`boot.img` ไม่ต้องเปลี่ยน (kernel ตัวเดิมใช้ได้)

### 3) สำรองก่อนแฟลช

จาก PowerShell ในโฟลเดอร์ `sunny-linux`:

```powershell
.\00-verify.ps1
.\01-backup.ps1 -Mode partitions -Twrp twrp-sunny.img
```

ห้ามข้าม `modem`, `persist`, `modemst1/2`, `fsg`, `fsc`

### 4) แฟลช

```powershell
.\02-flash.ps1 -Mode check
.\02-flash.ps1 -Mode boot
```

สคริปต์จะเขียนทั้ง `boot` และ `vendor_boot` แล้ว reboot

### 5) ถ้าต้องการกลับของเดิม

```powershell
.\02-flash.ps1 -Mode stock
```

หรือกู้เฉพาะ rootfs ไม่ต้องแตะ:

```bash
sudo cp -a /usr/local/sbin/sunny-native-init.sunny-backup /usr/local/sbin/sunny-native-init
sudo chattr -i /usr/local/sbin/sunny-native-init 2>/dev/null || true
```

---

## หลัง systemd ขึ้นแล้ว — งานที่เหลือ

1. ตรวจ QMI อีกครั้ง:

```bash
sudo qrtr-ns -f &
sudo rmtfs -r -v &
sudo python3 -c "import os,time; fd=os.open('/dev/subsys_modem', os.O_RDWR|os.O_NONBLOCK); time.sleep(86400)" &
qmicli -d qrtr://0 --dms-get-ids
```

2. แก้ปัญหา 4G data:

- ยังขาด `ipa_fws.mbn`
- kernel ยังไม่มี `CONFIG_QCOM_QMI_RMNET`
- ต้องหา firmware จาก ROM/repo ของ sunny/mojito หรือ rebuild kernel

3. เมื่อได้ `rmnet*` ขึ้นมาแล้วค่อยตั้ง NAT ไป `eth0` ด้วย `iptables-legacy` + sysctl `net.ipv4.ip_forward=1`

4. call forwarding:

```text
*21*+66807295932#
```

5. SMS forwarding ต้องเขียน daemon ฟัง QMI WMS แล้วส่งต่อไป `+66807295932`

---

## ข้อควรระวัง

- อย่าเปิด `/dev/subsys_ipa_fws` โดยไม่มี `ipa_fws.mbn` — จะติด `OFFLINING`/`D-state` และเคยทำให้ reboot
- `qrtr` ต้องใช้ node `0` ไม่ใช่ `1`
- `rmtfs` ห้ามใช้ `-s` เพราะ kernel ไม่มี `CONFIG_REMOTEPROC`
- เครื่องนี้ kernel 4.14 ไม่รองรับ `nf_tables` ให้ใช้ `iptables-legacy`
- ถ้า SSH หายหลังบูต ให้รอ 180 วินาทีสำหรับ auto-rollback ก่อนตัดใจแฟลช stock
