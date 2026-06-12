#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/IOSAPP/PhotoDelete.xcodeproj"
SCHEME="${SCHEME:-PhotoDelete}"
TEAM_ID="${TEAM_ID:-PCJ84YD7HQ}"
BUNDLE_ID="${BUNDLE_ID:-com.01mvp.photodelete}"
PROFILE_SPECIFIER="${PROFILE_SPECIFIER:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Distribution}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
ARCHIVE_CODE_SIGNING_ALLOWED="${ARCHIVE_CODE_SIGNING_ALLOWED:-YES}"
ARCHIVE_CODE_SIGNING_ALLOWED="$(printf '%s' "$ARCHIVE_CODE_SIGNING_ALLOWED" | tr '[:lower:]' '[:upper:]')"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(TZ=Asia/Shanghai date +%Y%m%d%H%M)}"
SIMULATOR_DESTINATION="$("$ROOT_DIR/scripts/resolve-ios-simulator-destination.sh")"
RELEASE_DIR="${PHOTO_DELETE_RELEASE_DIR:-/tmp/PhotoDeleteRelease}"
ARCHIVE_PATH="$RELEASE_DIR/PhotoDelete.xcarchive"
EXPORT_PATH="$RELEASE_DIR/export"
EXPORT_OPTIONS="$RELEASE_DIR/ExportOptions.plist"
SKIP_TESTS="${SKIP_TESTS:-0}"

check_icon_alpha() {
  local icon_dir="$ROOT_DIR/IOSAPP/PhotoDelete/Assets.xcassets/AppIcon.appiconset"
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
  if [[ "$CODE_SIGN_STYLE" == "Manual" ]]; then
    if [[ -z "$PROFILE_SPECIFIER" ]]; then
      printf 'PROFILE_SPECIFIER is required when CODE_SIGN_STYLE=Manual.\n' >&2
      return 1
    fi
    /usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c "Add :signingCertificate string $CODE_SIGN_IDENTITY" "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$BUNDLE_ID string $PROFILE_SPECIFIER" "$EXPORT_OPTIONS"
  else
    /usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$EXPORT_OPTIONS"
  fi
  /usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$EXPORT_OPTIONS"
  plutil -lint "$EXPORT_OPTIONS"
}

verify_archive_version() {
  local info_plist="$ARCHIVE_PATH/Products/Applications/PhotoDelete.app/Info.plist"
  local archived_build_number

  if [[ ! -f "$info_plist" ]]; then
    printf 'Archive Info.plist not found at %s.\n' "$info_plist" >&2
    return 1
  fi

  archived_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [[ "$archived_build_number" != "$BUILD_NUMBER" ]]; then
    printf 'Archive CFBundleVersion mismatch: expected %s, got %s.\n' "$BUILD_NUMBER" "$archived_build_number" >&2
    return 1
  fi
}

case "$ARCHIVE_CODE_SIGNING_ALLOWED" in
  YES|NO)
    ;;
  *)
    printf 'ARCHIVE_CODE_SIGNING_ALLOWED must be YES or NO, got %s.\n' "$ARCHIVE_CODE_SIGNING_ALLOWED" >&2
    exit 1
    ;;
esac

if [[ "$SKIP_TESTS" != "1" ]]; then
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_DESTINATION"
fi

check_icon_alpha

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

archive_signing_args=(
  "DEVELOPMENT_TEAM=$TEAM_ID"
  "CODE_SIGNING_ALLOWED=$ARCHIVE_CODE_SIGNING_ALLOWED"
  "MARKETING_VERSION=$MARKETING_VERSION"
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
)

if [[ "$ARCHIVE_CODE_SIGNING_ALLOWED" != "NO" ]]; then
  archive_signing_args+=("CODE_SIGN_STYLE=$CODE_SIGN_STYLE")
fi

if [[ "$ARCHIVE_CODE_SIGNING_ALLOWED" != "NO" && "$CODE_SIGN_STYLE" == "Manual" ]]; then
  archive_signing_args+=(
    "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
    "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_SPECIFIER"
  )
fi

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "${archive_signing_args[@]}"

verify_archive_version

if [[ "$ARCHIVE_CODE_SIGNING_ALLOWED" == "NO" ]]; then
  printf 'Dry-run archive completed for PhotoDelete %s (%s); skipped export and upload because ARCHIVE_CODE_SIGNING_ALLOWED=NO.\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
  exit 0
fi

write_export_options

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

printf 'Uploaded PhotoDelete %s (%s) to App Store Connect/TestFlight.\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
