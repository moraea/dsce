VERSION=10

set -e

cd "$(dirname "$0")"

clang++ -fmodules -fcxx-modules -std=c++20 -Wno-unused-getter-return-value -mmacosx-version-min=12 -I apple -I apple/dyld/common -I apple/dyld/lsl -I apple/libplatform/private -DDSCE_VERSION="$VERSION" Main.mm -o dsce

# rm -rf Out

# ./dsce '/Volumes/amazon/open 2025-6-4/root/misc/versions/15.5 (24F74)/cryptex/intel/System/Library/dyld/dyld_shared_cache_x86_64h' /System/Library/Extensions/AppleIntelKBLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelKBLGraphicsMTLDriver

# find -d Out -type f -exec codesign -f -s - {} \;
# chmod -R 755 Out
