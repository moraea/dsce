set -e

cd "$(dirname "$0")"

clang++ -fmodules -fcxx-modules -std=c++17 -Wno-unused-getter-return-value -I .. Main.mm -o Extract

rm -rf Out

./Extract /System/Library/dyld/dyld_shared_cache_x86_64 /System/Library/Frameworks/QuartzCore /System/Library/Frameworks/CoreGraphics /System/Library/Frameworks/Carbon /System/Library/Frameworks/AppKit

# ./Extract ../125dp2/dyld_shared_cache_x86_64 /System/Library/Frameworks/MetalPerformanceShaders.framework

# ./Extract ../12dp6/dyld_shared_cache_x86_64 /System/Library/Extensions/GeForce

# ./Extract ../13b4/dyld_shared_cache_x86_64h /System/Library/Frameworks/QuartzCore /System/Library/Frameworks/CoreGraphics /System/Library/Frameworks/Carbon /System/Library/Frameworks/AppKit

find Out -type f -exec codesign -f -s - {} \;

DYLD_FRAMEWORK_PATH=$PWD/Out/System/Library/Frameworks:$PWD/Out/System/Library/PrivateFrameworks /System/Applications/TextEdit.app/Contents/MacOS/TextEdit