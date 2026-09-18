#!/bin/bash
# Cuts a release: bumps the version, builds, zips, signs the zip with the
# Sparkle key in your Keychain, and prepends the item to appcast.xml.
#
#   ./scripts/release.sh 1.1 [-m "What changed"] [--dry-run]
#
# It never touches git or GitHub. It ends by printing the three steps that
# do, in the order that keeps installed copies from seeing a 404.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Duarte0903/Ascend"
usage() { echo "usage: $0 <version> [-m notes] [--dry-run]" >&2; exit 2; }

VERSION="" NOTES="" DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) NOTES="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) usage ;;
    *) [[ -z "$VERSION" ]] && VERSION="$1" || usage; shift ;;
  esac
done
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "version must look like 1.2 or 1.2.3" >&2; exit 2; }

# --- Versions live in project.yml only -------------------------------------
current=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
[[ -n "$current" && -n "$build" ]] || { echo "could not read versions from project.yml" >&2; exit 1; }
if [[ "$VERSION" == "$current" ]]; then
  echo "version $VERSION is already the current version; pick a new one" >&2; exit 1
fi
next_build=$((build + 1))

# --- Sparkle's tools ship inside the SPM artifact -----------------------------
find_tools() { find build/SourcePackages/artifacts -type d -name bin 2>/dev/null | grep -i sparkle | head -1; }
BIN=$(find_tools)
if [[ -z "$BIN" ]]; then
  echo "Sparkle tools not found; building once to resolve the package…"
  ./scripts/build.sh >/dev/null
  BIN=$(find_tools)
fi
[[ -n "$BIN" ]] || { echo "Sparkle's bin/ directory not found under build/SourcePackages/artifacts" >&2; exit 1; }

# --- Signing key: one-time --------------------------------------------------
if ! PUBKEY=$("$BIN/generate_keys" -p 2>/dev/null); then
  echo "No Sparkle signing key in your Keychain yet. Generating one…"
  "$BIN/generate_keys"
  PUBKEY=$("$BIN/generate_keys" -p)
  echo
  echo "Put this public key in project.yml as SUPublicEDKey, then run again:"
  echo "  $PUBKEY"
  exit 1
fi
if ! grep -q "SUPublicEDKey: \"$PUBKEY\"" project.yml; then
  echo "project.yml's SUPublicEDKey does not match the key in your Keychain:" >&2
  echo "  $PUBKEY" >&2
  exit 1
fi

# --- Bump, build, zip ----------------------------------------------------------
sed -i '' "s/^\( *MARKETING_VERSION: \)\".*\"/\1\"$VERSION\"/" project.yml
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \)\".*\"/\1\"$next_build\"/" project.yml
echo "Version $current ($build) → $VERSION ($next_build)"

./scripts/build.sh
APP="build/Build/Products/Release/Ascend.app"
mkdir -p build/release
ZIP="build/release/Ascend-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# --- Sign and record ---------------------------------------------------------
SIGNED=$("$BIN/sign_update" "$ZIP")             # sparkle:edSignature="…" length="…"
SIG=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNED")
LEN=$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGNED")
[[ -n "$SIG" && -n "$LEN" ]] || { echo "sign_update gave unexpected output: $SIGNED" >&2; exit 1; }

URL="https://github.com/$REPO/releases/download/v$VERSION/Ascend-$VERSION.zip"
python3 scripts/appcast.py add --version "$VERSION" --build "$next_build" \
  --url "$URL" --length "$LEN" --signature "$SIG" --notes "$NOTES"

# --- Hand-off ---------------------------------------------------------------------
cat <<EOM

Release $VERSION is built and signed:
  $ZIP
  appcast.xml updated, project.yml bumped to $VERSION ($next_build)
EOM
if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry run: project.yml and appcast.xml were modified; discard them if this was only a test)"
  exit 0
fi
NOTES_ARG=""
[[ -n "$NOTES" ]] && NOTES_ARG=" --notes \"$NOTES\""
cat <<EOM

Now, in this order (the appcast must not go public before the zip exists):

  1. Publish the release with the zip attached:
       gh release create v$VERSION "$ZIP" --title "Ascend $VERSION"$NOTES_ARG

  2. Commit the version and the feed:
       git add project.yml appcast.xml && git commit -m "Release $VERSION"

  3. git push
EOM
