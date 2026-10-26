#!/usr/bin/env bash
set -euo pipefail
mode="${1:-both}"
case "$mode" in
  device|both) ;;
  *) echo "Expected device or both" >&2; exit 2 ;;
esac
wrapper=Thirdparty/LibTorrent-Swift
export BOOST_ROOT="$(brew --prefix boost)"
export BOOST_INCLUDEDIR="$BOOST_ROOT/include"
test -f "$BOOST_INCLUDEDIR/boost/version.hpp"
bash "$wrapper/make.sh"
xcodebuild -project "$wrapper/LibTorrent.xcodeproj" -scheme LibTorrent \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$wrapper/DerivedData" BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO build
if [[ "$mode" == both ]]; then
  xcodebuild -project "$wrapper/LibTorrent.xcodeproj" -scheme LibTorrent \
    -configuration Release -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$wrapper/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    EXCLUDED_ARCHS=x86_64 BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO build
fi
mkdir -p "$wrapper/Build"
for framework in LibTorrent OpenSSL; do
  arguments=(-framework "$wrapper/DerivedData/Build/Products/Release-iphoneos/$framework.framework")
  if [[ "$mode" == both ]]; then
    arguments+=(-framework "$wrapper/DerivedData/Build/Products/Release-iphonesimulator/$framework.framework")
  fi
  xcodebuild -create-xcframework "${arguments[@]}" -output "$wrapper/Build/$framework.xcframework"
done
