#!/usr/bin/env bash
# Build McFly for iPhone and iPad, and send it to TestFlight.
#
#   scripts/release-ios.sh             → build/ios/McFly.xcarchive, built and checked;
#                                         nothing leaves this Mac
#   scripts/release-ios.sh --upload    … then signed for the App Store and uploaded to
#                                         App Store Connect. TestFlight has it once Apple
#                                         has processed it, usually within minutes.
#
# What it builds is a commit, origin/main unless MCFLY_RELEASE_REF names another
# (a branch, a tag, HEAD), checked out on its own: never this checkout's files,
# which other work in progress shares. Only Config/Local.xcconfig comes from here.
#
# The version is MARKETING_VERSION in project.yml (or MCFLY_IOS_VERSION). The build
# number is the date and time, UTC (or MCFLY_IOS_BUILD), so each upload is newer
# than the last.
#
# Needs, once (README.md, "TestFlight"):
#   - Config/Local.xcconfig with the Supabase project's URL and anon key: a build
#     without them only says it isn't connected, so this refuses to make one
#   - McFly's voice, McFlyVoice/scripts/fetch-kokoro.sh (about 190 MB, not in git)
#   - Xcode, signed in to the developer account (Xcode → Settings → Accounts). It
#     makes the Apple Distribution certificate and the App Store profile itself.
#     Or an App Store Connect API key instead: MCFLY_ASC_KEY_ID and
#     MCFLY_ASC_ISSUER_ID, with the key at
#     ~/.appstoreconnect/private_keys/AuthKey_<MCFLY_ASC_KEY_ID>.p8 (or MCFLY_ASC_KEY_PATH)
#   - the app in App Store Connect, for the bundle ID com.bot.mcfly
#   - brew install xcodegen
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=0
[[ "${1:-}" == "--upload" ]] && UPLOAD=1

# Xcode, not just the command-line tools: the iOS SDK comes with it.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Needs Xcode, not just the command-line tools (or DEVELOPER_DIR set to it)." >&2
    exit 1
  fi
fi

# The team: MCFLY_TEAM_ID, else Local.xcconfig's, else the one this Mac signs with.
if [[ -z "${MCFLY_TEAM_ID:-}" && -f Config/Local.xcconfig ]]; then
  MCFLY_TEAM_ID="$(sed -nE 's/^[[:space:]]*MCFLY_TEAM_ID[[:space:]]*=[[:space:]]*([A-Z0-9]{10}).*/\1/p' Config/Local.xcconfig | tail -1)"
fi
if [[ -z "${MCFLY_TEAM_ID:-}" ]]; then
  MCFLY_TEAM_ID="$(security find-identity -v -p codesigning | sed -nE 's/.*\(([A-Z0-9]{10})\)"$/\1/p' | head -1)"
fi
if [[ -z "$MCFLY_TEAM_ID" ]]; then
  echo "Set MCFLY_TEAM_ID to your developer team's ID (developer.apple.com → Membership)." >&2
  exit 1
fi

# Date, then time: a later build compares greater, part by part.
NOW="$(date -u +%Y%m%d%H%M)"
BUILD_NUMBER="${MCFLY_IOS_BUILD:-${NOW:0:8}.$((10#${NOW:8:4}))}"

OUT="$PWD/build/ios"
ARCHIVE="$OUT/McFly.xcarchive"
APP="$ARCHIVE/Products/Applications/McFly.app"
rm -rf "$OUT" && mkdir -p "$OUT"

if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Config/Local.xcconfig is missing: the build needs the Supabase project (README.md, Configure)." >&2
  exit 1
fi

# The commit, checked out where nothing else is being edited.
REF="${MCFLY_RELEASE_REF:-origin/main}"
if [[ "$REF" == origin/* ]] && ! git fetch --quiet origin; then
  echo "Couldn't fetch origin to build $REF." >&2
  exit 1
fi
COMMIT="$(git rev-parse --short "$REF^{commit}")"
SRC="$(mktemp -d)/mcfly"
cleanup() { git worktree remove --force "$SRC" >/dev/null 2>&1 || true; rm -rf "$(dirname "$SRC")"; }
trap cleanup EXIT
git worktree add --detach --quiet "$SRC" "$REF"
cp Config/Local.xcconfig "$SRC/apple/Config/Local.xcconfig"
# McFly's voice: its model files aren't in git, so they come from this checkout,
# checked against their pinned hashes on the way. A build without them would
# quietly speak with the system voice.
KOKORO="$PWD/McFlyVoice/Sources/McFlyVoice/Kokoro"
if [[ ! -d "$KOKORO/coreml" ]]; then
  echo "McFly's voice files are missing: run McFlyVoice/scripts/fetch-kokoro.sh first." >&2
  exit 1
fi
(cd "$SRC/apple/McFlyVoice" && scripts/fetch-kokoro.sh --from "$KOKORO" >/dev/null)
(cd "$SRC/apple" && xcodegen generate --quiet)

# Built unsigned. Xcode would sign an archive for development, and a
# development profile for an iPhone app needs an iPhone registered to the
# team; the App Store signature is the export's to make, below.
xcodebuild archive -quiet -project "$SRC/apple/McFly.xcodeproj" -scheme McFly -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO MCFLY_TEAM_ID="$MCFLY_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ${MCFLY_IOS_VERSION:+MARKETING_VERSION="$MCFLY_IOS_VERSION"}

INFO="$APP/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true; }
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
# App Store Connect takes each build number once: it must be this upload's.
if [[ "$(plist CFBundleVersion)" != "$BUILD_NUMBER" ]]; then
  echo "The app's CFBundleVersion is $(plist CFBundleVersion), not $BUILD_NUMBER: Info.plist must take \$(CURRENT_PROJECT_VERSION)." >&2
  exit 1
fi

# A build that can't reach the backend is no use to a tester.
SUPABASE_URL="$(plist SupabaseURL)"
SUPABASE_KEY="$(plist SupabaseAnonKey)"
if [[ "$SUPABASE_URL" != https://*.* || "$SUPABASE_URL" == *YOUR-PROJECT* || -z "$SUPABASE_KEY" \
      || "$SUPABASE_KEY" == *'$('* || "$SUPABASE_KEY" == YOUR-ANON-KEY ]]; then
  echo "The build has no Supabase project: set SUPABASE_URL and SUPABASE_ANON_KEY in Config/Local.xcconfig." >&2
  exit 1
fi

# Then signed here, ad hoc, to carry the entitlements: the export signs for
# the App Store with the entitlements it finds on the archive, and an unsigned
# one has none. The app would lose its associated domain, and with it the
# https://mcfly.bot/pair links.
ENTITLEMENTS="$OUT/McFly.entitlements"
sed "s/[$](AppIdentifierPrefix)/$MCFLY_TEAM_ID./g" "$SRC/apple/McFly/McFly-iOS.entitlements" > "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :application-identifier string $MCFLY_TEAM_ID.$BUNDLE_ID" \
  -c "Add :com.apple.developer.team-identifier string $MCFLY_TEAM_ID" "$ENTITLEMENTS" >/dev/null
codesign --force --sign - --entitlements "$ENTITLEMENTS" --generate-entitlement-der "$APP"

# What App Store Connect would otherwise turn away after the upload.
if ! plutil -lint -s "$APP/PrivacyInfo.xcprivacy"; then
  echo "The app has no valid privacy manifest (McFly/PrivacyInfo.xcprivacy)." >&2
  exit 1
fi
if [[ ! -d "$APP/McFlyVoice_McFlyVoice.bundle/Kokoro/coreml" ]]; then
  echo "The archive has no Kokoro voice (McFlyVoice_McFlyVoice.bundle/Kokoro)." >&2
  exit 1
fi
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "applinks:mcfly.bot"; then
  echo "The archive is not signed with the associated domain." >&2
  exit 1
fi
# The APIs Apple wants a reason for, as the linked binary uses them (its own
# code and every package's): each needs its category in the privacy manifest.
BINARY="$APP/$(plist CFBundleExecutable)"
USES="$( { xcrun nm -u "$BINARY" 2>/dev/null; strings -a "$BINARY"; } | grep -oE \
  '_OBJC_CLASS_\$_NSUserDefaults|_mach_absolute_time|systemUptime|_(f|l)?stat(at|fs|vfs)?$|_f?getattrlist(bulk|at)?|attributesOfItemAtPath|NSFile(Creation|Modification)Date|NSURL(ContentModification|Creation)DateKey|NSFileSystem(Free)?Size|NSURLVolume(Available|Total)Capacity|activeInputModes' \
  | sort -u || true)"
declared="$(plutil -extract NSPrivacyAccessedAPITypes json -o - "$APP/PrivacyInfo.xcprivacy")"
missing=()
need() { [[ "$declared" == *"$1"* ]] || missing+=("$1 ($2)"); }
while IFS= read -r use; do
  case "$use" in
    "") ;;
    *NSUserDefaults*) need NSPrivacyAccessedAPICategoryUserDefaults "$use" ;;
    *mach_absolute_time*|*systemUptime*) need NSPrivacyAccessedAPICategorySystemBootTime "$use" ;;
    *Capacity*|*FileSystem*|*statfs*|*statvfs*) need NSPrivacyAccessedAPICategoryDiskSpace "$use" ;;
    *activeInputModes*) need NSPrivacyAccessedAPICategoryActiveKeyboards "$use" ;;
    *) need NSPrivacyAccessedAPICategoryFileTimestamp "$use" ;;
  esac
done <<< "$USES"
if (( ${#missing[@]} )); then
  printf 'The privacy manifest gives no reason for:\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "Built McFly $VERSION ($BUILD_NUMBER) from $COMMIT ($REF) for iOS, against $SUPABASE_URL: $ARCHIVE"

if [[ "$UPLOAD" != "1" ]]; then
  echo "Nothing was sent. scripts/release-ios.sh --upload sends a build to TestFlight."
  exit 0
fi

AUTH=()
if [[ -n "${MCFLY_ASC_KEY_ID:-}" ]]; then
  KEY="${MCFLY_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$MCFLY_ASC_KEY_ID.p8}"
  if [[ ! -f "$KEY" || -z "${MCFLY_ASC_ISSUER_ID:-}" ]]; then
    echo "MCFLY_ASC_KEY_ID needs MCFLY_ASC_ISSUER_ID too, and the key at $KEY." >&2
    exit 1
  fi
  AUTH=(-authenticationKeyPath "$KEY" -authenticationKeyID "$MCFLY_ASC_KEY_ID"
        -authenticationKeyIssuerID "$MCFLY_ASC_ISSUER_ID")
fi

# The build number is ours (above), not Xcode's to change on the way up.
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$MCFLY_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

# Signs for the App Store, registering the bundle ID and making the
# certificate and profile the first time, and uploads.
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "Uploaded McFly $VERSION ($BUILD_NUMBER) from $COMMIT. It shows in App Store Connect → TestFlight once processed."
