#!/bin/bash
# Dock transitions only show or hide the on-screen keyboard.
# A fake sysfs tree stands in for /sys/bus/usb/devices. Dry-run logs actions
# and must not eval hl.monitor or hl.device.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/zephyrus-duo-keyboard"
TMP=$(mktemp -d)
DAEMON_PID=""

cleanup() {
  if [[ -n $DAEMON_PID ]]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  echo "--- log ---" >&2
  cat "$LOG" >&2 || true
  echo "--- daemon ---" >&2
  cat "$ERR" >&2 || true
  exit 1
}

usb_dev() {
  local name=$1 vendor=$2 product=$3
  mkdir -p "$USB/$name"
  printf '%s\n' "$vendor" >"$USB/$name/idVendor"
  printf '%s\n' "$product" >"$USB/$name/idProduct"
}

decoys() {
  usb_dev ite 0b05 193b
  usb_dev z13 0b05 1a30
}

stop_daemon() {
  if [[ -n $DAEMON_PID ]]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
    DAEMON_PID=""
  fi
}

start_daemon() {
  local show=$1
  stop_daemon
  rm -rf "$USB" "$RUN" "$LOG" "$ERR" "$CONF"
  mkdir -p "$USB" "$RUN"
  decoys
  cat >"$CONF" <<EOF
enabled=true
keyboard=0b05:1ce6
auto_rotate=false
show_keyboard=$show
touch_tweaks=false
EOF
  : >"$LOG"
  TABLET_MODE_DRYRUN=1 \
    TABLET_MODE_LOG="$LOG" \
    TABLET_MODE_USB_DEVICES="$USB" \
    TABLET_MODE_CONF="$CONF" \
    TABLET_MODE_RUN_DIR="$RUN" \
    "$BIN" daemon --no-readers >"$ERR" 2>&1 &
  DAEMON_PID=$!
  local _
  for _ in $(seq 1 50); do
    [[ -p $RUN/events ]] && grep -q '^dock:' "$ERR" && break
    kill -0 "$DAEMON_PID" 2>/dev/null || fail "daemon exited during startup"
    sleep 0.05
  done
  [[ -p $RUN/events ]] || fail "daemon did not create the event fifo"
  grep -q '^dock:' "$ERR" || fail "daemon did not report the dock"
}

send_usb() {
  timeout 2 bash -c 'printf "%s\n" "$1" >"$2"' _ usb "$RUN/events" || fail "could not write the usb event"
}

# Wait out the 800ms USB settle, then a little more.
settle() { sleep 1.5; }

assert_hide_without_eval() {
  grep -q 'osk hide' "$LOG" || fail "expected an OSK hide"
  if grep -E 'eval hl\.(monitor|device)|hl\.monitor|hl\.device' "$LOG" "$ERR"; then
    fail "display eval was logged"
  fi
}

assert_no_show() {
  if grep -q 'osk show' "$LOG"; then
    fail "OSK show was logged while show_keyboard=false"
  fi
}

USB="$TMP/usb"
RUN="$TMP/run"
LOG="$TMP/actions.log"
ERR="$TMP/daemon.err"
CONF="$TMP/keyboard.conf"

# Lifted -> seated: hide, and never eval a monitor or device.
start_daemon false
send_usb
settle
# Still lifted (only the Z13 id and the ITE controller are on the bus): no hide yet.
if grep -q 'osk hide' "$LOG"; then
  fail "1a30/193b were treated as the dock"
fi
usb_dev dock 0b05 1ce6
send_usb
settle
assert_hide_without_eval
stop_daemon

# Seated -> lifted, show_keyboard=false: do not show.
start_daemon false
usb_dev dock 0b05 1ce6
send_usb
settle
: >"$LOG"
rm -rf "$USB/dock"
send_usb
settle
assert_no_show
stop_daemon

# Same transition with show_keyboard=true: show.
start_daemon true
usb_dev dock 0b05 1ce6
send_usb
settle
: >"$LOG"
rm -rf "$USB/dock"
send_usb
settle
grep -q 'osk show' "$LOG" || fail "expected an OSK show when show_keyboard=true"
if grep -E 'eval hl\.(monitor|device)|hl\.monitor|hl\.device' "$LOG" "$ERR"; then
  fail "display eval was logged on show"
fi
stop_daemon

# rotate, lock, and calibrate are refused and name the rotator.
for cmd in rotate lock calibrate; do
  set +e
  out=$("$BIN" "$cmd" 2>&1)
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "$cmd exited 0"
  [[ $out == *zephyrus-duo-rotate* ]] || fail "$cmd did not name zephyrus-duo-rotate: $out"
done

# The event path has no live call into the removed helpers.
if grep -nE 'rotate_to|map_touch|tweaks_apply|inhibit_take|systemd-inhibit' "$BIN"; then
  fail "removed helper is still named in the daemon"
fi

echo "ok"
