#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Minimal userspace companion for Qualcomm's downstream QG driver. */
enum qg_id {
	QG_SOC, QG_OCV_UV, QG_RBAT_MOHM, QG_PON_OCV_UV, QG_GOOD_OCV_UV,
	QG_ESR, QG_CHARGE_COUNTER, QG_FIFO_TIME_DELTA, QG_BATT_SOC,
	QG_CC_SOC, QG_ESR_CHARGE_DELTA, QG_ESR_DISCHARGE_DELTA,
	QG_ESR_CHARGE_SF, QG_ESR_DISCHARGE_SF, QG_FULL_SOC,
	QG_CLEAR_LEARNT_DATA, QG_SYS_SOC, QG_RESERVED_10, QG_MAX
};

#define MAX_FIFO_LENGTH 16

struct qg_param { uint32_t data; bool valid; };
struct fifo_data { uint32_t v, i, count, interval; };
struct qg_kernel_data {
	uint32_t seq_no, fifo_time, fifo_length;
	struct fifo_data fifo[MAX_FIFO_LENGTH];
	struct qg_param param[QG_MAX];
};
struct qg_user_data { struct qg_param param[QG_MAX]; };

static long long read_number(const char *path, long long fallback)
{
	char buf[64];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	ssize_t n;
	char *end;
	long long value;

	if (fd < 0)
		return fallback;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return fallback;
	buf[n] = '\0';
	errno = 0;
	value = strtoll(buf, &end, 10);
	return errno || end == buf ? fallback : value;
}

static long long monotonic_seconds(void)
{
	struct timespec ts;
	if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0)
		return 0;
	return ts.tv_sec;
}

static void set_param(struct qg_user_data *u, enum qg_id id, uint32_t value)
{
	u->param[id].data = value;
	u->param[id].valid = true;
}

int main(void)
{
	struct qg_kernel_data kdata;
	struct qg_user_data udata;
	struct pollfd pfd;
	long long raw, full_uah, accumulator_uas = 0;
	long long last, last_report = 0;
	int fd;

	fd = open("/dev/qg", O_RDWR | O_CLOEXEC | O_NONBLOCK);
	if (fd < 0) {
		perror("sunny-qgd: open /dev/qg");
		return 1;
	}
	raw = read_number("/sys/class/power_supply/bms/capacity_raw", -1);
	if (raw < 0 || raw > 10000)
		raw = read_number("/sys/class/power_supply/bms/real_capacity", 50) * 100;
	full_uah = read_number("/sys/class/power_supply/bms/charge_full", 5020000);
	if (full_uah < 1000000 || full_uah > 10000000)
		full_uah = 5020000;
	last = monotonic_seconds();
	pfd.fd = fd;
	pfd.events = POLLIN;
	fprintf(stderr, "sunny-qgd: native QG fallback started raw=%lld full=%llduAh\n",
		raw, full_uah);

	for (;;) {
		long long now, elapsed, current_ua, voltage_uv, denominator, delta;
		long long usb_present, charge_done;
		int pr = poll(&pfd, 1, 10000);

		if (pr > 0 && (pfd.revents & POLLIN)) {
			while (read(fd, &kdata, sizeof(kdata)) > 0)
				;
		}
		now = monotonic_seconds();
		elapsed = now - last;
		if (elapsed <= 0)
			continue;
		if (elapsed > 300)
			elapsed = 300;
		last = now;

		current_ua = read_number("/sys/class/power_supply/bms/current_now", 0);
		voltage_uv = read_number("/sys/class/power_supply/bms/voltage_now", 0);
		usb_present = read_number("/sys/class/power_supply/usb/present", 0);
		charge_done = read_number("/sys/class/power_supply/battery/charge_done", 0);
		full_uah = read_number("/sys/class/power_supply/bms/charge_full", full_uah);
		if (full_uah < 1000000 || full_uah > 10000000)
			full_uah = 5020000;

		/* QG reports positive current while discharging, negative while charging. */
		accumulator_uas += -current_ua * elapsed;
		denominator = full_uah * 3600LL;
		delta = (accumulator_uas * 10000LL) / denominator;
		if (delta) {
			raw += delta;
			accumulator_uas -= (delta * denominator) / 10000LL;
		}
		if (charge_done && usb_present)
			raw = 10000;
		if (raw < 0)
			raw = 0;
		if (raw > 10000)
			raw = 10000;

		memset(&udata, 0, sizeof(udata));
		set_param(&udata, QG_SOC, (uint32_t)raw);
		set_param(&udata, QG_SYS_SOC, (uint32_t)raw);
		set_param(&udata, QG_BATT_SOC, (uint32_t)raw);
		set_param(&udata, QG_CC_SOC, (uint32_t)raw);
		set_param(&udata, QG_FULL_SOC, 10000);
		if (voltage_uv > 0)
			set_param(&udata, QG_OCV_UV, (uint32_t)voltage_uv);
		if (write(fd, &udata, sizeof(udata)) != (ssize_t)sizeof(udata)) {
			if (errno != EAGAIN && errno != EINTR)
				perror("sunny-qgd: write");
		}
		if (now - last_report >= 60) {
			fprintf(stderr,
				"sunny-qgd: raw=%lld current=%llduA voltage=%llduV usb=%lld residual=%llduAs\n",
				raw, current_ua, voltage_uv, usb_present, accumulator_uas);
			last_report = now;
		}
	}
}
