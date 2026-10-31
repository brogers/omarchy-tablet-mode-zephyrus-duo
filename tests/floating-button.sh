#!/bin/bash
# The floating button setting lives in the config. A missing key stays on,
# and button on/off/toggle writes it without starting the daemon.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/zephyrus-duo-keyboard"
TMP=$(mktemp -d)

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TMP/usb" "$TMP/run" "$TMP/omarchy"
cat >"$TMP/keyboard.conf" <<'EOF'
enabled=true
keyboard=0b05:1ce6
show_keyboard=false
EOF

run() {
  TABLET_MODE_CONF="$TMP/keyboard.conf" \
    TABLET_MODE_USB_DEVICES="$TMP/usb" \
    TABLET_MODE_RUN_DIR="$TMP/run" \
    TABLET_MODE_OMARCHY_CONFIG="$TMP/omarchy" \
    "$BIN" "$@"
}

expect() {
  local filter=$1
  local st
  st=$(run status --json) || fail "status --json failed"
  jq -e "$filter" <<<"$st" >/dev/null || fail "$filter, got: $st"
}

expect '.floating_button == true'
grep -q floating_button "$TMP/keyboard.conf" && fail "status rewrote a config that omitted the key"

run button off
expect '.floating_button == false'
grep -qx 'floating_button=false' "$TMP/keyboard.conf" || fail "button off did not write floating_button=false"

run button on
expect '.floating_button == true'
grep -qx 'floating_button=true' "$TMP/keyboard.conf" || fail "button on did not write floating_button=true"

run button toggle
expect '.floating_button == false'

run button toggle
expect '.floating_button == true'

if run button sideways >/dev/null 2>"$TMP/err"; then
  fail "button accepted a bad argument"
fi
grep -q 'Usage:' "$TMP/err" || fail "bad argument did not print usage"
