set -e

cd "$(dirname "$0")"

clang++ -fmodules -fcxx-modules -std=c++17 -Wno-unused-getter-return-value -I .. Main.mm -o Extract

rm -rf Out

./Extract ../125/dyld_shared_cache_x86_64 /System/Library/Extensions/AMDMTLBronzeDriver /System/Library/Extensions/AMDShared /System/Library/Frameworks/Metal.framework /System/Library/Frameworks/MetalPerformanceShaders.framework

find -d Out -type f -exec codesign -f -s - {} \;

# DYLD_FRAMEWORK_PATH=$PWD/Out/System/Library/Frameworks:$PWD/Out/System/Library/PrivateFrameworks /System/Applications/TextEdit.app/Contents/MacOS/TextEdit