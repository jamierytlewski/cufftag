#!/usr/bin/env bash
# ==============================================================================
# CuffTag — One-Command TestFlight / App Store Connect Release Script
# ==============================================================================
# Usage:
#   ./CuffTag/scripts/release-testflight.sh [options]
#
# Options:
#   --version <x.y.z>   Set marketing version (CFBundleShortVersionString)
#   --build <num>       Set explicit build number (CFBundleVersion)
#   --no-bump           Do not auto-increment CFBundleVersion before archiving
#   --team <TEAM_ID>    Override Apple Developer Team ID
#   --internal-only     Restrict build to Internal TestFlight testers only
#   --archive-only      Build & sign the .xcarchive locally without uploading
#   --export-ipa        Export a signed .ipa to CuffTag/build/export instead of uploading
#   -h, --help          Show this help message
#
# Authentication (two supported modes):
#   1. Xcode Account (default, zero setup):
#      Uses the Apple ID already signed into Xcode > Settings > Accounts.
#   2. App Store Connect API Key (optional, completely headless):
#      Set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (or place key at
#      ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8).
#      You can also save these in .env.testflight at the repo root.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUFFTAG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CUFFTAG_DIR}/.." && pwd)"

PROJECT_PATH="${CUFFTAG_DIR}/CuffTag.xcodeproj"
SCHEME="CuffTag"
INFO_PLIST="${CUFFTAG_DIR}/CuffTag/Info.plist"
PROJECT_YML="${CUFFTAG_DIR}/project.yml"
BUILD_DIR="${CUFFTAG_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/CuffTag.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
GENERATED_EXPORT_PLIST="${BUILD_DIR}/ExportOptions.generated.plist"

# Load optional .env.testflight if present
if [[ -f "${REPO_ROOT}/.env.testflight" ]]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.env.testflight"
fi

BUMP_BUILD=true
EXPLICIT_VERSION=""
EXPLICIT_BUILD=""
TEAM_ID="${TEAM_ID:-}"
INTERNAL_ONLY=false
MODE="upload" # upload | archive-only | export-ipa

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      EXPLICIT_VERSION="$2"
      shift 2
      ;;
    --build)
      EXPLICIT_BUILD="$2"
      BUMP_BUILD=false
      shift 2
      ;;
    --no-bump)
      BUMP_BUILD=false
      shift
      ;;
    --team)
      TEAM_ID="$2"
      shift 2
      ;;
    --internal-only)
      INTERNAL_ONLY=true
      shift
      ;;
    --archive-only)
      MODE="archive-only"
      shift
      ;;
    --export-ipa)
      MODE="export-ipa"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# 1. Detect Team ID from project.pbxproj if not explicitly provided
if [[ -z "${TEAM_ID}" ]]; then
  TEAM_ID="$(grep -m1 'DEVELOPMENT_TEAM = ' "${PROJECT_PATH}/project.pbxproj" | sed -E 's/.*DEVELOPMENT_TEAM = ([A-Z0-9]+);.*/\1/' || true)"
fi

if [[ -z "${TEAM_ID}" ]]; then
  echo "Error: Could not determine DEVELOPMENT_TEAM. Pass --team <YOUR_TEAM_ID> or set TEAM_ID." >&2
  exit 1
fi

# 2. Read & update version / build number
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}")"

TARGET_VERSION="${EXPLICIT_VERSION:-${CURRENT_VERSION}}"
if [[ -n "${EXPLICIT_BUILD}" ]]; then
  TARGET_BUILD="${EXPLICIT_BUILD}"
elif [[ "${BUMP_BUILD}" == "true" ]]; then
  if [[ "${CURRENT_BUILD}" =~ ^[0-9]+$ ]]; then
    TARGET_BUILD="$((CURRENT_BUILD + 1))"
  else
    TARGET_BUILD="$(date +%Y%m%d%H%M)"
  fi
else
  TARGET_BUILD="${CURRENT_BUILD}"
fi

if [[ "${TARGET_VERSION}" != "${CURRENT_VERSION}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${TARGET_VERSION}" "${INFO_PLIST}"
  if [[ -f "${PROJECT_YML}" ]]; then
    sed -i '' -E "s/(CFBundleShortVersionString: \")[^\"]+(\")/\1${TARGET_VERSION}\2/" "${PROJECT_YML}"
  fi
fi

if [[ "${TARGET_BUILD}" != "${CURRENT_BUILD}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${TARGET_BUILD}" "${INFO_PLIST}"
  if [[ -f "${PROJECT_YML}" ]]; then
    sed -i '' -E "s/(CFBundleVersion: \")[^\"]+(\")/\1${TARGET_BUILD}\2/" "${PROJECT_YML}"
  fi
fi

BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER = ' "${PROJECT_PATH}/project.pbxproj" | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/' | tr -d ' "')"

echo "=================================================================="
echo " CuffTag Release Pipeline"
echo "------------------------------------------------------------------"
echo " Bundle ID : ${BUNDLE_ID}"
echo " Team ID   : ${TEAM_ID}"
echo " Version   : ${TARGET_VERSION} (build ${TARGET_BUILD})"
echo " Mode      : ${MODE}"
echo "=================================================================="

# 3. Configure App Store Connect authentication flags
AUTH_FLAGS=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  ASC_KEY_PATH="${ASC_KEY_PATH:-${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  if [[ ! -f "${ASC_KEY_PATH}" ]]; then
    echo "Error: ASC_KEY_ID was set, but private key file was not found at: ${ASC_KEY_PATH}" >&2
    exit 1
  fi
  echo "Using App Store Connect API Key (${ASC_KEY_ID})..."
  AUTH_FLAGS+=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
else
  echo "Using Apple ID signed into Xcode > Settings > Accounts..."
fi

# 4. Prepare clean build folder & ExportOptions.plist
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
mkdir -p "${BUILD_DIR}"

EXPORT_DEST="upload"
if [[ "${MODE}" == "export-ipa" ]]; then
  EXPORT_DEST="export"
fi

cat > "${GENERATED_EXPORT_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>${EXPORT_DEST}</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<true/>
	<key>testFlightInternalTestingOnly</key>
	<$( [[ "${INTERNAL_ONLY}" == "true" ]] && echo "true" || echo "false" )/>
</dict>
</plist>
EOF

# 5. Archive the Release build for generic iOS device
echo ""
echo "-> Step 1/2: Archiving ${SCHEME} (${TARGET_VERSION} #${TARGET_BUILD})..."
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CURRENT_PROJECT_VERSION="${TARGET_BUILD}" \
  MARKETING_VERSION="${TARGET_VERSION}" \
  "${AUTH_FLAGS[@]}"

echo "Archive created at: ${ARCHIVE_PATH}"

if [[ "${MODE}" == "archive-only" ]]; then
  echo ""
  echo "Done (--archive-only). To open in Xcode Organizer:"
  echo "  open \"${ARCHIVE_PATH}\""
  exit 0
fi

# 6. Export & Upload to App Store Connect / TestFlight
echo ""
if [[ "${MODE}" == "upload" ]]; then
  echo "-> Step 2/2: Uploading archive to App Store Connect / TestFlight..."
else
  echo "-> Step 2/2: Exporting signed .ipa to ${EXPORT_DIR}..."
fi

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${GENERATED_EXPORT_PLIST}" \
  -exportPath "${EXPORT_DIR}" \
  "${AUTH_FLAGS[@]}"

echo ""
echo "=================================================================="
if [[ "${MODE}" == "upload" ]]; then
  echo " Upload complete! CuffTag ${TARGET_VERSION} (${TARGET_BUILD}) is now"
  echo " processing on App Store Connect."
  echo ""
  echo " - Processing usually takes 5-15 minutes."
  echo " - Since ITSAppUsesNonExemptEncryption=false is already set in"
  echo "   Info.plist, Internal TestFlight testers will receive the build"
  echo "   automatically as soon as processing finishes."
  echo " - Check status: https://appstoreconnect.apple.com/apps"
else
  echo " Export complete! Signed .ipa is in: ${EXPORT_DIR}"
fi
echo "=================================================================="
