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
#define SYS_ppoll 73
#define SYS_nanosleep 101
#define SYS_statfs 43
#define SYS_clock_gettime 113

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
#include <linux/input.h>
#include <sys/vfs.h>
#include "sunnyfont.h"

#define CARD "/dev/dri/card0"
#ifndef TTY_IN
#define TTY_IN "/dev/ttyGS0"
#endif

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
#define LEFT_MARGIN 64
#define RIGHT_MARGIN 32
#define STATUS_TOP 224
#define TOP_MARGIN 432
#define BOTTOM_MARGIN 64

static u32 crtc_ids[8], conn_ids[8], enc_ids[8];
static struct drm_mode_modeinfo modes[64];

static u32 *fb;
static u32 fbW, fbH, stride_px;
static int cols, rows;
static u8 *grid;
static u32 *grid_fg;
static u32 current_fg = 0x00E0E0E0u;
static int cx, cy, dirty = 1;
static int display_fd = -1;
static struct drm_mode_crtc display_crtc;
static u32 display_connector;
static void feed(const u8 *buf, int n);
static int screen_dark;
static int charge_only;
static int power_pressed, power_long_triggered;
static long power_pressed_at;
static int vol_up_pressed, vol_down_pressed, vol_long_triggered;
static long vol_up_at, vol_down_at;
static int heal_menu, heal_selected;
static int system_dashboard;
static char saved_brightness[32] = "513";
static int saved_brightness_len = 3;
static u64 cpu_total_old, cpu_idle_old;
static int cpu_percent;
static int animation_phase;

#define COL_TEXT   0x00E0E0E0u
#define COL_CYAN   0x0080D8FFu
#define COL_GREEN  0x004CD964u
#define COL_YELLOW 0x00FFD84Au
#define COL_ORANGE 0x00FF8C00u
#define COL_RED    0x00FF4040u
#define COL_DIM    0x00708090u

static u32 level_color(int percent) {
    if (percent >= 90) return COL_RED;
    if (percent >= 75) return COL_ORANGE;
    if (percent >= 60) return COL_YELLOW;
    return COL_GREEN;
}
static u32 battery_color(int percent) {
    if (percent < 20) return COL_RED;
    if (percent < 40) return COL_ORANGE;
    if (percent < 80) return COL_YELLOW;
    return COL_GREEN;
}

static int read_text(const char *path, char *buf, int cap) {
    int fd = xopen(path, O_RDONLY);
    if (fd < 0) return 0;
    long n = xread(fd, buf, cap - 1);
    sc6(SYS_close, fd, 0, 0, 0, 0, 0);
    if (n < 0) n = 0;
    buf[n] = 0;
    return (int)n;
}
static u64 parse_num(const char **p) {
    u64 n = 0;
    while (**p == ' ' || **p == '\t') (*p)++;
    while (**p >= '0' && **p <= '9') { n = n * 10 + (u64)(**p - '0'); (*p)++; }
    return n;
}
static u64 mem_field(const char *s, const char *key) {
    const char *start = s;
    for (; *s; s++) {
        if (s != start && s[-1] != '\n') continue;
        const char *a = s, *b = key;
        while (*b && *a == *b) { a++; b++; }
        if (!*b) return parse_num(&a);
    }
    return 0;
}
static void append_text(char *out, int *pos, const char *s) {
    while (*s && *pos < 120) out[(*pos)++] = *s++;
}
static void append_num(char *out, int *pos, u64 n) {
    char tmp[24]; int used = 0;
    do { tmp[used++] = (char)('0' + n % 10); n /= 10; } while (n && used < 24);
    while (used && *pos < 120) out[(*pos)++] = tmp[--used];
}
static void draw_status_line(const char *line, int pos, int y, int start_col, u32 color) {
    y += STATUS_TOP;
    for (int c = 0; c < pos && LEFT_MARGIN + (u32)((start_col + c + 1) * CW) <= fbW - LEFT_MARGIN; c++) {
        const u8 *g = font8x16 + (u64)(u8)line[c] * 16;
        u32 *base = fb + (u64)y * stride_px + LEFT_MARGIN + (u64)(start_col + c) * CW;
        for (int gy = 0; gy < 16; gy++) for (int sy = 0; sy < S; sy++) {
            u32 *row = base + (u64)(gy * S + sy) * stride_px;
            for (int gx = 0; gx < 8; gx++) if (g[gy] & (0x80 >> gx))
                for (int sx = 0; sx < S; sx++) row[gx * S + sx] = color;
        }
    }
}
static void append_bar(char *line, int *pos, int percent, int width) {
    int filled = (percent * width + 99) / 100;
    append_text(line, pos, "[");
    for (int i = 0; i < width && *pos < 120; i++) line[(*pos)++] = i < filled ? '#' : '-';
    append_text(line, pos, "] "); append_num(line, pos, (u64)percent); append_text(line, pos, "%");
}
static int first_number(const char *path) {
    char b[64]; if (!read_text(path, b, sizeof(b))) return -1;
    const char *p = b; return (int)parse_num(&p);
}
/* Read the fuel gauge directly on every refresh.  The Qualcomm BMS exposes
 * real_capacity as the authoritative, unsmoothed SOC; fall back only when
 * that node is unavailable.  Do not cache this value in the UI. */
static int battery_percent(void) {
    int n = first_number("/sys/class/power_supply/bms/real_capacity");
    if (n < 0) n = first_number("/sys/class/power_supply/bms/capacity");
    if (n < 0) n = first_number("/sys/class/power_supply/battery/capacity");
    if (n > 100) n = 100;
    return n;
}
static void draw_status(void) {
    char buf[2048], line[128]; int pos = 0;
    int bat = battery_percent();
    int ram_percent = 0, disk_percent = 0;
    /* A compact Tux holds the orange B; the resource dashboard sits beside it. */
    draw_status_line("  .--.", 6, 16, 0, COL_TEXT);
    draw_status_line(" (o_o)===[ ]", 12, 48, 0, COL_TEXT);
    draw_status_line("B", 1, 48, 10, COL_ORANGE);
    draw_status_line(" /|_|\\", 6, 80, 0, COL_TEXT);
    draw_status_line(" /   \\", 6, 112, 0, COL_TEXT);
    draw_status_line("Brownyrollz-PhoneSunny", 23, 16, 14, COL_CYAN);
    append_text(line, &pos, "BAT  ");
    if (bat >= 0) { append_bar(line, &pos, bat, 10); }
    else append_text(line, &pos, "unavailable");
    char power[48]; if (read_text("/sys/class/power_supply/battery/status", power, sizeof(power))) {
        append_text(line, &pos, " "); for (int i=0; power[i] && power[i]!='\n' && pos<120; i++) line[pos++]=power[i];
    }
    draw_status_line(line, pos, 48, 14, bat >= 0 ? battery_color(bat) : COL_DIM);
    pos = 0; append_text(line, &pos, "CPU  ");
    if (read_text("/proc/stat", buf, sizeof(buf)) && buf[0] == 'c' && buf[1] == 'p' && buf[2] == 'u') {
        const char *p = buf + 3; u64 v[8];
        for (int i = 0; i < 8; i++) v[i] = parse_num(&p);
        u64 total = 0; for (int i = 0; i < 8; i++) total += v[i];
        u64 idle = v[3] + v[4];
        if (cpu_total_old && total > cpu_total_old && idle >= cpu_idle_old) {
            u64 dt = total - cpu_total_old, di = idle - cpu_idle_old;
            cpu_percent = di <= dt ? (int)((dt - di) * 100 / dt) : 0;
        }
        cpu_total_old = total; cpu_idle_old = idle;
        append_bar(line, &pos, cpu_percent, 10);
    } else append_text(line, &pos, "unavailable");
    int temp = first_number("/sys/class/thermal/thermal_zone0/temp");
    if (temp >= 0) { append_text(line, &pos, "  "); append_num(line, &pos, temp > 1000 ? (u64)temp/1000 : (u64)temp); append_text(line, &pos, "C"); }
    draw_status_line(line, pos, 80, 14, level_color(cpu_percent));
    pos = 0; append_text(line, &pos, "RAM  ");
    if (read_text("/proc/meminfo", buf, sizeof(buf))) {
        u64 total = mem_field(buf, "MemTotal:"), avail = mem_field(buf, "MemAvailable:");
        if (total && avail <= total) {
            ram_percent = (int)((total - avail) * 100 / total);
            append_bar(line, &pos, ram_percent, 10); append_text(line, &pos, " ");
            append_num(line, &pos, (total - avail) / 1024); append_text(line, &pos, "/");
            append_num(line, &pos, total / 1024); append_text(line, &pos, "MB");
        } else append_text(line, &pos, "unavailable");
    } else append_text(line, &pos, "unavailable");
    draw_status_line(line, pos, 112, 14, level_color(ram_percent));
    pos = 0; append_text(line, &pos, "DISK ");
    struct statfs fs;
    if (sc6(SYS_statfs, (long)"/", (long)&fs, 0, 0, 0, 0) == 0 && fs.f_blocks && fs.f_bfree <= fs.f_blocks) {
        u64 used = fs.f_blocks - fs.f_bfree;
        disk_percent = (int)(used * 100 / fs.f_blocks);
        append_bar(line, &pos, disk_percent, 10); append_text(line, &pos, " ");
        append_num(line, &pos, used * (u64)fs.f_bsize / 1073741824u); append_text(line, &pos, "/");
        append_num(line, &pos, (u64)fs.f_blocks * (u64)fs.f_bsize / 1073741824u); append_text(line, &pos, "GB");
    } else append_text(line, &pos, "unavailable");
    draw_status_line(line, pos, 144, 14, level_color(disk_percent));
    pos = 0; append_text(line, &pos, "NET  ");
    if (read_text("/run/sunny-lan/status", buf, sizeof(buf))) {
        const char *p = buf; if (p[0]=='S'&&p[1]=='T'&&p[2]=='A'&&p[3]=='T'&&p[4]=='E'&&p[5]=='=') p += 6;
        while (*p && *p!='\n' && pos<85) line[pos++]=*p++;
        const char *q=buf; while (*q) { if (q[0]=='I'&&q[1]=='P'&&q[2]=='=') { q+=3; append_text(line,&pos,"  IP "); while(*q&&*q!='\n'&&pos<110) line[pos++]=*q++; break; } q++; }
    } else append_text(line, &pos, charge_only ? "charging-only" : "waiting for OTG Ethernet");
    draw_status_line(line, pos, 176, 14, COL_CYAN);
}

static void show_file(const char *label, const char *path, int limit) {
    char buf[4096];
    int fd = xopen(path, O_RDONLY);
    int label_len = 0; while (label[label_len]) label_len++;
    feed((const u8 *)label, label_len);
    if (fd < 0) { feed((const u8 *)"unavailable\r\n", 13); return; }
    if (limit > (int)sizeof(buf)) limit = sizeof(buf);
    long n = xread(fd, buf, (u64)limit);
    sc6(SYS_close, fd, 0, 0, 0, 0, 0);
    if (n > 0) feed((const u8 *)buf, (int)n);
    feed((const u8 *)"\r\n", 2);
}
static void show_health(void) {
    system_dashboard = 1;
    dirty = 1;
}
static void toggle_screen(void) {
    const char *path = "/sys/class/backlight/panel0-backlight/brightness";
    if (!screen_dark) {
        int rfd = xopen(path, O_RDONLY);
        if (rfd >= 0) {
            long n = xread(rfd, saved_brightness, sizeof(saved_brightness));
            if (n > 0) saved_brightness_len = (int)n;
            sc6(SYS_close, rfd, 0, 0, 0, 0, 0);
        }
    }
    int fd = xopen(path, 1 /* O_WRONLY */);
    if (fd < 0) return;
    long n = screen_dark ? xwrite(fd, saved_brightness, saved_brightness_len) : xwrite(fd, "0", 1);
    sc6(SYS_close, fd, 0, 0, 0, 0, 0);
    if (n > 0) screen_dark = !screen_dark;
}
static long monotonic_seconds(void) {
    struct { long sec, nsec; } t = {0, 0};
    return sc6(SYS_clock_gettime, 1 /* CLOCK_MONOTONIC */, (long)&t, 0, 0, 0, 0) == 0 ? t.sec : 0;
}
static void check_power_hold(void) {
    long now = monotonic_seconds();
    if (!power_pressed || power_long_triggered || !now || now - power_pressed_at < 3) return;
    power_long_triggered = 1;
    static const u8 msg_off[] = "\r\nPower held: shutting down...\r\n";
    static const u8 msg_on[] = "\r\nPower held: starting Linux...\r\n";
    if (charge_only) feed(msg_on, sizeof(msg_on) - 1);
    else feed(msg_off, sizeof(msg_off) - 1);
    long pid = sc6(SYS_clone, SIGCHLD, 0, 0, 0, 0, 0);
    if (pid == 0) {
        char *argv[] = {charge_only ? "reboot" : "shutdown", "now", 0};
        char *envp[] = {"PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin", 0};
        const char *path = charge_only ? "/usr/local/sbin/reboot" : "/usr/local/sbin/shutdown";
        sc6(SYS_execve, (long)path, (long)argv, (long)envp, 0, 0, 0);
        xexit(127);
    }
}

static void show_heal_menu(void) {
    static const char *items[] = {
        "SYSTEM FASTFETCH", "HEAL OTG / DHCP", "RESCAN USB / INPUT",
        "BATTERY / CHARGER CHECK", "THERMAL CHECK", "STORAGE / FS CHECK",
        "PROCESS / LOAD CHECK", "SAVE DIAGNOSTIC REPORT",
        "SYNC FILESYSTEM", "EXIT MENU"
    };
    static const char *numbers[]={"01","02","03","04","05","06","07","08","09","10"};
    system_dashboard=0;
    static const u8 clear[] = "\033[2J\033[H";
    feed(clear, sizeof(clear)-1);
    static const u8 title[] =
        "+--------------------------------------------------+\r\n"
        "|             STATUS / HEAL SYSTEM               |\r\n"
        "+--------------------------------------------------+\r\n\r\n";
    feed(title, sizeof(title)-1);
    for (int i=0; i<10; i++) {
        feed((const u8 *)(i==heal_selected ? "  > [" : "    ["), 5);
        feed((const u8 *)numbers[i],2); feed((const u8 *)"] ",2);
        int n=0; while(items[i][n]) n++; feed((const u8 *)items[i],n); feed((const u8 *)"\r\n",2);
    }
    static const u8 help[] =
        "\r\nShort Vol+ / Vol- : move selection\r\n"
        "Hold Vol+          : run selected option\r\n"
        "Hold Vol-          : exit menu\r\n";
    feed(help,sizeof(help)-1); dirty=1;
}
static void run_heal_selection(int mfd) {
    static const char *commands[] = {
        "\n/usr/local/sbin/sunny-heal network\n",
        "\n/usr/local/sbin/sunny-heal usb\n",
        "\n/usr/local/sbin/sunny-heal battery\n",
        "\n/usr/local/sbin/sunny-heal thermal\n",
        "\n/usr/local/sbin/sunny-heal storage\n",
        "\n/usr/local/sbin/sunny-heal process\n",
        "\n/usr/local/sbin/sunny-heal report\n",
        "\n/usr/local/sbin/sunny-heal sync\n"
    };
    if (heal_selected==0) { heal_menu=0; show_health(); return; }
    if (heal_selected >= 9) { heal_menu=0; xwrite(mfd,"\nclear\n",7); return; }
    const char *s=commands[heal_selected-1]; u64 n=0; while(s[n])n++;
    heal_menu=0; xwrite(mfd,s,n);
}
static void check_volume_hold(int mfd) {
    long now=monotonic_seconds(); if(!now || vol_long_triggered) return;
    if (vol_up_pressed && now-vol_up_at>=2) {
        vol_long_triggered=1;
        if (heal_menu) run_heal_selection(mfd);
        else { heal_menu=1; heal_selected=0; show_heal_menu(); }
    } else if (vol_down_pressed && now-vol_down_at>=2) {
        vol_long_triggered=1;
        if (heal_menu) { heal_menu=0; xwrite(mfd,"\nclear\n",7); }
        else { heal_menu=1; heal_selected=0; show_heal_menu(); }
    }
}

/* USB keyboards expose evdev nodes; discover them again after hotplug. */
#define KBD_MAX 16
static int keyboard[KBD_MAX], shift_down, ctrl_down;
static const char keys_plain[128] = {
    [KEY_1]='1',[KEY_2]='2',[KEY_3]='3',[KEY_4]='4',[KEY_5]='5',
    [KEY_6]='6',[KEY_7]='7',[KEY_8]='8',[KEY_9]='9',[KEY_0]='0',
    [KEY_Q]='q',[KEY_W]='w',[KEY_E]='e',[KEY_R]='r',[KEY_T]='t',
    [KEY_Y]='y',[KEY_U]='u',[KEY_I]='i',[KEY_O]='o',[KEY_P]='p',
    [KEY_A]='a',[KEY_S]='s',[KEY_D]='d',[KEY_F]='f',[KEY_G]='g',
    [KEY_H]='h',[KEY_J]='j',[KEY_K]='k',[KEY_L]='l',
    [KEY_Z]='z',[KEY_X]='x',[KEY_C]='c',[KEY_V]='v',[KEY_B]='b',
    [KEY_N]='n',[KEY_M]='m',[KEY_SPACE]=' ',[KEY_MINUS]='-',
    [KEY_EQUAL]='=',[KEY_LEFTBRACE]='[',[KEY_RIGHTBRACE]=']',
    [KEY_BACKSLASH]='\\',[KEY_SEMICOLON]=';',[KEY_APOSTROPHE]='\'',
    [KEY_GRAVE]='`',[KEY_COMMA]=',',[KEY_DOT]='.',[KEY_SLASH]='/',
    [KEY_ENTER]='\n',[KEY_BACKSPACE]=127,[KEY_TAB]='\t',[KEY_ESC]=27
};
static const char keys_shift[128] = {
    [KEY_1]='!',[KEY_2]='@',[KEY_3]='#',[KEY_4]='$',[KEY_5]='%',
    [KEY_6]='^',[KEY_7]='&',[KEY_8]='*',[KEY_9]='(',[KEY_0]=')',
    [KEY_MINUS]='_',[KEY_EQUAL]='+',[KEY_LEFTBRACE]='{',[KEY_RIGHTBRACE]='}',
    [KEY_BACKSLASH]='|',[KEY_SEMICOLON]=':',[KEY_APOSTROPHE]='"',
    [KEY_GRAVE]='~',[KEY_COMMA]='<',[KEY_DOT]='>',[KEY_SLASH]='?'
};
static void scan_keyboards(void) {
    for (int i = 0; i < KBD_MAX; i++) {
        if (keyboard[i] >= 0) continue;
        char path[] = "/dev/input/event00";
        path[16] = (char)('0' + i / 10); path[17] = (char)('0' + i % 10);
        /* Device names below ten have no leading zero. */
        if (i < 10) { path[16] = (char)('0' + i); path[17] = 0; }
        int fd = xopen(path, O_RDONLY | 0x800 /* O_NONBLOCK */);
        if (fd < 0) continue;
        unsigned long bits[(KEY_MAX + 8 * sizeof(long)) / (8 * sizeof(long))];
        memset(bits, 0, sizeof(bits));
        if (xioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0 &&
            (((bits[KEY_A / (8 * sizeof(long))] & (1ul << (KEY_A % (8 * sizeof(long))))) &&
              (bits[KEY_ENTER / (8 * sizeof(long))] & (1ul << (KEY_ENTER % (8 * sizeof(long)))))) ||
             (bits[KEY_POWER / (8 * sizeof(long))] & (1ul << (KEY_POWER % (8 * sizeof(long))))) ||
             (bits[KEY_VOLUMEUP / (8 * sizeof(long))] & (1ul << (KEY_VOLUMEUP % (8 * sizeof(long))))) ||
             (bits[KEY_VOLUMEDOWN / (8 * sizeof(long))] & (1ul << (KEY_VOLUMEDOWN % (8 * sizeof(long)))))))
            keyboard[i] = fd;
        else sc6(SYS_close, fd, 0, 0, 0, 0, 0);
    }
}
static void keyboard_input(int fd, int mfd) {
    struct input_event ev[16];
    long n = xread(fd, ev, sizeof(ev));
    for (long i = 0; i < n / (long)sizeof(ev[0]); i++) {
        if (ev[i].type != EV_KEY) continue;
        unsigned k = ev[i].code;
        if (k == KEY_POWER) {
            if (ev[i].value == 1) { power_pressed = 1; power_long_triggered = 0; power_pressed_at = monotonic_seconds(); }
            else if (ev[i].value == 0 && power_pressed) {
                check_power_hold();
                if (!power_long_triggered) toggle_screen();
                power_pressed = 0;
            }
            continue;
        }
        if (k == KEY_VOLUMEUP) {
            if (ev[i].value==1) { vol_up_pressed=1; vol_long_triggered=0; vol_up_at=monotonic_seconds(); }
            else if (ev[i].value==0 && vol_up_pressed) {
                check_volume_hold(mfd);
                if(!vol_long_triggered) { if(heal_menu){heal_selected=(heal_selected+9)%10;show_heal_menu();} else show_health(); }
                vol_up_pressed=0;
            }
            continue;
        }
        if (k == KEY_VOLUMEDOWN) {
            if (ev[i].value==1) { vol_down_pressed=1; vol_long_triggered=0; vol_down_at=monotonic_seconds(); }
            else if (ev[i].value==0 && vol_down_pressed) {
                check_volume_hold(mfd);
                if(!vol_long_triggered) { if(heal_menu){heal_selected=(heal_selected+1)%10;show_heal_menu();} else {system_dashboard=0;xwrite(mfd,"\003",1);} }
                vol_down_pressed=0;
            }
            continue;
        }
        if (k == KEY_LEFTSHIFT || k == KEY_RIGHTSHIFT) { shift_down = ev[i].value != 0; continue; }
        if (k == KEY_LEFTCTRL || k == KEY_RIGHTCTRL) { ctrl_down = ev[i].value != 0; continue; }
        if (!ev[i].value) continue;
        const char *seq = 0;
        if (k == KEY_UP) seq = "\033[A"; else if (k == KEY_DOWN) seq = "\033[B";
        else if (k == KEY_RIGHT) seq = "\033[C"; else if (k == KEY_LEFT) seq = "\033[D";
        else if (k == KEY_DELETE) seq = "\033[3~";
        if (seq) { u64 len = 0; while (seq[len]) len++; xwrite(mfd, seq, len); continue; }
        if (k >= sizeof(keys_plain)) continue;
        char c = keys_plain[k];
        if (shift_down && keys_shift[k]) c = keys_shift[k];
        else if (shift_down && c >= 'a' && c <= 'z') c -= 'a' - 'A';
        if (ctrl_down && c >= 'a' && c <= 'z') c = c - 'a' + 1;
        if (ctrl_down && c >= 'A' && c <= 'Z') c = c - 'A' + 1;
        if (c) xwrite(mfd, &c, 1);
    }
}

static void grid_line(int row, int col, const char *s, u32 color) {
    if (row < 0 || row >= rows) return;
    while (*s && col < cols) {
        if (col >= 0) { grid[row * cols + col] = (u8)*s; grid_fg[row * cols + col] = color; }
        col++; s++;
    }
}
static long first_signed(const char *path, int *ok) {
    char b[64]; *ok=0; if(!read_text(path,b,sizeof(b))) return 0;
    const char *p=b; int neg=0; if(*p=='-'){neg=1;p++;}
    u64 n=parse_num(&p); *ok=1; return neg?-(long)n:(long)n;
}
static void append_fixed3(char *out,int *p,u64 milli) {
    append_num(out,p,milli/1000); append_text(out,p,".");
    u64 f=milli%1000; if(f<100)append_text(out,p,"0"); if(f<10)append_text(out,p,"0"); append_num(out,p,f);
}
static int read_core_stats(u64 total[8],u64 idle[8]) {
    char b[4096]; if(!read_text("/proc/stat",b,sizeof(b)))return 0;
    for(int i=0;i<8;i++){total[i]=0;idle[i]=0;}
    const char *p=b;
    while(*p){
        if(p[0]=='c'&&p[1]=='p'&&p[2]=='u'&&p[3]>='0'&&p[3]<='7'&&(p[4]==' '||p[4]=='\t')){
            int c=p[3]-'0'; const char *q=p+4; u64 v[8];
            for(int i=0;i<8;i++)v[i]=parse_num(&q);
            for(int i=0;i<8;i++)total[c]+=v[i]; idle[c]=v[3]+v[4];
        }
        while(*p&&*p!='\n')p++; if(*p)p++;
    }
    return 1;
}
static int cpu_freq_khz(int core) {
    char path[96]; int p=0; const char *a="/sys/devices/system/cpu/cpu"; while(*a)path[p++]=*a++;
    path[p++]=(char)('0'+core); a="/cpufreq/scaling_cur_freq"; while(*a)path[p++]=*a++; path[p]=0;
    return first_number(path);
}
static int thermal_temp(int zone) {
    char path[64]; int p=0; const char *a="/sys/class/thermal/thermal_zone"; while(*a)path[p++]=*a++;
    if(zone>=10)path[p++]=(char)('0'+zone/10); path[p++]=(char)('0'+zone%10);
    a="/temp";while(*a)path[p++]=*a++;path[p]=0;return first_number(path);
}
static void build_system_dashboard(void) {
    memset(grid,0,(u64)cols*rows); for(int i=0;i<cols*rows;i++)grid_fg[i]=COL_TEXT;
    grid_line(0,0,"+==========================================================+",COL_CYAN);
    grid_line(1,0,"|        BROWNYROLLZ PHONE STATUS / FASTFETCH             |",COL_CYAN);
    grid_line(2,0,"+==========================================================+",COL_CYAN);
    grid_line(4,2,"       .--.",COL_TEXT); grid_line(5,2,"      |o_o |",COL_TEXT);
    grid_line(6,2,"      |:_/ |",COL_TEXT); grid_line(7,2,"     //   \\ \\  ",COL_TEXT);
    grid_line(8,2,"    (|     | )====[ B ]",COL_TEXT); grid_line(8,22,"B",COL_ORANGE);
    grid_line(9,2,"   /'\\_   _/`\\",COL_TEXT); grid_line(10,2,"   \\___)=(___/",COL_TEXT);
    grid_line(4,30,"MODEL  Redmi Note 10 4G",COL_GREEN);
    grid_line(5,30,"DEVICE sunny / mojito family",COL_TEXT);
    grid_line(6,30,"SOC    Qualcomm SM6150",COL_TEXT);
    char raw[128],line[128];int p=0;
    append_text(line,&p,"KERNEL "); if(read_text("/proc/sys/kernel/osrelease",raw,sizeof(raw)))for(int i=0;raw[i]&&raw[i]!='\n'&&p<120;i++)line[p++]=raw[i]; line[p]=0;grid_line(7,30,line,COL_TEXT);
    p=0;append_text(line,&p,"UPTIME ");if(read_text("/proc/uptime",raw,sizeof(raw))){const char*q=raw;u64 sec=parse_num(&q);append_num(line,&p,sec/3600);append_text(line,&p,"h ");append_num(line,&p,(sec%3600)/60);append_text(line,&p,"m");}line[p]=0;grid_line(9,30,line,COL_TEXT);
    grid_line(12,1,"[ CPU CORES - REAL USAGE ]",COL_CYAN);
    u64 ta[8],ia[8],tb[8],ib[8];int pct[8]={0};read_core_stats(ta,ia);
    struct{long s,ns;}ts={0,160000000};sc6(SYS_nanosleep,(long)&ts,0,0,0,0,0);read_core_stats(tb,ib);
    for(int c=0;c<8;c++){
        u64 dt=tb[c]>=ta[c]?tb[c]-ta[c]:0,di=ib[c]>=ia[c]?ib[c]-ia[c]:0;
        pct[c]=dt&&di<=dt?(int)((dt-di)*100/dt):0;p=0;append_text(line,&p,"CORE ");append_num(line,&p,c);append_text(line,&p," ");append_bar(line,&p,pct[c],18);
        int khz=cpu_freq_khz(c);if(khz>0){append_text(line,&p,"  ");append_num(line,&p,(u64)khz/1000);append_text(line,&p,"MHz");}line[p]=0;grid_line(13+c,3,line,level_color(pct[c]));
    }
    int cpu_temp=0;for(int z=18;z<=25;z++){int t=thermal_temp(z);if(t>cpu_temp)cpu_temp=t;}
    p=0;append_text(line,&p,"CPU TEMP   ");if(cpu_temp){append_num(line,&p,(u64)cpu_temp/1000);append_text(line,&p,".");append_num(line,&p,(u64)(cpu_temp%1000)/100);append_text(line,&p," C");}else append_text(line,&p,"unavailable");line[p]=0;grid_line(22,3,line,cpu_temp>=80000?COL_RED:cpu_temp>=65000?COL_ORANGE:COL_GREEN);
    char mem[2048];u64 mt=0,ma=0;if(read_text("/proc/meminfo",mem,sizeof(mem))){mt=mem_field(mem,"MemTotal:");ma=mem_field(mem,"MemAvailable:");}
    int rp=mt&&ma<=mt?(int)((mt-ma)*100/mt):0;p=0;append_text(line,&p,"RAM  ");append_bar(line,&p,rp,22);append_text(line,&p,"  ");append_num(line,&p,(mt-ma)/1024);append_text(line,&p,"/");append_num(line,&p,mt/1024);append_text(line,&p,"MB");line[p]=0;grid_line(24,3,line,level_color(rp));
    struct statfs fs;int dp=0;p=0;append_text(line,&p,"DISK ");if(sc6(SYS_statfs,(long)"/",(long)&fs,0,0,0,0)==0&&fs.f_blocks){u64 used=fs.f_blocks-fs.f_bfree;dp=(int)(used*100/fs.f_blocks);append_bar(line,&p,dp,22);append_text(line,&p,"  ");append_num(line,&p,used*(u64)fs.f_bsize/1073741824u);append_text(line,&p,"/");append_num(line,&p,(u64)fs.f_blocks*(u64)fs.f_bsize/1073741824u);append_text(line,&p,"GB");}line[p]=0;grid_line(25,3,line,level_color(dp));
    grid_line(27,1,"[ BATTERY / CHARGER / HARDWARE ]",COL_CYAN);
    int okv=0,oki=0;long uv=first_signed("/sys/class/power_supply/battery/voltage_now",&okv),ua=first_signed("/sys/class/power_supply/battery/current_now",&oki);int bat=battery_percent();int bt=first_number("/sys/class/power_supply/battery/temp");
    p=0;append_text(line,&p,"BATTERY ");if(bat>=0){append_bar(line,&p,bat,14);append_text(line,&p,"  ");}if(read_text("/sys/class/power_supply/battery/status",raw,sizeof(raw)))for(int i=0;raw[i]&&raw[i]!='\n'&&p<120;i++)line[p++]=raw[i];if(bt>=0){append_text(line,&p,"  ");append_num(line,&p,(u64)bt/10);append_text(line,&p,".");append_num(line,&p,(u64)bt%10);append_text(line,&p,"C");}line[p]=0;grid_line(28,3,line,battery_color(bat));
    p=0;append_text(line,&p,"POWER   ");if(okv&&oki){u64 av=ua<0?(u64)(-ua):(u64)ua;append_fixed3(line,&p,(u64)uv/1000);append_text(line,&p,"V x ");append_num(line,&p,av/1000);append_text(line,&p,"mA = ");append_fixed3(line,&p,(u64)uv*av/1000000000u);append_text(line,&p,"W battery-side");}else append_text(line,&p,"current sensor unavailable");line[p]=0;grid_line(29,3,line,COL_YELLOW);
    int vmax=first_number("/sys/class/power_supply/usb/voltage_max"),imax=first_number("/sys/class/power_supply/usb/current_max");p=0;append_text(line,&p,"CHARGER ");if(read_text("/sys/class/power_supply/usb/real_type",raw,sizeof(raw)))for(int i=0;raw[i]&&raw[i]!='\n'&&p<120;i++)line[p++]=raw[i];if(vmax>0&&imax>0){append_text(line,&p,"  limit ");append_fixed3(line,&p,(u64)vmax/1000);append_text(line,&p,"V/");append_num(line,&p,(u64)imax/1000);append_text(line,&p,"mA");}line[p]=0;grid_line(30,3,line,COL_CYAN);
    grid_line(31,3,"CAMERA  Qualcomm CAM stack | sensor IDs not exported",COL_TEXT);
    int camt=thermal_temp(29);p=0;append_text(line,&p,"SENSORS camera ");if(camt>0){append_num(line,&p,(u64)camt/1000);append_text(line,&p,".");append_num(line,&p,(u64)(camt%1000)/100);append_text(line,&p,"C");}append_text(line,&p," | battery health ");if(read_text("/sys/class/power_supply/battery/health",raw,sizeof(raw)))for(int i=0;raw[i]&&raw[i]!='\n'&&p<120;i++)line[p++]=raw[i];line[p]=0;grid_line(32,3,line,COL_TEXT);
    p=0;append_text(line,&p,"NETWORK ");if(read_text("/run/sunny-lan/status",raw,sizeof(raw))){const char*q=raw+6;while(*q&&*q!='\n'&&p<120)line[p++]=*q++;}else append_text(line,&p,"unavailable");line[p]=0;grid_line(34,3,line,COL_CYAN);
    grid_line(37,4,"Vol+ short: refresh | Vol+/- hold: HEAL SYSTEM",COL_DIM);
    cx=0;cy=rows-1;
}
static void grid_value_line(int row, const char *label, const char *path, const char *unit, u64 divisor, u32 color) {
    char raw[64], out[120]; int p = 0;
    append_text(out, &p, label);
    if (read_text(path, raw, sizeof(raw))) {
        const char *q = raw; if (*q=='-') { out[p++]='-'; q++; }
        u64 n = parse_num(&q); if (divisor) n /= divisor;
        append_num(out, &p, n); append_text(out, &p, unit);
    } else append_text(out, &p, "unavailable");
    out[p] = 0; grid_line(row, 5, out, color);
}
static void build_charge_screen(void) {
    memset(grid, 0, (u64)cols * rows);
    for (int i = 0; i < cols * rows; i++) grid_fg[i] = COL_TEXT;
    int percent = battery_percent();
    if (percent < 0) percent = 0; if (percent > 100) percent = 100;
    u32 bcol = battery_color(percent);
    char status[48], source[48];
    int have_status = read_text("/sys/class/power_supply/battery/status", status, sizeof(status));
    int charging = have_status && status[0]=='C' && status[1]=='h';
    if (!read_text("/sys/class/power_supply/usb/real_type", source, sizeof(source)))
        if (!read_text("/sys/class/power_supply/usb/type", source, sizeof(source)))
            read_text("/sys/class/power_supply/usb/present", source, sizeof(source));
    for (int i=0; status[i]; i++) if (status[i]=='\n') status[i]=0;
    for (int i=0; source[i]; i++) if (source[i]=='\n') source[i]=0;

    grid_line(0, 0, "+==========================================================+", COL_CYAN);
    grid_line(1, 0, "|                 C H A R G I N G   M O D E                |", charging ? COL_GREEN : COL_ORANGE);
    grid_line(2, 0, "+==========================================================+", COL_CYAN);
    /* Tux's right arm is physically connected to the B block. */
    grid_line(4, 8, "       .--.", COL_TEXT);
    grid_line(5, 8, "      |o_o |", COL_TEXT);
    grid_line(6, 8, "      |:_/ |", COL_TEXT);
    grid_line(7, 8, "     //   \\ \\       +-----+", COL_TEXT);
    grid_line(8, 8, "    (|     | )=======[  B  ]", COL_TEXT);
    grid_line(8, 32, "B", COL_ORANGE);
    grid_line(9, 8, "   /'\\_   _/`\\      +-----+", COL_TEXT);
    grid_line(10,8, "   \\___)=(___/", COL_TEXT);

    grid_line(13, 1, "+------------------------------------------------------+--+", bcol);
    grid_line(14, 1, "|                                                      |  |", bcol);
    char bar[80]; int p=0; append_text(bar,&p,"|  [");
    int filled=(percent*38+99)/100;
    for(int i=0;i<38;i++) bar[p++]=i<filled?'#':'-';
    append_text(bar,&p,"]  "); append_num(bar,&p,(u64)percent); append_text(bar,&p,"%");
    while(p<55) bar[p++]=' '; append_text(bar,&p,"|  |"); bar[p]=0;
    grid_line(15, 1, bar, bcol);
    grid_line(16, 1, "|                                                      |  |", bcol);
    grid_line(17, 1, "+------------------------------------------------------+--+", bcol);
    grid_line(18, 30, "|", charging ? COL_GREEN : COL_RED);
    grid_line(19, 26, charging && (animation_phase & 1) ? "  *  |  *" : "     |", charging ? COL_YELLOW : COL_RED);
    grid_line(20, 26, charging ? "  +--+--+" : "  X  X  ", charging ? COL_GREEN : COL_RED);
    grid_line(21, 26, charging ? "  | USB |" : "DISCONNECTED", charging ? COL_GREEN : COL_RED);
    grid_line(22, 26, charging ? "  +-----+" : "NOT CHARGING", charging ? COL_GREEN : COL_RED);

    char state_line[100]; p=0; append_text(state_line,&p,"Status  : ");
    append_text(state_line,&p,have_status?status:"unavailable"); state_line[p]=0;
    grid_line(25,5,state_line,charging?COL_GREEN:COL_ORANGE);
    p=0; append_text(state_line,&p,"Source  : "); append_text(state_line,&p,source[0]?source:"unavailable"); state_line[p]=0;
    grid_line(26,5,state_line,COL_CYAN);
    grid_value_line(27,"Voltage : ","/sys/class/power_supply/battery/voltage_now"," mV",1000,COL_TEXT);
    grid_value_line(28,"Current : ","/sys/class/power_supply/battery/current_now"," mA",1000,COL_TEXT);
    grid_value_line(29,"Temp    : ","/sys/class/power_supply/battery/temp"," C",10,COL_TEXT);
    grid_line(32,8,"Hold Power 3 seconds to start full Linux.",COL_DIM);
    animation_phase++;
    cx = 0; cy = rows - 1;
}

static void render(void) {
    if (charge_only) build_charge_screen();
    else if (system_dashboard) build_system_dashboard();
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
            u32 *base = fb + (u64)(TOP_MARGIN + r * CH) * stride_px + LEFT_MARGIN + (u64)(c * CW);
            for (int gy = 0; gy < 16; gy++) {
                u8 bits = g[gy];
                if (!bits) continue;
                for (int sy = 0; sy < S; sy++) {
                    u32 *row = base + (u64)(gy * S + sy) * stride_px;
                    for (int gx = 0; gx < 8; gx++) {
                        if (bits & (0x80 >> gx)) {
                            for (int sx = 0; sx < S; sx++)
                                row[gx * S + sx] = grid_fg[r * cols + c] ? grid_fg[r * cols + c] : COL_TEXT;
                        }
                    }
                }
            }
        }
    }
    draw_status();
    /* cursor: underline block */
    if (!charge_only && !system_dashboard && cy < rows && cx < cols) {
        u32 *base = fb + (u64)(TOP_MARGIN + cy * CH + 14 * S) * stride_px + LEFT_MARGIN + (u64)(cx * CW);
        for (int sy = 0; sy < S; sy++) {
            u32 *row = base + (u64)sy * stride_px;
            for (int sx = 0; sx < CW; sx++) row[sx] = 0x00FFFFFFu;
        }
    }
    /* Notify DRM that CPU writes have changed the scanout buffer. */
    if (display_fd >= 0) {
        struct drm_mode_fb_dirty_cmd update;
        memset(&update, 0, sizeof(update));
        update.fb_id = display_crtc.fb_id;
        xioctl(display_fd, DRM_IOCTL_MODE_DIRTYFB, &update);
    }
    dirty = 0;
}

static void scroll_up(void) {
    memmove_(grid, grid + cols, (u64)(rows - 1) * cols);
    memmove_(grid_fg, grid_fg + cols, (u64)(rows - 1) * cols * sizeof(u32));
    memset(grid + (u64)(rows - 1) * cols, 0, (u64)cols);
    memset(grid_fg + (u64)(rows - 1) * cols, 0, (u64)cols * sizeof(u32));
    if (cy > 0) cy = rows - 1;
}

static void put_char(u8 ch) {
    if (ch == '\n') { cx = 0; cy++; }
    else if (ch == '\r') { cx = 0; }
    else if (ch == '\b') { if (cx > 0) cx--; }
    else if (ch == '\t') { cx = (cx + 8) & ~7; }
    else if (ch >= 32 && ch < 127) {
        grid[cy * cols + cx] = ch;
        grid_fg[cy * cols + cx] = current_fg;
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
    static int csi_param = 0;
    for (int i = 0; i < n; i++) {
        u8 c = buf[i];
        if (esc == 1) {           /* just saw ESC */
            if (c == '[' || c == ']' || c == '(' || c == ')') { esc = 2; csi_param = 0; continue; }
            esc = 0;
            continue;
        }
        if (esc == 2) {           /* inside CSI */
            if (c >= '0' && c <= '9') { csi_param = csi_param * 10 + c - '0'; continue; }
            if (c >= 0x40 && c <= 0x7e) {
                if (c == 'J' && (csi_param == 2 || csi_param == 3)) {
                    memset(grid, 0, (u64)cols * rows); memset(grid_fg, 0, (u64)cols * rows * sizeof(u32)); dirty = 1;
                } else if (c == 'H' || c == 'f') { cx = 0; cy = 0; dirty = 1;
                } else if (c == 'D') { int n=csi_param?csi_param:1; cx=cx>n?cx-n:0; dirty=1;
                } else if (c == 'C') { int n=csi_param?csi_param:1; cx+=n; if(cx>=cols)cx=cols-1; dirty=1;
                } else if (c == 'A') { int n=csi_param?csi_param:1; cy=cy>n?cy-n:0; dirty=1;
                } else if (c == 'B') { int n=csi_param?csi_param:1; cy+=n; if(cy>=rows)cy=rows-1; dirty=1;
                } else if (c == 'G') { cx=csi_param>0?csi_param-1:0; if(cx>=cols)cx=cols-1; dirty=1;
                } else if (c == 'K') {
                    int from=csi_param==2?0:cx, to=csi_param==1?cx:cols;
                    memset(grid+(u64)cy*cols+from,0,(u64)(to-from));
                    memset(grid_fg+(u64)cy*cols+from,0,(u64)(to-from)*sizeof(u32)); dirty=1;
                }
                esc = 0;
            }
            continue;
        }
        if (c == 0x1b) { esc = 1; continue; }
        if (c == 7) continue;     /* bell */
        put_char(c);
    }
}

int main_entry(void) {
    int charge_fd = xopen("/run/sunny-charge-mode", O_RDONLY);
    if (charge_fd >= 0) { charge_only = 1; sc6(SYS_close, charge_fd, 0, 0, 0, 0, 0); }
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
    display_fd = fd;
    display_connector = cid;
    display_crtc = set;
    display_crtc.set_connectors_ptr = (u64)(unsigned long)&display_connector;

    cols = (fbW - LEFT_MARGIN - RIGHT_MARGIN) / CW; rows = (fbH - TOP_MARGIN - BOTTOM_MARGIN) / CH;
    grid = (u8 *)xmmap(0, (u64)cols * rows, 3, 0x22 /*MAP_PRIVATE|ANON*/, -1, 0);
    if ((long)grid < 0 && (long)grid > -4096) { puts_("sunnyterm: grid mmap\n"); return 9; }
    grid_fg = (u32 *)xmmap(0, (u64)cols * rows * sizeof(u32), 3, 0x22, -1, 0);
    if ((long)grid_fg < 0 && (long)grid_fg > -4096) { puts_("sunnyterm: color mmap\n"); return 9; }
    memset(grid, 0, (u64)cols * rows);
    memset(grid_fg, 0, (u64)cols * rows * sizeof(u32));
    static const u8 banner[] = "Brownyrollz-PhoneSunny\r\nUbuntu root mounted - starting services\r\n\r\n";
    static const u8 charge_banner[] =
        "Brownyrollz-PhoneSunny\r\n\r\n"
        "         CHARGING\r\n\r\n"
        "   +--------------------------+\r\n"
        "   |                          |--+\r\n"
        "   |  [....................]  |  |\r\n"
        "   |                          |--+\r\n"
        "   +--------------------------+\r\n"
        "                |\r\n"
        "                +------- USB POWER\r\n\r\n"
        "      Hold Power to start Linux.\r\n";
    if (charge_only) feed(charge_banner, sizeof(charge_banner) - 1);
    else feed(banner, sizeof(banner) - 1);

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
        /* The shell must not retain DRM master after the terminal exits. */
        sc6(SYS_close, fd, 0, 0, 0, 0, 0);
        sc6(SYS_close, mfd, 0, 0, 0, 0, 0);
        sc6(SYS_setsid, 0, 0, 0, 0, 0, 0);
        xioctl(sfd, TIOCSCTTY, 0);
        xdup3(sfd, 0); xdup3(sfd, 1); xdup3(sfd, 2);
        char *argv[] = {"sh", "-c", charge_only ? "while :; do sleep 60; done" : "/usr/bin/busybox dmesg 2>/dev/null | head -n 55; sleep 5; printf '\\033[2J\\033[H'; printf 'Brownyrollz-PhoneSunny - local console ready\\n'; /usr/local/sbin/sunny-usb-status & watcher=$!; /bin/bash --noprofile --norc -i; kill $watcher 2>/dev/null", 0};
        char *envp[] = {"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin", "HOME=/root",
                        "TERM=linux", "HISTFILE=/root/.bash_history", "HISTSIZE=500", "HISTCONTROL=ignoredups", "PS1=Brownyrollz-PhoneSunny:~# ", 0};
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
        puts_("sunnyterm: serial input unavailable; watching for USB keyboards\n");
    }

    render();

    u8 buf[512];
    for (int i = 0; i < KBD_MAX; i++) keyboard[i] = -1;
    int refresh_tick = 0;
    for (;;) {
        struct { long events; short revents; } dummy;
        /* poll master (always) and tty (if any) */
        struct { int fd; short events; short revents; } pfd[2 + KBD_MAX];
        pfd[0].fd = mfd; pfd[0].events = 1; pfd[0].revents = 0;
        int np = 1;
        if (tty >= 0) { pfd[1].fd = tty; pfd[1].events = 1; pfd[1].revents = 0; np = 2; }
        scan_keyboards();
        int key_start = np;
        for (int i = 0; i < KBD_MAX; i++) {
            pfd[np].fd = keyboard[i]; pfd[np].events = 1; pfd[np].revents = 0; np++;
        }
        if (++refresh_tick >= 5) { render(); refresh_tick = 0; }
        (void)dummy;
        struct { long sec, nsec; } timeout = {1, 0};
        sc6(SYS_ppoll, (long)pfd, np, (long)&timeout, 0, 0, 0);
        check_power_hold();
        check_volume_hold(mfd);

        if (pfd[0].revents & 1) {
            long n = xread(mfd, buf, sizeof(buf));
            if (n > 0) { feed(buf, (int)n); if (dirty) render(); }
        }

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
        for (int i = 0; i < KBD_MAX; i++) {
            if (keyboard[i] < 0) continue;
            short events = pfd[key_start + i].revents;
            if (events & 1) keyboard_input(keyboard[i], mfd);
            if (dirty) render();
            if (events & (8 | 16 | 32)) {
                sc6(SYS_close, keyboard[i], 0, 0, 0, 0, 0);
                keyboard[i] = -1;
            }
        }
    }
    return 0;
}

void _start(void) { xexit(main_entry()); }
