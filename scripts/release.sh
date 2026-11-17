#!/bin/zsh
# Build a release zip plus the Sparkle appcast that installed copies read.
# Usage: scripts/release.sh 1.8.0
# Then: gh release create v1.8.0 build/release/DullNotch-1.8.0.zip build/release/appcast.xml
# Needs the EdDSA private key in secrets/sparkle_ed_key (not the Keychain: reading it from there
# shows a dialog and Keychain Access crashes on that item). Lose the key and installed copies stop updating.
KEY=secrets/sparkle_ed_key  # git-ignored; spare copy in ~/.config/dullnotch/
set -euo pipefail
VERSION=$1
REPO=jimmyxan/DullNotch-Notch-Enhanced
cd "${0:A:h}/.."
OUT=build/release
DD=${DERIVED_DATA:-$TMPDIR/dullnotch-release}

# Sparkle compares CFBundleVersion, so the build number must grow with every release.
BUILD=$(( $(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' boringNotch.xcodeproj/project.pbxproj | grep -o '[0-9]*$') + 1 ))
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/; s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $VERSION;/" boringNotch.xcodeproj/project.pbxproj

xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath "$DD" ENABLE_HARDENED_RUNTIME=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

rm -rf $OUT && mkdir -p $OUT
ditto -c -k --sequesterRsrc --keepParent "$DD/Build/Products/Release/DullNotch.app" "$OUT/DullNotch-$VERSION.zip"
"$DD/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" --ed-key-file $KEY \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" -o "$OUT/appcast.xml" $OUT
grep -q "sparkle:edSignature" $OUT/appcast.xml
echo "OK: $OUT/DullNotch-$VERSION.zip (build $BUILD) + appcast.xml"
