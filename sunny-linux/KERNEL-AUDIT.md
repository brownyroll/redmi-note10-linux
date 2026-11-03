# PhoneSunny native Ubuntu and Docker audit

Target tested: Redmi Note 10 4G (`sunny`), Linux
`4.14.206-NetErnels-YAAP`, aarch64.

## What is native today

- Ubuntu 26.04.1 ARM64 is the real persistent root filesystem on the phone.
- Processes execute directly on the phone kernel; there is no PRoot, VM, or
  CPU emulation.
- APT, OpenSSH, DNS, the local DRM terminal, and persistent files are native.
- PID 1 is `sunny-native-init`; systemd 259 is installed but is not PID 1 and
  is not advertised as working.
- Docker 29.1.3, containerd 2.2.2, runc, Compose and Buildx packages are
  present in the Ubuntu filesystem.

## Runtime kernel audit

Available and verified: cgroup v1 `cpuset`, `cpu`, `cpuacct`, `blkio`,
`freezer`; namespaces exposed under `/proc/*/ns`; overlayfs; bridge, veth,
netfilter, NAT and seccomp in the extracted kernel config.

Missing from the **running kernel** `/proc/cgroups`: `devices`, `pids`, and
`memory`. The running `/proc/config.gz` also does not expose `CGROUP_DEVICE`,
`CGROUP_PIDS`, `IPC_NS`, or `POSIX_MQUEUE`. These are hard blockers for a safe,
normal Docker daemon and for genuine systemd container/service isolation.

The installed Docker 29 daemon reaches containerd/overlay initialization, but
fails while creating the daemon on this incomplete cgroup environment. Docker
29 then has a cleanup panic in `daemon/events.(*Events).Close`; that panic is
not reported as a successful Docker start.

`sunnyctl kernel-audit` reads the live kernel and prints the blockers.
`sunnyctl docker start` refuses to claim success when the controllers are
missing. No wrapper is allowed to claim a successful systemd transaction.

For operator convenience, `/usr/local/bin/systemctl` is an explicit native
service-manager compatibility adapter for only `ssh/sshd` and `docker`. Its
output always identifies `sunny-native-init`, it returns failure for unsupported
units, and it defers to `/usr/bin/systemctl` automatically if genuine systemd
ever becomes PID 1. It does not imitate a successful systemd transaction.

## Lifecycle commands

```
sunnyctl ubuntu start|stop|restart|status|enter|logs
sunnyctl ssh start|stop|restart|status
sunnyctl docker start|stop|restart|status
sunnyctl battery
sunnyctl kernel-audit
```

Because Ubuntu is currently the phone's root userspace, `ubuntu stop` stops
managed Ubuntu services, not PID 1 or the root filesystem.

## Android coexistence warning

The current installation uses partition `userdata` (`/dev/sda17`) as the
Ubuntu root filesystem. Consequently, it does **not** preserve a usable
Android `/data` on that partition. Kernel/vendor/boot partitions and the
original vendor_boot backup remain available, but claiming full Android and
Ubuntu coexistence in the current layout would be false. Real coexistence
requires repartitioning or placing the Ubuntu rootfs as an image/directory on
an Android-owned filesystem, then booting it by mount/chroot/namespace.

## Kernel work required for Docker/systemd acceptance

Rebuild the exact sunny/mojito vendor kernel and matching DTB/DTBO with, at
minimum, cgroup devices/pids/memory, IPC namespaces, POSIX mqueues, and all
currently working Android vendor drivers retained. After flashing only a
tested boot/kernel artifact, rerun `sunnyctl kernel-audit`, start Docker, and
perform `docker run --rm hello-world`, networking, published-port, volume,
restart-policy, Compose, Buildx, reboot and shutdown tests on target hardware.
