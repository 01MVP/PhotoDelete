#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/IOSAPP/PhotoDelete.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
SCHEME="${SCHEME:-PhotoDelete}"
TEAM_ID="${TEAM_ID:-PCJ84YD7HQ}"
BUNDLE_ID="${BUNDLE_ID:-com.01mvp.photodelete}"
PROFILE_SPECIFIER="${PROFILE_SPECIFIER:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Distribution}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
ARCHIVE_CODE_SIGNING_ALLOWED="${ARCHIVE_CODE_SIGNING_ALLOWED:-YES}"
ARCHIVE_CODE_SIGNING_ALLOWED="$(printf '%s' "$ARCHIVE_CODE_SIGNING_ALLOWED" | tr '[:lower:]' '[:upper:]')"
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-}"
XCODE_AUTH_ARGS=()

if [[ -n "$ASC_KEY_ID" || -n "$ASC_ISSUER_ID" || -n "$ASC_PRIVATE_KEY_PATH" ]]; then
  if [[ -z "$ASC_KEY_ID" || -z "$ASC_ISSUER_ID" || -z "$ASC_PRIVATE_KEY_PATH" ]]; then
    printf 'ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH must be provided together.\n' >&2
    exit 1
  fi
  if [[ ! -f "$ASC_PRIVATE_KEY_PATH" ]]; then
    printf 'ASC private key not found at %s.\n' "$ASC_PRIVATE_KEY_PATH" >&2
    exit 1
  fi
  XCODE_AUTH_ARGS=(
    -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

run_xcodebuild() {
  if (( ${#XCODE_AUTH_ARGS[@]} > 0 )); then
    xcodebuild "$@" "${XCODE_AUTH_ARGS[@]}"
  else
    xcodebuild "$@"
  fi
}

resolve_project_marketing_version() {
  local version
  version="$(
    xcodebuild -showBuildSettings \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration Release 2>/dev/null |
      awk -F= '/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        print $2
        exit
      }'
  )"

  if [[ -z "$version" ]]; then
    printf 'Unable to resolve MARKETING_VERSION from %s.\n' "$PROJECT_PATH" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

increment_marketing_version() {
  local version="$1"
  local parts
  local last_index

  IFS='.' read -r -a parts <<< "$version"
  last_index=$((${#parts[@]} - 1))

  if [[ $last_index -lt 0 || ! "${parts[$last_index]}" =~ ^[0-9]+$ ]]; then
    printf 'Cannot auto-increment MARKETING_VERSION: %s\n' "$version" >&2
    return 1
  fi

  parts[$last_index]="$((10#${parts[$last_index]} + 1))"
  (IFS='.'; printf '%s\n' "${parts[*]}")
}

next_build_number_after() {
  local previous="$1"
  local candidate

  candidate="$(TZ=Asia/Shanghai date +%Y%m%d%H%M)"
  if [[ "$candidate" =~ ^[0-9]+$ && "$previous" =~ ^[0-9]+$ ]] && ((10#$candidate <= 10#$previous)); then
    printf '%s\n' "$((10#$previous + 1))"
  else
    printf '%s\n' "$candidate"
  fi
}

persist_project_marketing_version() {
  local version="$1"

  if [[ ! -f "$PROJECT_FILE" ]]; then
    printf 'Project file not found at %s.\n' "$PROJECT_FILE" >&2
    return 1
  fi

  /usr/bin/perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+)*;/MARKETING_VERSION = $version;/g" "$PROJECT_FILE"
}

is_closed_marketing_version_error() {
  local log_path="$1"

  grep -Eq \
    'Invalid Pre-Release Train|CFBundleShortVersionString .*must contain a higher version|code = 90186|code = 90062' \
    "$log_path"
}

MARKETING_VERSION_WAS_EXPLICIT="${MARKETING_VERSION+x}"
MARKETING_VERSION="${MARKETING_VERSION:-$(resolve_project_marketing_version)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(TZ=Asia/Shanghai date +%Y%m%d%H%M)}"
RELEASE_DIR="${PHOTO_DELETE_RELEASE_DIR:-/tmp/PhotoDeleteRelease}"
ARCHIVE_PATH="$RELEASE_DIR/PhotoDelete.xcarchive"
EXPORT_PATH="$RELEASE_DIR/export"
EXPORT_OPTIONS="$RELEASE_DIR/ExportOptions.plist"
SKIP_TESTS="${SKIP_TESTS:-0}"
AUTO_INCREMENT_MARKETING_VERSION="${AUTO_INCREMENT_MARKETING_VERSION:-1}"
MAX_MARKETING_VERSION_UPLOAD_ATTEMPTS="${MAX_MARKETING_VERSION_UPLOAD_ATTEMPTS:-2}"

if [[ "$SKIP_TESTS" != "1" ]]; then
  SIMULATOR_DESTINATION="$("$ROOT_DIR/scripts/resolve-ios-simulator-destination.sh")"
else
  SIMULATOR_DESTINATION=""
fi

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
  local archived_bundle_id
  local archived_marketing_version

  if [[ ! -f "$info_plist" ]]; then
    printf 'Archive Info.plist not found at %s.\n' "$info_plist" >&2
    return 1
  fi

  archived_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [[ "$archived_build_number" != "$BUILD_NUMBER" ]]; then
    printf 'Archive CFBundleVersion mismatch: expected %s, got %s.\n' "$BUILD_NUMBER" "$archived_build_number" >&2
    return 1
  fi

  archived_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  if [[ "$archived_bundle_id" != "$BUNDLE_ID" ]]; then
    printf 'Archive bundle identifier mismatch: expected %s, got %s.\n' "$BUNDLE_ID" "$archived_bundle_id" >&2
    return 1
  fi

  archived_marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  if [[ "$archived_marketing_version" != "$MARKETING_VERSION" ]]; then
    printf 'Archive marketing version mismatch: expected %s, got %s.\n' "$MARKETING_VERSION" "$archived_marketing_version" >&2
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

case "$AUTO_INCREMENT_MARKETING_VERSION" in
  0|1)
    ;;
  *)
    printf 'AUTO_INCREMENT_MARKETING_VERSION must be 0 or 1, got %s.\n' "$AUTO_INCREMENT_MARKETING_VERSION" >&2
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

archive_and_upload() {
  local export_log
  local archive_signing_args

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

  run_xcodebuild archive \
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
    return 0
  fi

  write_export_options

  export_log="$RELEASE_DIR/export-$MARKETING_VERSION-$BUILD_NUMBER.log"
  if ! run_xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates 2>&1 | tee "$export_log"; then
    if is_closed_marketing_version_error "$export_log"; then
      return 86
    fi
    return 1
  fi

  printf 'Uploaded PhotoDelete %s (%s) to App Store Connect/TestFlight.\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
}

attempt=1
while true; do
  status=0
  archive_and_upload || status=$?
  if [[ "$status" == "0" ]]; then
    exit 0
  fi

  if [[ "$status" == "86" &&
        "$AUTO_INCREMENT_MARKETING_VERSION" == "1" &&
        -z "$MARKETING_VERSION_WAS_EXPLICIT" &&
        "$attempt" -lt "$MAX_MARKETING_VERSION_UPLOAD_ATTEMPTS" ]]; then
    next_marketing_version="$(increment_marketing_version "$MARKETING_VERSION")"
    printf 'App Store Connect rejected MARKETING_VERSION %s. Retrying with %s.\n' "$MARKETING_VERSION" "$next_marketing_version" >&2
    persist_project_marketing_version "$next_marketing_version"
    MARKETING_VERSION="$next_marketing_version"
    BUILD_NUMBER="$(next_build_number_after "$BUILD_NUMBER")"
    attempt=$((attempt + 1))
    continue
  fi

  exit "$status"
done
