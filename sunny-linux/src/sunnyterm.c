/*
 * sunnyterm.c — a tiny console on the Xiaomi sunny panel, no fbdev needed.
 *
 *  - drives the DSI panel directly through DRM/KMS (/dev/dri/card0)
 *  - allocates a PTY, runs /bin/sh on it
 *  - renders the VT grid with the kernel's 8x16 font (scaled 2x)
 *  - input comes from the USB serial console (/dev/ttyGS0), put in raw mode
 *  - Ctrl-] quits (termios is restored)
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
#define SYS_read 63
#define SYS_exit 93
#define SYS_clone 220
#define SYS_execve 221
#define SYS_dup3 24
#define SYS_setsid 157
#define SYS_poll 73
#define SYS_nanosleep 101

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_RDWR 2
#define O_NOCTTY 0x100
#define SIGCHLD 17

static int xopen(const char *p, int flags) { return (int)sc6(SYS_openat, AT_FDCWD, (long)p, flags, 0, 0, 0); }
static int xioctl(int fd, unsigned long req, void *arg) { return (int)sc6(SYS_ioctl, fd, req, (long)arg, 0, 0, 0); }
static void *xmmap(void *a, u64 len, int prot, int flags, int fd, u64 off) { return (void *)sc6(SYS_mmap, (long)a, (long)len, prot, flags, fd, (long)off); }
static long xread(int fd, void *b, u64 n) { return sc6(SYS_read, fd, (long)b, (long)n, 0, 0, 0); }
static long xwrite(int fd, const void *s, u64 n) { return sc6(SYS_write, fd, (long)s, (long)n, 0, 0, 0); }
static void xexit(int c) { sc6(SYS_exit, c, 0, 0, 0, 0, 0); }
static int xdup3(int a, int b) { return (int)sc6(SYS_dup3, a, b, 0, 0, 0, 0); }

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
static void *memmove_(void *d, const void *s, u64 n) { u8 *a = d; const u8 *b = s; if (a < b) { while (n--) *a++ = *b++; } else { a += n; b += n; while (n--) *--a = *--b; } return d; }

#include <sys/ioctl.h>
#include <xf86drm.h>
#include "sunnyfont.h"

#define CARD "/dev/dri/card0"
#define TTY_IN "/dev/ttyGS0"

/* ---- termios (aarch64 layout) ---- */
struct ktermios {
    u32 c_iflag, c_oflag, c_cflag, c_lflag;
    u8  c_line;
    u8  c_cc[19];
};
#define TCGETS 0x5401
#define TCSETS 0x5402
#define TIOCSPTLCK 0x40045431
#define TIOCGPTN   0x80045430
#define TIOCSCTTY  0x540E

/* ---- screen ---- */
#define S 2                 /* glyph scale */
#define CW (8 * S)
#define CH (16 * S)

static u32 crtc_ids[8], conn_ids[8], enc_ids[8];
static struct drm_mode_modeinfo modes[64];

static u32 *fb;
static u32 fbW, fbH, stride_px;
static int cols, rows;
static u8 *grid;
static int cx, cy, dirty = 1;

static void render(void) {
    /* clear */
    for (u32 y = 0; y < fbH; y++) {
        u32 *row = fb + (u64)y * stride_px;
        for (u32 x = 0; x < fbW; x++) row[x] = 0x00000000u;
    }
    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            u8 ch = grid[r * cols + c];
            if (!ch || ch == ' ') continue;
            const u8 *g = font8x16 + (u64)ch * 16;
            u32 *base = fb + (u64)(r * CH) * stride_px + (u64)(c * CW);
            for (int gy = 0; gy < 16; gy++) {
                u8 bits = g[gy];
                if (!bits) continue;
                for (int sy = 0; sy < S; sy++) {
                    u32 *row = base + (u64)(gy * S + sy) * stride_px;
                    for (int gx = 0; gx < 8; gx++) {
                        if (bits & (0x80 >> gx)) {
                            for (int sx = 0; sx < S; sx++)
                                row[gx * S + sx] = 0x00E0E0E0u;
                        }
                    }
                }
            }
        }
    }
    /* cursor: underline block */
    if (cy < rows && cx < cols) {
        u32 *base = fb + (u64)(cy * CH + 14 * S) * stride_px + (u64)(cx * CW);
        for (int sy = 0; sy < S; sy++) {
            u32 *row = base + (u64)sy * stride_px;
            for (int sx = 0; sx < CW; sx++) row[sx] = 0x00FFFFFFu;
        }
    }
    dirty = 0;
}

static void scroll_up(void) {
    memmove_(grid, grid + cols, (u64)(rows - 1) * cols);
    memset(grid + (u64)(rows - 1) * cols, 0, (u64)cols);
    if (cy > 0) cy = rows - 1;
}

static void put_char(u8 ch) {
    if (ch == '\n') { cx = 0; cy++; }
    else if (ch == '\r') { cx = 0; }
    else if (ch == '\b') { if (cx > 0) cx--; }
    else if (ch == '\t') { cx = (cx + 8) & ~7; }
    else if (ch >= 32 && ch < 127) {
        grid[cy * cols + cx] = ch;
        cx++;
        if (cx >= cols) { cx = 0; cy++; }
    } else {
        return;
    }
    while (cy >= rows) scroll_up();
    dirty = 1;
}

static void feed(const u8 *buf, int n) {
    static int esc = 0;
    for (int i = 0; i < n; i++) {
        u8 c = buf[i];
        if (esc == 1) {           /* just saw ESC */
            if (c == '[' || c == ']' || c == '(' || c == ')') { esc = 2; continue; }
            esc = 0;
            continue;
        }
        if (esc == 2) {           /* inside CSI */
            if (c >= 0x40 && c <= 0x7e) esc = 0;
            continue;
        }
        if (c == 0x1b) { esc = 1; continue; }
        if (c == 7) continue;     /* bell */
        put_char(c);
    }
}

int main_entry(void) {
    /* ---------- DRM ---------- */
    int fd = xopen(CARD, O_RDWR);
    if (fd < 0) { puts_("sunnyterm: no card0\n"); return 1; }
    xioctl(fd, DRM_IOCTL_SET_MASTER, 0);

    struct drm_mode_card_res crd;
    memset(&crd, 0, sizeof(crd));
    crd.crtc_id_ptr = (u64)(unsigned long)crtc_ids;
    crd.connector_id_ptr = (u64)(unsigned long)conn_ids;
    crd.encoder_id_ptr = (u64)(unsigned long)enc_ids;
    crd.count_crtcs = 8; crd.count_connectors = 8; crd.count_encoders = 8;
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &crd) < 0) { puts_("sunnyterm: GETRESOURCES\n"); return 2; }

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
            conn_id = conn_ids[i]; enc_id = c.encoder_id; chosen = modes[0]; have = 1;
        }
    }
    if (!have) { puts_("sunnyterm: no DSI\n"); return 3; }

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
    dumb.width = chosen.hdisplay; dumb.height = chosen.vdisplay; dumb.bpp = 32;
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) { puts_("sunnyterm: dumb\n"); return 4; }
    struct drm_mode_map_dumb md;
    memset(&md, 0, sizeof(md));
    md.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md) < 0) { puts_("sunnyterm: map\n"); return 5; }
    fb = xmmap(0, dumb.size, 3, 0x01, fd, md.offset);
    if ((long)fb < 0 && (long)fb > -4096) { puts_("sunnyterm: mmap\n"); return 6; }
    fbW = dumb.width; fbH = dumb.height; stride_px = dumb.pitch / 4;

    struct drm_mode_fb_cmd fbcmd;
    memset(&fbcmd, 0, sizeof(fbcmd));
    fbcmd.width = fbW; fbcmd.height = fbH; fbcmd.pitch = dumb.pitch;
    fbcmd.bpp = 32; fbcmd.depth = 24; fbcmd.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB, &fbcmd) < 0) { puts_("sunnyterm: addfb\n"); return 7; }

    struct drm_mode_crtc set;
    memset(&set, 0, sizeof(set));
    set.crtc_id = crtc_id; set.fb_id = fbcmd.fb_id; set.mode_valid = 1; set.mode = chosen;
    u32 cid = conn_id;
    set.set_connectors_ptr = (u64)(unsigned long)&cid;
    set.count_connectors = 1;
    int rc = xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &set);
    if (rc < 0) {
        puts_("sunnyterm: setcrtc rc="); putnum(rc); puts_(" -> disable+retry\n");
        struct drm_mode_crtc off;
        memset(&off, 0, sizeof(off));
        off.crtc_id = crtc_id;
        xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &off);
        for (int t = 0; t < 4 && rc < 0; t++) {
            struct { long s, ns; } ts = {0, 250000000};
            sc6(SYS_nanosleep, (long)&ts, 0, 0, 0, 0, 0);
            rc = xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &set);
        }
        if (rc < 0) { puts_("sunnyterm: setcrtc still failing rc="); putnum(rc); puts_("\n"); return 8; }
    }

    cols = fbW / CW; rows = fbH / CH;
    grid = (u8 *)xmmap(0, (u64)cols * rows, 3, 0x22 /*MAP_PRIVATE|ANON*/, -1, 0);
    if ((long)grid < 0 && (long)grid > -4096) { puts_("sunnyterm: grid mmap\n"); return 9; }
    memset(grid, 0, (u64)cols * rows);

    puts_("sunnyterm: panel "); putnum(fbW); puts_("x"); putnum(fbH);
    puts_(" text "); putnum(cols); puts_("x"); putnum(rows); puts_(" (Ctrl-] to quit)\n");

    /* ---------- PTY + shell ---------- */
    int mfd = xopen("/dev/ptmx", O_RDWR | O_NOCTTY);
    if (mfd < 0) { puts_("sunnyterm: /dev/ptmx\n"); return 10; }
    int unlock = 0;
    xioctl(mfd, TIOCSPTLCK, &unlock);
    u32 ptn = 0;
    xioctl(mfd, TIOCGPTN, &ptn);
    char spath[32];
    memcpy(spath, "/dev/pts/", 10);
    { char t[12]; int i = 0, v = (int)ptn;
      if (!v) t[i++] = '0';
      while (v > 0) { t[i++] = (char)('0' + v % 10); v /= 10; }
      int k = 9;
      while (i > 0) spath[k++] = t[--i];
      spath[k] = 0; }
    puts_("sunnyterm: pty "); puts_(spath); puts_("\n");

    int sfd = xopen(spath, O_RDWR | O_NOCTTY);
    if (sfd < 0) { puts_("sunnyterm: open pty slave\n"); return 11; }

    long pid = sc6(SYS_clone, SIGCHLD, 0, 0, 0, 0, 0);
    if (pid == 0) {
        sc6(SYS_setsid, 0, 0, 0, 0, 0, 0);
        xioctl(sfd, TIOCSCTTY, 0);
        xdup3(sfd, 0); xdup3(sfd, 1); xdup3(sfd, 2);
        char *argv[] = {"sh", 0};
        char *envp[] = {"PATH=/sbin:/bin:/usr/sbin:/usr/bin", "HOME=/root",
                        "TERM=linux", "PS1=sunny:~# ", 0};
        sc6(SYS_execve, (long)"/bin/sh", (long)argv, (long)envp, 0, 0, 0);
        xexit(127);
    }
    if (pid < 0) { puts_("sunnyterm: fork failed\n"); return 12; }

    /* ---------- input tty in raw mode ---------- */
    int tty = xopen(TTY_IN, O_RDWR | O_NOCTTY);
    struct ktermios saved, rawm;
    int have_saved = 0;
    if (tty >= 0 && xioctl(tty, TCGETS, &saved) == 0) {
        have_saved = 1;
        rawm = saved;
        rawm.c_iflag = 0; rawm.c_oflag = 0; rawm.c_lflag = 0;
        rawm.c_cc[6] = 1;   /* VMIN */
        rawm.c_cc[5] = 0;   /* VTIME */
        xioctl(tty, TCSETS, &rawm);
    } else {
        tty = -1;
        puts_("sunnyterm: no input tty, screen is read-only\n");
    }

    render();

    u8 buf[512];
    for (;;) {
        struct { long events; short revents; } dummy;
        /* poll master (always) and tty (if any) */
        struct { int fd; short events; short revents; } pfd[2];
        pfd[0].fd = mfd; pfd[0].events = 1; pfd[0].revents = 0;
        int np = 1;
        if (tty >= 0) { pfd[1].fd = tty; pfd[1].events = 1; pfd[1].revents = 0; np = 2; }
        (void)dummy;
        sc6(SYS_poll, (long)pfd, np, 1000, 0, 0, 0);

        long n = xread(mfd, buf, sizeof(buf));
        if (n > 0) { feed(buf, (int)n); if (dirty) render(); }

        if (tty >= 0 && pfd[1].revents & 1) {
            long k = xread(tty, buf, sizeof(buf));
            for (long i = 0; i < k; i++) {
                if (buf[i] == 0x1d) {          /* Ctrl-] */
                    if (have_saved) xioctl(tty, TCSETS, &saved);
                    puts_("\nsunnyterm: quit\n");
                    xexit(0);
                }
                xwrite(mfd, &buf[i], 1);
            }
        }
    }
    return 0;
}

void _start(void) { xexit(main_entry()); }
