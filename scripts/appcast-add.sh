#!/bin/bash
# Sign a release DMG for Sparkle and put it at the top of appcast.xml, the feed
# the app checks for automatic updates.
#
#   ./scripts/appcast-add.sh DMG VERSION DOWNLOAD_URL [NOTES_FILE]
#
# The private key comes from $SPARKLE_KEY_FILE when set (CI), otherwise from the
# "macsteam-fork" account in your login Keychain (made by Sparkle's generate_keys).
# NOTES_FILE is plain text or Markdown; it is shown as-is in the update window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:?DMG path}"
VERSION="${2:?version, e.g. 0.8.10}"
URL="${3:?download URL}"
NOTES_FILE="${4:-}"
APPCAST="${APPCAST:-$ROOT/appcast.xml}"

SIGN_UPDATE="${SIGN_UPDATE:-$(find "$ROOT/macsteam-app/.build/artifacts" -path '*Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)}"
[ -x "$SIGN_UPDATE" ] || { echo "error: Sparkle's sign_update not found; run ./build.sh first or set SIGN_UPDATE" >&2; exit 1; }
[ -f "$DMG" ] || { echo "error: $DMG is missing" >&2; exit 1; }

if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
    SIG_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG")"
else
    SIG_ATTRS="$("$SIGN_UPDATE" --account macsteam-fork "$DMG")"
fi
# sign_update prints: sparkle:edSignature="..." length="..."
SIGNATURE="$(printf '%s' "$SIG_ATTRS" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIG_ATTRS" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
[ -n "$SIGNATURE" ] && [ -n "$LENGTH" ] || { echo "error: sign_update gave no signature: $SIG_ATTRS" >&2; exit 1; }

python3 -I - "$APPCAST" "$VERSION" "$URL" "$SIGNATURE" "$LENGTH" "$NOTES_FILE" <<'PY'
import html, sys
from email.utils import formatdate

appcast, version, url, signature, length, notes_file = sys.argv[1:7]
notes = open(notes_file, encoding="utf-8").read().strip() if notes_file else ""
notes = notes or f"macSteam {version}"
body = f'<div style="white-space: pre-wrap">{html.escape(notes)}</div>'

text = open(appcast, encoding="utf-8").read()
if f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in text:
    sys.exit(f"appcast.xml already lists {version}")

item = f"""    <item>
      <title>Version {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{body}]]></description>
      <enclosure url="{html.escape(url, quote=True)}"
                 type="application/octet-stream"
                 sparkle:edSignature="{signature}"
                 length="{length}" />
    </item>
"""
anchor = text.find("    <item>")
if anchor < 0:
    anchor = text.find("  </channel>")
if anchor < 0:
    sys.exit("appcast.xml has no <channel>")
open(appcast, "w", encoding="utf-8").write(text[:anchor] + item + text[anchor:])
print(f"appcast.xml: added {version}")
PY
