VERSION := 6

# This will force a rebuild every time, in case dyld changes or headers change
.PHONY: all clean

SRC=$(wildcard *.m *.mm)
HEADERS=$(wildcard *.h)

all: dsce

# This is a bit of a hack to get the binary to rebuild when the headers change
dsce: $(HEADERS)
	clang++ -fmodules -fcxx-modules -std=c++17 -Wno-unused-getter-return-value -mmacosx-version-min=12 -Idyld/common -DDSCE_VERSION="$(VERSION)" $(SRC) -o $@

clean:
	rm -f $(OBJ) dsce
