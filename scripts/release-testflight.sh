#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/IOSAPP/PhotoDel.xcodeproj"
SCHEME="${SCHEME:-PhotoDel}"
TEAM_ID="${TEAM_ID:-PCJ84YD7HQ}"
BUNDLE_ID="${BUNDLE_ID:-com.01MVP.PhotoDel}"
PROFILE_SPECIFIER="${PROFILE_SPECIFIER:-PhotoDel App Store}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Distribution}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
SIMULATOR_DESTINATION="${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
RELEASE_DIR="${PHOTO_DEL_RELEASE_DIR:-/tmp/PhotoDelRelease}"
ARCHIVE_PATH="$RELEASE_DIR/PhotoDel.xcarchive"
EXPORT_PATH="$RELEASE_DIR/export"
EXPORT_OPTIONS="$RELEASE_DIR/ExportOptions.plist"
SKIP_TESTS="${SKIP_TESTS:-0}"

check_icon_alpha() {
  local icon_dir="$ROOT_DIR/IOSAPP/PhotoDel/Assets.xcassets/AppIcon.appiconset"
  local alpha_icons=()

  while IFS= read -r -d '' icon_path; do
    if sips -g hasAlpha "$icon_path" 2>/dev/null | grep -q "hasAlpha: yes"; then
      alpha_icons+=("$icon_path")
    fi
  done < <(find "$icon_dir" -name '*.png' -print0)

  if (( ${#alpha_icons[@]} > 0 )); then
    printf 'App icons must not contain alpha channels:\n' >&2
    printf '  %s\n' "${alpha_icons[@]}" >&2
    return 1
  fi
}

write_export_options() {
  /usr/libexec/PlistBuddy -c 'Clear dict' "$EXPORT_OPTIONS" >/dev/null
  /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :signingCertificate string $CODE_SIGN_IDENTITY" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$BUNDLE_ID string $PROFILE_SPECIFIER" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool true' "$EXPORT_OPTIONS"
  plutil -lint "$EXPORT_OPTIONS"
}

if [[ "$SKIP_TESTS" != "1" ]]; then
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_DESTINATION"
fi

check_icon_alpha

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_SPECIFIER" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

write_export_options

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

printf 'Uploaded PhotoDel %s (%s) to App Store Connect/TestFlight.\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
