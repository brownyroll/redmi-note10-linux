/*
 * sunnyfb.c — minimal DRM/KMS test for Xiaomi Redmi Note 10 (sunny, SM6150)
 *
 * Standalone, no libc, no libdrm linkage: raw aarch64 syscalls + libdrm headers.
 * Opens /dev/dri/card0, finds the DSI connector, allocates a dumb buffer,
 * paints a test pattern and sets the CRTC. If the panel lights up, KMS works.
 *
 * Build:
 *   aarch64-linux-gnu-gcc -Os -static -nostdlib -ffreestanding \
 *     -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables \
 *     -I/usr/include/libdrm -Wl,--build-id=none -o sunnyfb sunnyfb.c
 */
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;
typedef long i64;

/* ---------- raw syscalls (aarch64 generic) ---------- */
static long sc6(long n, long a1, long a2, long a3, long a4, long a5, long a6) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    register long x2 __asm__("x2") = a3;
    register long x3 __asm__("x3") = a4;
    register long x4 __asm__("x4") = a5;
    register long x5 __asm__("x5") = a6;
    __asm__ volatile("svc #0"
                     : "+r"(x0)
                     : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5)
                     : "memory");
    return x0;
}

#define SYS_openat 56
#define SYS_close 57
#define SYS_ioctl 29
#define SYS_mmap 222
#define SYS_write 64
#define SYS_exit 93
#define SYS_nanosleep 101

static int xopen(const char *p, int flags) {
    return (int)sc6(SYS_openat, -100 /*AT_FDCWD*/, (long)p, flags, 0, 0, 0);
}
static int xioctl(int fd, unsigned long req, void *arg) {
    return (int)sc6(SYS_ioctl, fd, req, (long)arg, 0, 0, 0);
}
static void *xmmap(void *addr, u64 len, int prot, int flags, int fd, u64 off) {
    return (void *)sc6(SYS_mmap, (long)addr, (long)len, prot, flags, fd, (long)off);
}
static long xwrite(int fd, const char *s, u64 n) {
    return sc6(SYS_write, fd, (long)s, (long)n, 0, 0, 0);
}
static void xexit(int c) { sc6(SYS_exit, c, 0, 0, 0, 0, 0); }

static void puts_(const char *s) {
    u64 n = 0;
    while (s[n]) n++;
    xwrite(1, s, n);
}
static void putnum(long v) {
    char b[24];
    int i = 23;
    b[i] = 0;
    if (v < 0) { puts_("-"); v = -v; }
    if (v == 0) b[--i] = '0';
    while (v > 0) { b[--i] = (char)('0' + (v % 10)); v /= 10; }
    puts_(&b[i]);
}

/* memcpy/memset in case the compiler emits calls */
void *memcpy(void *d, const void *s, u64 n) {
    u8 *dd = d; const u8 *ss = s;
    while (n--) *dd++ = *ss++;
    return d;
}
void *memset(void *d, int c, u64 n) {
    u8 *dd = d;
    while (n--) *dd++ = (u8)c;
    return d;
}

/* ---------- DRM structures (from libdrm headers) ---------- */
#include <sys/ioctl.h>
#include <xf86drm.h>


#define CARD "/dev/dri/card0"

static u32 crtc_ids[8], conn_ids[8], enc_ids[8];
static struct drm_mode_modeinfo modes[64];

static void paint(u32 *fb, int w, int h, int frame) {
    /* color bars + moving marker, so we can tell if it updates */
    const u32 bars[8] = {
        0x00FFFFFF, 0x00FFFF00, 0x0000FFFF, 0x0000FF00,
        0x00FF00FF, 0x00FF0000, 0x000000FF, 0x00000000};
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int band = (x * 8) / w;
            u32 c = bars[band];
            /* darken towards the bottom so orientation is obvious */
            if (y > h - h / 8) c = 0x00202020;
            fb[(u64)y * (u64)w + (u64)x] = c;
        }
    }
    /* white square that moves: proves the buffer is really ours */
    int sz = w / 10;
    int ox = (frame * (w / 8)) % (w - sz);
    int oy = h / 2 - sz / 2;
    for (int y = oy; y < oy + sz && y < h; y++)
        for (int x = ox; x < ox + sz && x < w; x++)
            fb[(u64)y * (u64)w + (u64)x] = 0x00FFFFFF;
}

void _start(void) {
    puts_("sunnyfb: open " CARD "\n");
    int fd = xopen(CARD, 2 /*O_RDWR*/);
    if (fd < 0) { puts_("sunnyfb: cannot open card0\n"); xexit(1); }

    /* become DRM master (only client on the device) */
    long r = xioctl(fd, DRM_IOCTL_SET_MASTER, 0);
    puts_("sunnyfb: SET_MASTER "); putnum(r); puts_("\n");

    struct drm_mode_card_res crd;
    memset(&crd, 0, sizeof(crd));
    crd.crtc_id_ptr = (u64)(unsigned long)crtc_ids;
    crd.connector_id_ptr = (u64)(unsigned long)conn_ids;
    crd.encoder_id_ptr = (u64)(unsigned long)enc_ids;
    crd.count_crtcs = 8;
    crd.count_connectors = 8;
    crd.count_encoders = 8;
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &crd) < 0) {
        puts_("sunnyfb: GETRESOURCES failed\n");
        xexit(2);
    }
    puts_("sunnyfb: crtcs="); putnum(crd.count_crtcs);
    puts_(" connectors="); putnum(crd.count_connectors);
    puts_(" encoders="); putnum(crd.count_encoders); puts_("\n");

    int conn_fd = -1, conn_id = 0, enc_id = 0;
    struct drm_mode_modeinfo *mode = 0;
    for (unsigned i = 0; i < crd.count_connectors; i++) {
        struct drm_mode_get_connector c;
        memset(&c, 0, sizeof(c));
        c.connector_id = conn_ids[i];
        c.modes_ptr = (u64)(unsigned long)modes;
        c.count_modes = 64;
        c.props_ptr = 0;
        c.count_props = 0;
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0) continue;
        puts_("sunnyfb: conn "); putnum((long)conn_ids[i]);
        puts_(" type="); putnum(c.connector_type);
        puts_(" status="); putnum(c.connection);
        puts_(" modes="); putnum(c.count_modes);
        puts_(" enc="); putnum(c.encoder_id);
        puts_("\n");
        if (c.connector_type == DRM_MODE_CONNECTOR_DSI &&
            c.connection == 1 /*connected*/ && c.count_modes > 0 && !mode) {
            conn_fd = 0;
            conn_id = conn_ids[i];
            enc_id = c.encoder_id;
            mode = &modes[0];
            /* keep a copy: modes[] is shared by the next iteration */
            static struct drm_mode_modeinfo chosen;
            chosen = modes[0];
            mode = &chosen;
        }
    }
    if (!mode) { puts_("sunnyfb: no DSI connector with modes\n"); xexit(3); }
    puts_("sunnyfb: mode "); putnum(mode->hdisplay); puts_("x");
    putnum(mode->vdisplay); puts_(" clock="); putnum((long)mode->clock);
    puts_(" type="); putnum(mode->type); puts_("\n");

    u32 crtc_id = 0;
    if (enc_id) {
        struct drm_mode_get_encoder e;
        memset(&e, 0, sizeof(e));
        e.encoder_id = enc_id;
        if (xioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0) {
            crtc_id = e.crtc_id;
            puts_("sunnyfb: encoder "); putnum((long)enc_id);
            puts_(" crtc="); putnum((long)crtc_id);
            puts_(" possible="); putnum((long)e.possible_crtcs); puts_("\n");
            if (!crtc_id) {
                for (unsigned i = 0; i < crd.count_crtcs; i++)
                    if (e.possible_crtcs & (1u << i)) { crtc_id = crtc_ids[i]; break; }
            }
        }
    }
    if (!crtc_id) { crtc_id = crtc_ids[0]; }
    puts_("sunnyfb: using crtc "); putnum((long)crtc_id); puts_("\n");

    /* dumb buffer */
    struct drm_mode_create_dumb dumb;
    memset(&dumb, 0, sizeof(dumb));
    dumb.width = mode->hdisplay;
    dumb.height = mode->vdisplay;
    dumb.bpp = 32;
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) {
        puts_("sunnyfb: CREATE_DUMB failed\n"); xexit(4);
    }
    puts_("sunnyfb: dumb handle="); putnum((long)dumb.handle);
    puts_(" pitch="); putnum((long)dumb.pitch);
    puts_(" size="); putnum((long)dumb.size); puts_("\n");

    struct drm_mode_map_dumb md;
    memset(&md, 0, sizeof(md));
    md.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md) < 0) {
        puts_("sunnyfb: MAP_DUMB failed\n"); xexit(5);
    }
    u32 *fbm = xmmap(0, dumb.size, 3 /*RW*/, 0x01 /*MAP_SHARED*/, fd, md.offset);
    if ((long)fbm < 0 && (long)fbm > -4096) {
        puts_("sunnyfb: mmap failed "); putnum((long)fbm); puts_("\n"); xexit(6);
    }
    puts_("sunnyfb: mmap ok\n");

    paint(fbm, dumb.width, dumb.height, 0);

    u32 fb_id = 0;
    struct drm_mode_fb_cmd fbcmd;
    memset(&fbcmd, 0, sizeof(fbcmd));
    fbcmd.width = dumb.width;
    fbcmd.height = dumb.height;
    fbcmd.pitch = dumb.pitch;
    fbcmd.bpp = 32;
    fbcmd.depth = 24;
    fbcmd.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB, &fbcmd) < 0) {
        puts_("sunnyfb: ADDFB failed\n"); xexit(7);
    }
    fb_id = fbcmd.fb_id;
    puts_("sunnyfb: fb_id="); putnum((long)fb_id); puts_("\n");

    struct drm_mode_crtc set;
    memset(&set, 0, sizeof(set));
    set.crtc_id = crtc_id;
    set.fb_id = fb_id;
    set.x = 0;
    set.y = 0;
    set.mode_valid = 1;
    set.mode = *mode;
    u32 cid = conn_id;
    set.set_connectors_ptr = (u64)(unsigned long)&cid;
    set.count_connectors = 1;
    if (xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &set) < 0) {
        puts_("sunnyfb: SETCRTC failed\n"); xexit(8);
    }
    puts_("sunnyfb: SETCRTC ok -- panel should be lit now\n");

    /* animate a bit so it is obvious the buffer is live */
    for (int i = 0; i < 600; i++) {
        paint(fbm, dumb.width, dumb.height, i);
        struct timespec_ { long s; long ns; } ts = {0, 120000000};
        sc6(SYS_nanosleep, (long)&ts, 0, 0, 0, 0, 0);
    }
    puts_("sunnyfb: done\n");
    xexit(0);
}
