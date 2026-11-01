/*
 * sunnyfb2.c — DRM/KMS geometry probe for Xiaomi sunny (1080x2400 panel)
 *
 * Fixes v1: uses the real stride from dumb.pitch instead of width.
 * Draws 4 colour bands + border + 100px tick lines so we can see exactly
 * which part of the panel is actually scanned out.
 */
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;

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

static int xopen(const char *p, int flags) { return (int)sc6(SYS_openat, -100, (long)p, flags, 0, 0, 0); }
static int xioctl(int fd, unsigned long req, void *arg) { return (int)sc6(SYS_ioctl, fd, req, (long)arg, 0, 0, 0); }
static void *xmmap(void *a, u64 len, int prot, int flags, int fd, u64 off) { return (void *)sc6(SYS_mmap, (long)a, (long)len, prot, flags, fd, (long)off); }
static long xwrite(int fd, const char *s, u64 n) { return sc6(SYS_write, fd, (long)s, (long)n, 0, 0, 0); }
static void xexit(int c) { sc6(SYS_exit, c, 0, 0, 0, 0, 0); }

static void puts_(const char *s) { u64 n = 0; while (s[n]) n++; xwrite(1, s, n); }
static void putnum(long v) {
    char b[24]; int i = 23; b[i] = 0;
    if (v < 0) { puts_("-"); v = -v; }
    if (v == 0) b[--i] = '0';
    while (v > 0) { b[--i] = (char)('0' + (v % 10)); v /= 10; }
    puts_(&b[i]);
}

void *memcpy(void *d, const void *s, u64 n) { u8 *a = d; const u8 *b = s; while (n--) *a++ = *b++; return d; }
void *memset(void *d, int c, u64 n) { u8 *a = d; while (n--) *a++ = (u8)c; return d; }

#include <sys/ioctl.h>
#include <xf86drm.h>

#define CARD "/dev/dri/card0"

static u32 crtc_ids[8], conn_ids[8], enc_ids[8];
static struct drm_mode_modeinfo modes[64];

int main_entry(void) {
    int fd = xopen(CARD, 2);
    if (fd < 0) { puts_("sunnyfb2: cannot open card0\n"); return 1; }
    xioctl(fd, DRM_IOCTL_SET_MASTER, 0);

    struct drm_mode_card_res crd;
    memset(&crd, 0, sizeof(crd));
    crd.crtc_id_ptr = (u64)(unsigned long)crtc_ids;
    crd.connector_id_ptr = (u64)(unsigned long)conn_ids;
    crd.encoder_id_ptr = (u64)(unsigned long)enc_ids;
    crd.count_crtcs = 8; crd.count_connectors = 8; crd.count_encoders = 8;
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &crd) < 0) { puts_("sunnyfb2: GETRESOURCES failed\n"); return 2; }

    struct drm_mode_modeinfo chosen;
    memset(&chosen, 0, sizeof(chosen));
    int conn_id = 0, enc_id = 0, have = 0;
    for (unsigned i = 0; i < crd.count_connectors; i++) {
        struct drm_mode_get_connector c;
        memset(&c, 0, sizeof(c));
        c.connector_id = conn_ids[i];
        c.modes_ptr = (u64)(unsigned long)modes;
        c.count_modes = 64;
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0) continue;
        if (c.connector_type == 16 && c.connection == 1 && c.count_modes > 0 && !have) {
            conn_id = conn_ids[i]; enc_id = c.encoder_id;
            chosen = modes[0]; have = 1;
        }
    }
    if (!have) { puts_("sunnyfb2: no DSI connector\n"); return 3; }

    u32 crtc_id = 0;
    if (enc_id) {
        struct drm_mode_get_encoder e;
        memset(&e, 0, sizeof(e));
        e.encoder_id = enc_id;
        if (xioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0) {
            crtc_id = e.crtc_id;
            if (!crtc_id)
                for (unsigned i = 0; i < crd.count_crtcs; i++)
                    if (e.possible_crtcs & (1u << i)) { crtc_id = crtc_ids[i]; break; }
        }
    }
    if (!crtc_id) crtc_id = crtc_ids[0];

    struct drm_mode_create_dumb dumb;
    memset(&dumb, 0, sizeof(dumb));
    dumb.width = chosen.hdisplay;
    dumb.height = chosen.vdisplay;
    dumb.bpp = 32;
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) { puts_("sunnyfb2: CREATE_DUMB failed\n"); return 4; }

    struct drm_mode_map_dumb md;
    memset(&md, 0, sizeof(md));
    md.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md) < 0) { puts_("sunnyfb2: MAP_DUMB failed\n"); return 5; }
    u32 *fbm = xmmap(0, dumb.size, 3, 0x01, fd, md.offset);
    if ((long)fbm < 0 && (long)fbm > -4096) { puts_("sunnyfb2: mmap failed\n"); return 6; }

    u32 W = dumb.width, H = dumb.height;
    u32 stride_px = dumb.pitch / 4;   /* <-- the v1 bug */

    puts_("sunnyfb2: mode ");   putnum(W); puts_("x"); putnum(H);
    puts_(" pitch=");           putnum(dumb.pitch);
    puts_(" stride_px=");       putnum(stride_px);
    puts_(" bufsize=");         putnum(dumb.size); puts_("\n");

    /* 4 bands: red / green / blue / white  + white border + tick lines every 100 rows */
    for (u32 y = 0; y < H; y++) {
        u32 band = (y * 4) / H;                 /* 0..3 */
        u32 base = (band == 0) ? 0x00FF0000u :
                   (band == 1) ? 0x0000FF00u :
                   (band == 2) ? 0x000000FFu : 0x00FFFFFFu;
        u32 *row = fbm + (u64)y * stride_px;
        for (u32 x = 0; x < W; x++) row[x] = base;
        if ((y % 100) < 2) {                    /* tick lines: black */
            for (u32 x = 0; x < W; x++) row[x] = 0x00000000u;
        }
        if (y < 4 || y >= H - 4) {              /* border */
            for (u32 x = 0; x < W; x++) row[x] = 0x0000FFFFu;
        }
        row[0] = 0x0000FFFFu; row[1] = 0x0000FFFFu;
        row[W - 1] = 0x0000FFFFu; row[W - 2] = 0x0000FFFFu;
    }

    struct drm_mode_fb_cmd fbcmd;
    memset(&fbcmd, 0, sizeof(fbcmd));
    fbcmd.width = W; fbcmd.height = H; fbcmd.pitch = dumb.pitch;
    fbcmd.bpp = 32; fbcmd.depth = 24; fbcmd.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB, &fbcmd) < 0) { puts_("sunnyfb2: ADDFB failed\n"); return 7; }

    struct drm_mode_crtc set;
    memset(&set, 0, sizeof(set));
    set.crtc_id = crtc_id;
    set.fb_id = fbcmd.fb_id;
    set.mode_valid = 1;
    set.mode = chosen;
    u32 cid = conn_id;
    set.set_connectors_ptr = (u64)(unsigned long)&cid;
    set.count_connectors = 1;
    if (xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &set) < 0) { puts_("sunnyfb2: SETCRTC failed\n"); return 8; }
    puts_("sunnyfb2: on screen. red(top) green blue white(bottom)\n");

    /* stay alive so the image keeps scanning out */
    for (;;) {
        struct { long s, ns; } ts = {60, 0};
        sc6(SYS_nanosleep, (long)&ts, 0, 0, 0, 0, 0);
    }
    return 0;
}

void _start(void) { xexit(main_entry()); }
