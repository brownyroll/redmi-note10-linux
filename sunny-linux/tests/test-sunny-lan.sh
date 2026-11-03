#!/usr/bin/env bash
# Root-only integration test: DHCP server starts late, disappears, and returns.
set -euo pipefail
NS=sunny-lan-test-client
HOST=snylan-host
TMP=$(mktemp -d /tmp/sunny-lan-test.XXXXXX)
CLIENT_PID= SERVER_PID=
cleanup() {
  [ -z "$CLIENT_PID" ] || kill "$CLIENT_PID" 2>/dev/null || true
  [ -z "$SERVER_PID" ] || kill "$SERVER_PID" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  ip link del "$HOST" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
ip netns del "$NS" 2>/dev/null || true
ip link del "$HOST" 2>/dev/null || true
ip netns add "$NS"
ip link add "$HOST" type veth peer name eth9
ip link set eth9 netns "$NS"
ip link set "$HOST" up
ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip link set eth9 up
cat > "$TMP/client.conf" <<EOF
MODE=dhcp
DHCP_RETRY_SECONDS=2
FALLBACK_SERVER=no
EOF
cat > "$TMP/server.conf" <<EOF
start 10.77.0.10
end 10.77.0.20
interface $HOST
lease_file $TMP/leases
pidfile $TMP/server.pid
option subnet 255.255.255.0
option router 10.77.0.1
option dns 10.77.0.1
option lease 60
EOF
touch "$TMP/leases"
SCRIPT=${1:-$(cd "$(dirname "$0")/.." && pwd)/build/sunny-lan}
ip netns exec "$NS" env SUNNY_LAN_CONFIG="$TMP/client.conf" SUNNY_LAN_RUN="$TMP/run" \
  SUNNY_RESOLV_CONF="$TMP/resolv.conf" \
  "$SCRIPT" >"$TMP/client.log" 2>&1 & CLIENT_PID=$!
sleep 6
grep -q 'Waiting for DHCP' "$TMP/run/status"

# The cable stays connected. Only the upstream DHCP service becomes ready.
ip addr add 10.77.0.1/24 dev "$HOST"
/usr/bin/busybox udhcpd -f "$TMP/server.conf" >"$TMP/server.log" 2>&1 & SERVER_PID=$!
for _ in $(seq 1 15); do
  ip netns exec "$NS" ip -4 addr show dev eth9 | grep -q '10.77.0.' && break
  sleep 1
done
ip netns exec "$NS" ip -4 addr show dev eth9 | grep -q '10.77.0.'
for _ in $(seq 1 5); do grep -q '^STATE=Network Connected' "$TMP/run/status" && break; sleep 1; done
grep -q '^STATE=Network Connected' "$TMP/run/status" || { cat "$TMP/run/status"; cat "$TMP/client.log"; exit 1; }

# Simulate a lost lease while link remains up; DHCP later returns, no replug.
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=
ip netns exec "$NS" ip addr flush dev eth9 scope global
sleep 5
grep -Eq '^STATE=(DHCP Retry|Waiting for DHCP|Requesting IP)' "$TMP/run/status"
/usr/bin/busybox udhcpd -f "$TMP/server.conf" >"$TMP/server2.log" 2>&1 & SERVER_PID=$!
for _ in $(seq 1 15); do
  ip netns exec "$NS" ip -4 addr show dev eth9 | grep -q '10.77.0.' && break
  sleep 1
done
ip netns exec "$NS" ip -4 addr show dev eth9 | grep -q '10.77.0.'
for _ in $(seq 1 5); do grep -q '^GATEWAY=10.77.0.1' "$TMP/run/status" && break; sleep 1; done
grep -q '^GATEWAY=10.77.0.1' "$TMP/run/status"
grep -q '^DNS=10.77.0.1' "$TMP/run/status"

# A second manager must not compete for the same interface.
ip netns exec "$NS" env SUNNY_LAN_CONFIG="$TMP/client.conf" SUNNY_LAN_RUN="$TMP/run" \
  SUNNY_RESOLV_CONF="$TMP/resolv.conf" "$SCRIPT"
echo 'PASS: late DHCP, automatic recovery, gateway/DNS, and single-owner lock'
