set -e

dyld='/Volumes/Temporary 40/Downloads Overflow 42/apple-oss-distributions Repos (2023-3-2)/dyld'
code='/Volumes/Files/notes/dysymtab test 2.mm'
temp=/Volumes/Files/temp

rm -rf "$temp"
mkdir "$temp"
PATH+=:"$temp"
cd "$temp"

clang++ -fmodules -fcxx-modules -std=c++17 -I "$dyld/common" -I "$dyld/cache-builder" "$code" -o hotfix

base='/Volumes/Files/git/unsupported-wifi-patches/Modern-WiFi-Patcher-Sequoia'
for name in CoreWiFi_1372 IO80211_1372 CoreWLAN_1372 WiFiPeerToPeer_1372
do
	hotfix "$base/$name" "$base/${name}"
done
