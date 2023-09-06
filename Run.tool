VERSION=7

set -e

cd "$(dirname "$0")"

clang++ -fmodules -fcxx-modules -std=c++17 -Wno-unused-getter-return-value -mmacosx-version-min=12 -I .. -I ../dyld/common -DDSCE_VERSION="$VERSION" Main.mm -o dsce

rm -rf Out

./dsce /System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64h /System/Library/Frameworks/AppKit.framework /System/Library/Frameworks/QuartzCore.framework /System/Library/Frameworks/CoreGraphics.framework /System/Library/Frameworks/Carbon.framework /System/Library/PrivateFrameworks/RenderBox.framework /System/Library/PrivateFrameworks/VectorKit.framework /System/Library/Frameworks/Metal.framework /System/Library/Frameworks/MetalPerformanceShaders.framework /System/Library/PrivateFrameworks/MTLCompiler.framework /System/Library/PrivateFrameworks/GPUCompiler.framework

find -d Out -type f -exec codesign -f -s - {} \;
chmod -R 755 Out