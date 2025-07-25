VERSION=10

set -e

cd "$(dirname "$0")"

function clangCommonCpp
{
	clang++ -fmodules -fcxx-modules -std=c++20 -Wno-unused-getter-return-value -mmacosx-version-min=12 -I . -I apple -I apple/dyld/common -I apple/dyld/lsl -I apple/libplatform/private -DDSCE_VERSION="$VERSION" "$@"
}

function clangCommonC
{
	clang++ -fmodules "$@"
}

clangCommonCpp Main.mm -o dsce
clangCommonCpp 'hotfixes/dysymtab test 2.mm' -o hotfixDysymtab
clangCommonC 'hotfixes/15.4 data rw hotfix.m' -o hotfixDataRw
clangCommonC 'hotfixes/retroactive_flag_removal.m' -o hotfixHeader
