#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SIMULATOR_DESTINATION:-}" ]]; then
  printf '%s\n' "$SIMULATOR_DESTINATION"
  exit 0
fi

preferred_devices=(
  "iPhone 17"
  "iPhone 16"
  "iPhone 15"
  "iPhone 14"
)

available_devices="$(xcrun simctl list devices available 2>/dev/null || true)"

for device_name in "${preferred_devices[@]}"; do
  if grep -q "$device_name (" <<<"$available_devices"; then
    printf 'platform=iOS Simulator,name=%s\n' "$device_name"
    exit 0
  fi
done

first_iphone="$(
  awk -F '[()]' '/iPhone/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
    print $1
    exit
  }' <<<"$available_devices"
)"

if [[ -n "$first_iphone" ]]; then
  printf 'platform=iOS Simulator,name=%s\n' "$first_iphone"
  exit 0
fi

printf 'No available iPhone simulator found. Set SIMULATOR_DESTINATION explicitly.\n' >&2
exit 1
