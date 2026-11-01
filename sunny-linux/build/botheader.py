#!/usr/bin/env python3
# botheader.py — อ่าน Android boot image header v3/v4 (และ vendor_boot v4) ถอดค่าจริงทุกฟิลด์
#   ใช้: botheader.py <path image.img>
import struct, sys

def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]

def parse_os(osv):
    major = (osv >> 25) & 0x7F
    minor = (osv >> 18) & 0x7F
    patch = (osv >> 11) & 0x7F
    pl = osv & 0x7FF
    year, month, day = (pl >> 11) + 2000, (pl >> 7) & 0xF, pl & 0x7F
    return (f"os_version={major}.{minor}.{patch}", f"os_patch_level={year}-{month}-{day}")

def boot(path):
    buf = open(path, "rb").read(1 << 22)
    if buf[:8] != b"ANDROID!":
        print("ไม่ใช่ boot image magic =", buf[:8]); sys.exit(1)
    ksize, rsize, osv, hsize = (u32(buf, 8), u32(buf, 12), u32(buf, 16), u32(buf, 20))
    print(f"header_version=3/4 kernel_size={ksize} ramdisk_size={rsize} header_size={hsize}")
    print(*parse_os(osv), sep="; ")
    cmd = buf[40:40+1536].rstrip(b"\x00").decode(errors="replace")
    print(f"cmdline_boot='{cmd}'")
    if hsize == 2112:  # v4
        off = hsize
        n_r = u32(buf, off); off += 4
        print(f"ramdisk_table entries={n_r}")
        for i in range(n_r):
            size, load, t, cid, cidb = struct.unpack_from("<QQIQQ", buf, off); off += 28
            print(f"  ramdisk[{i}] size=0x{size:x} load=0x{load:x} type={t}")
        n_d = u32(buf, off); off += 4
        print(f"dtb_table entries={n_d}")
        for i in range(n_d):
            size, load, eid, cid, cidb = struct.unpack_from("<QQIQQ", buf, off); off += 28
            print(f"  dtb[{i}] size=0x{size:x} load=0x{load:x} id=0x{eid:x}")

def vboot(path):
    buf = open(path, "rb").read(1 << 22)
    magic = buf[:16].rstrip(b"\x00")
    if not magic.startswith(b"VNDRBOOT"):
        print("ไม่ใช่ vendor_boot magic =", magic); sys.exit(1)
    hdr = u32(buf, 12)
    pd = u32(buf, 16)
    o1 = buf[20:20+1032].rstrip(b"\x00")
    vsu = buf[1052:1052+512].rstrip(b"\x00")
    print(f"magic={magic.decode(errors='replace')} header_version={hdr} page_size={pd}")
    print(f"cmdline_boot='{o1.decode(errors='replace')}'")
    print(f"vendor_string='{vsu.decode(errors='replace')}'")
    # header v4: tiRamdisk entries + vRTI + vDTB tables
    # v3 header size = 2112 + pagestrings? ใช้ offset หลัก: v3 vhdr layout:
    #   0-15 magic, 12 hdrVer, 16 pageSize, 20 cmdline1032, 1052 vstr512, gzip? ผู้เขียน line1008
    # v4 = v3 + 1568 bytes extra (ramdisk/dtb tables). อ่านราเม้นต์ที่ 2112:
    off = 2112
    n_ti = u32(buf, off); off += 4
    print(f"vendor_ramdisk_table entries={n_ti} (header v4 only)")
    total_size = 0
    for i in range(n_ti):
        size, load, ty, cid, cidb = struct.unpack_from("<QQIQQ", buf, off); off += 28
        print(f"  vramdisk[{i}] size=0x{size:x} load=0x{load:x} type={ty}")
        total_size += size
    print(f"  รวม ramdisk payload ~ {total_size} bytes")
    off += 4  # skip rti reserved
    n_dtb = u32(buf, off); off += 4
    print(f"dtb_table entries={n_dtb}")
    tot_d = 0
    for i in range(n_dtb):
        size, load, eid, cid, cidb = struct.unpack_from("<QQIQQ", buf, off); off += 28
        print(f"  dtb[{i}] size=0x{size:x} load=0x{load:x} id=0x{eid:x}")
        tot_d += size
    print(f"  รวม dtb ~ {tot_d} bytes")

if __name__ == "__main__":
    path = sys.argv[1]
    if b"VNDRBOOT" in open(path, "rb").read(16):
        vboot(path)
    else:
        boot(path)
