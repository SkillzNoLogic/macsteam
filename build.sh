#!/bin/bash
# Builds ONE app that contains macSteam and NotProton 1.2.6.
#
#   ./build.sh                          (uses /Applications/NotProton.app for NotProton's prebuilt parts)
#   ./build.sh --notproton-app PATH     (PATH = a NotProton 1.2.6 .app, or the NotProton.zip you downloaded)
#
# Result: dist/macSteam.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

NP_TAG="v1.2.6"
NP_VERSION="1.2.6"
NP_REPO="https://github.com/NotProtonNot/NotProton.git"
NP_DIR="$ROOT/notproton"
APP_FILE="macSteam.app"
DIST="$ROOT/dist"

NP_SOURCE_APP=""
BUILD_PAYLOAD_FROM_SOURCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --notproton-app) NP_SOURCE_APP="${2:-}"; shift 2 ;;
        --payload-from-source) BUILD_PAYLOAD_FROM_SOURCE=1; shift ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

say()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. checks
say "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || die "This has to be run on a Mac."
[ "$(uname -m)" = "arm64" ]  || die "macSteam and NotProton both need an Apple Silicon Mac."
command -v git   >/dev/null || die "git is missing. Run: xcode-select --install"
command -v clang >/dev/null || die "Apple's developer tools are missing. Run: xcode-select --install"
command -v swift >/dev/null || die "Swift is missing. Install Xcode 26 (free, App Store) and open it once."
command -v cmake >/dev/null || die "cmake is missing. Install Homebrew (brew.sh) and run: brew install cmake"

SWIFT_VER="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)"
SWIFT_MAJOR="${SWIFT_VER%% *}"; SWIFT_MINOR="${SWIFT_VER##* }"
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ] || { [ "$SWIFT_MAJOR" -eq 6 ] && [ "$SWIFT_MINOR" -lt 2 ]; }; then
    die "Swift 6.2 or newer is needed (you have: ${SWIFT_VER:-unknown}). Update to Xcode 26 and run: sudo xcode-select -s /Applications/Xcode.app"
fi
if ! xcrun --find xcstringstool >/dev/null 2>&1; then
    die "You have Apple's small 'Command Line Tools' but not the full Xcode app, and NotProton's translations need Xcode. Install Xcode 26 from the App Store, open it once and accept the licence, then run in Terminal:  sudo xcode-select -s /Applications/Xcode.app  and try again."
fi
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || die "macOS 15 or newer is needed."

# ---------------------------------------------------------------- 2. NotProton source
say "Getting NotProton $NP_VERSION source"
# The sources ship with this repository; a bare checkout from before they were
# added still fetches them, so both kinds of working copy build.
if [ ! -d "$NP_DIR" ]; then
    git clone --depth 1 --branch "$NP_TAG" "$NP_REPO" "$NP_DIR"
fi
if [ ! -f "$NP_DIR/app/Sources/NotProtonApp/Embed.swift" ]; then
    git -C "$NP_DIR" apply "$ROOT/patches/notproton-1.2.6.patch" \
        || die "Couldn't apply the NotProton patch. Delete the 'notproton' folder and run this again."
    echo "Applied the macSteam integration patch to NotProton."
else
    echo "NotProton source already patched."
fi

# ---------------------------------------------------------------- 3. NotProton prebuilt parts
PAYLOAD_DEST="$NP_DIR/app/Sources/NotProtonApp/Resources/payload"
if [ "$BUILD_PAYLOAD_FROM_SOURCE" -eq 1 ]; then
    say "Building NotProton's components from source (slow; this is the advanced path)"
    ( cd "$NP_DIR" && make bridge fonts app-payload )
else
    say "Taking NotProton's prebuilt components from a NotProton $NP_VERSION app"
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    if [ -z "$NP_SOURCE_APP" ]; then
        for c in /Applications/NotProton.app "$HOME/Applications/NotProton.app" \
                 "$ROOT"/NotProton*.zip "$HOME"/Downloads/NotProton*.zip; do
            [ -e "$c" ] && { NP_SOURCE_APP="$c"; break; }
        done
    fi
    if [ -z "$NP_SOURCE_APP" ] && [ -f "$PAYLOAD_DEST/notproton.dylib" ]; then
        echo "No NotProton $NP_VERSION app found; reusing the components already in $PAYLOAD_DEST."
    else
    [ -n "$NP_SOURCE_APP" ] || die "I couldn't find NotProton $NP_VERSION. Download NotProton.zip from https://github.com/NotProtonNot/NotProton/releases (version $NP_VERSION), then run: ./build.sh --notproton-app ~/Downloads/NotProton.zip"
    case "$NP_SOURCE_APP" in
        *.zip) ditto -x -k "$NP_SOURCE_APP" "$TMP/x"; NP_SOURCE_APP="$(find "$TMP/x" -maxdepth 2 -name '*.app' | head -1)" ;;
    esac
    [ -d "$NP_SOURCE_APP" ] || die "Not an app: $NP_SOURCE_APP"
    FOUND="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NP_SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
    [ "$FOUND" = "$NP_VERSION" ] || die "That NotProton is version '${FOUND:-unknown}', but this build needs exactly $NP_VERSION. Download $NP_VERSION from the NotProton releases page and use --notproton-app."
    SRC_PAYLOAD="$NP_SOURCE_APP/Contents/Resources/NotProtonApp_NotProtonApp.bundle/Contents/Resources/payload"
    [ -d "$SRC_PAYLOAD" ] || die "That NotProton app doesn't contain the expected components folder."
    mkdir -p "$PAYLOAD_DEST"
    # The prebuilt NotProton runner joins its arguments with "$*", which splits a
    # game path that contains spaces and hides OnlineFix from the loader scan. Keep
    # the runner from this source tree, which captures the executable argument whole.
    KEEP_RUNNER="$TMP/run.macsteam"
    cp "$PAYLOAD_DEST/run" "$KEEP_RUNNER" 2>/dev/null || true
    rsync -a --delete "$SRC_PAYLOAD/" "$PAYLOAD_DEST/"
    if [ -f "$KEEP_RUNNER" ]; then
        cp "$KEEP_RUNNER" "$PAYLOAD_DEST/run"
        chmod +x "$PAYLOAD_DEST/run"
    fi
    echo "Copied components from: $NP_SOURCE_APP"
    fi
fi
[ -f "$PAYLOAD_DEST/notproton.dylib" ] || die "NotProton's components are incomplete (notproton.dylib missing)."
# The payload folder is ignored in this repository, so the patch is what a fresh
# checkout has. Applying it to an already-fixed runner is a no-op.
RUNNER_PATCH="$ROOT/patches/notproton-run-whole-path.patch"
if [ -f "$RUNNER_PATCH" ]; then
    ( cd "$PAYLOAD_DEST" && patch -p1 -N -f < "$RUNNER_PATCH" >/dev/null 2>&1 ) || true
    rm -f "$PAYLOAD_DEST/run.rej" "$PAYLOAD_DEST/run.orig"
fi
RUNNER_NESTED_PATCH="$ROOT/patches/notproton-run-nested-onlinefix.patch"
if [ -f "$RUNNER_NESTED_PATCH" ]; then
    ( cd "$PAYLOAD_DEST" && patch -p1 -N -f < "$RUNNER_NESTED_PATCH" >/dev/null 2>&1 ) || true
    rm -f "$PAYLOAD_DEST/run.rej" "$PAYLOAD_DEST/run.orig"
fi
grep -q 'np_launch_exe=' "$PAYLOAD_DEST/run"     || die "The NotProton runner is missing the whole-path launch fix."
grep -q 'np_nested_onlinefix' "$PAYLOAD_DEST/run" || die "The NotProton runner is missing the nested OnlineFix scan."

# ---------------------------------------------------------------- 4. macSteam dylib
say "Building macSteam's dylib (this downloads and compiles Dobby, a few minutes the first time)"
make rebuild
[ -f out/macsteam.dylib ] || die "macSteam's dylib didn't build."

# ---------------------------------------------------------------- 5. the app
say "Compiling the combined app (first time downloads Sparkle, a few minutes)"
( cd macsteam-app && swift build -c release )
BIN_DIR="$(cd macsteam-app && swift build -c release --show-bin-path)"
[ -x "$BIN_DIR/MacsteamApp" ] || die "The app didn't compile."

say "Assembling $APP_FILE"
APP="$DIST/$APP_FILE"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_DIR/MacsteamApp" "$APP/Contents/MacOS/MacsteamApp"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MacsteamApp"
cp macsteam-app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# macSteam's own resource bundle (the Store button's script, etc.)
MS_BUNDLE="$BIN_DIR/MacsteamApp_MacsteamApp.bundle"
[ -d "$MS_BUNDLE" ] || die "macSteam's resource bundle wasn't produced by the build."
cp -R "$MS_BUNDLE" "$APP/Contents/Resources/"

# macSteam's parts
cp out/macsteam.dylib "$APP/Contents/Resources/macsteam.dylib"
MS_VERSION="$(sed -n 's/.*MACSTEAM_VERSION[[:space:]]*"\(.*\)".*/\1/p' src/version.h)"
printf '%s' "$MS_VERSION" > "$APP/Contents/Resources/macsteam.dylib.version"
cp -R signatures "$APP/Contents/Resources/signatures"

# NotProton's parts: its resource bundle (holds the components) and its translations
NP_BUNDLE="$BIN_DIR/NotProtonApp_NotProtonApp.bundle"
[ -d "$NP_BUNDLE" ] || die "NotProton's resource bundle wasn't produced by the build."
cp -R "$NP_BUNDLE" "$APP/Contents/Resources/"
for lproj in "$NP_BUNDLE"/Contents/Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
[ -f "$APP/Contents/Resources/NotProtonApp_NotProtonApp.bundle/Contents/Resources/payload/notproton.dylib" ] \
    || die "NotProton's components didn't make it into the app."

# OnlineFix Manager's parts: My Games and Add Games are compiled into the app; its
# dylib, 7-Zip and Steam build profiles are installed by the OnlineFix script.
say "Building CloudRedirect's cloud runtime"
"$ROOT/scripts/build-cloudredirect.sh" "$APP"

"$ROOT/scripts/build-onlinefix.sh" "$APP"

# Sparkle: the updater framework (feed and key are set in Info.plist below)
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
    ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
else
    SPARKLE_FW="$(find macsteam-app/.build/artifacts -type d -name Sparkle.framework -path '*macos*' | head -1)"
    [ -n "$SPARKLE_FW" ] || die "Couldn't find Sparkle.framework."
    ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
fi

NP_APP_VERSION="$(sed -n 's/^#define NOTPROTON_VERSION "\(.*\)"/\1/p' "$NP_DIR/dylib/version.h")"
# Automatic updates (Sparkle). The feed is the appcast.xml that
# .github/workflows/mirror-upstream.yml keeps; every update in it is signed with
# the private key whose public half is below. Override either to point a build
# at another feed, or set MACSTEAM_FEED_URL="" to build without updates.
SPARKLE_FEED_URL="${MACSTEAM_FEED_URL-https://raw.githubusercontent.com/SkillzNoLogic/macsteam/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="${MACSTEAM_SPARKLE_PUBLIC_KEY:-+nMQRgEWAndy7FprSQjv4Ef2iIc/cgDJD5E86hJPwFc=}"
SPARKLE_PLIST=""
if [ -n "$SPARKLE_FEED_URL" ]; then
    SPARKLE_PLIST="<key>SUFeedURL</key> <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key> <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key> <true/>"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>macSteam</string>
    <key>CFBundleDisplayName</key>        <string>macSteam</string>
    <key>CFBundleIdentifier</key>         <string>com.macsteam.app</string>
    <key>CFBundleExecutable</key>         <string>MacsteamApp</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>de</string><string>fr</string><string>it</string><string>zh-Hans</string></array>
    <key>CFBundleShortVersionString</key> <string>$MS_VERSION</string>
    <key>CFBundleVersion</key>            <string>$MS_VERSION</string>
    $SPARKLE_PLIST
    <key>NotProtonVersion</key>           <string>$NP_APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>26.0</string>
    <key>LSApplicationCategoryType</key>  <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>   <string>macSteam/CloudRedirect © 2026 Selectively11/ElfariaKensington. NotProton © NotProtonNot. Achievements, merging and others by Falhoo.</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSRemovableVolumesUsageDescription</key> <string>macSteam installs and removes game fixes in game folders on external drives.</string>
    <key>NSNetworkVolumesUsageDescription</key> <string>macSteam installs and removes game fixes in game folders on network drives.</string>
    <key>NSDesktopFolderUsageDescription</key> <string>macSteam installs and removes game fixes in game folders you keep on the Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key> <string>macSteam installs and removes game fixes in game folders you keep in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key> <string>macSteam installs and removes game fixes in game folders you keep in Downloads.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key> <true/>
        <key>NSExceptionDomains</key>
        <dict>
            <!-- LuaTools' public source checker is HTTP-only. -->
            <key>167.235.229.108</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key> <true/>
            </dict>
        </dict>
    </dict>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
</dict>
</plist>
PLIST
echo "APPL????" > "$APP/Contents/PkgInfo"

# Copy the license files that go with the code that's inside
mkdir -p "$APP/Contents/Resources/Licenses"
[ -f LICENSE ] && cp LICENSE "$APP/Contents/Resources/Licenses/LICENSE.macsteam" || echo "Note: no LICENSE file at the top of the project; skipped."
for f in LICENSE NOTICE LICENSE.lsteamclient LICENSE.steam-shim LICENSE.fonts; do
    [ -f "$NP_DIR/$f" ] && cp "$NP_DIR/$f" "$APP/Contents/Resources/Licenses/${f}.notproton"
done

xattr -cr "$APP" 2>/dev/null || true
codesign -f -s - "$APP"
codesign --verify --strict "$APP"

say "Done"
echo "Built: $APP"
echo
echo "Next: drag it into your Applications folder, open it, and use Install."
