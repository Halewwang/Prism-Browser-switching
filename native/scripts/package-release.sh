#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "usage: $0 <version> <build>"
  exit 64
fi

version="$1"
build="$2"
for required in DEVELOPER_ID_APPLICATION DEVELOPMENT_TEAM NOTARY_PROFILE SPARKLE_PUBLIC_ED_KEY SPARKLE_ED_PRIVATE_KEY SPARKLE_TOOLS_ROOT; do
  [[ -n "${(P)required:-}" ]] || {
    print -u2 "missing required environment value: $required"
    exit 78
  }
done

script_dir="${0:A:h}"
native_root="${script_dir:h}"
tools_root="${SPARKLE_TOOLS_ROOT:A}"
generate_appcast="$tools_root/bin/generate_appcast"
verify_release="$script_dir/verify-release.sh"
output_root="$native_root/build/release/$version-$build"
archive="$output_root/Prism.xcarchive"
export_dir="$output_root/export"
appcast_input="$output_root/appcast-input"
appcast="$output_root/appcast.xml"
dmg="$output_root/Prism-$version.dmg"

[[ -x "$generate_appcast" ]] || {
  print -u2 "Sparkle generate_appcast is not executable under SPARKLE_TOOLS_ROOT"
  exit 69
}
[[ -x "$verify_release" ]] || {
  print -u2 "release verifier is not executable: $verify_release"
  exit 69
}
[[ ! -e "$output_root" ]] || {
  print -u2 "release output already exists: $output_root"
  exit 73
}

mkdir -p "$output_root"
runtime_export_options="$output_root/ExportOptions.plist"
cp "$native_root/Config/ExportOptions.plist" "$runtime_export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$runtime_export_options"

cd "$native_root"
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Release \
  -configuration Release -archivePath "$archive" archive \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$runtime_export_options"

app="$export_dir/Prism.app"
[[ -d "$app" ]] || {
  print -u2 "export did not produce Prism.app"
  exit 65
}
ditto -c -k --keepParent "$app" "$output_root/Prism-notary.zip"
xcrun notarytool submit "$output_root/Prism-notary.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
hdiutil create -volname Prism -srcfolder "$app" -ov -format UDZO "$dmg"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
zsh "$verify_release" "$app" "$version" "$build" "$dmg"

mkdir "$appcast_input"
cp "$dmg" "$appcast_input/"
print -rn -- "$SPARKLE_ED_PRIVATE_KEY" | "$generate_appcast" --ed-key-file - "$appcast_input" > "$appcast"
[[ -s "$appcast" ]] || {
  print -u2 "Sparkle did not generate an appcast"
  exit 65
}
print "Verified release artifacts are in: $output_root"
