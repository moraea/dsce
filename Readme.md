# dsce

Incomplete macOS 11+ dyld cache extractor with a focus on Metal-related dylibs.

## credits

- [Apple](https://apple.com): [dyld](https://github.com/apple-oss-distributions/dyld), [objc4](https://github.com/apple-oss-distributions/objc4) (prerequisites)
- [Hopper Disassembler](https://www.hopperapp.com): Mach-O inspection, Objective-C struct definitions
- [Mach-O Explorer](https://github.com/DeVaukz/MachO-Explorer), [MachOView](https://github.com/mythkiven/MachOView): Mach-O inspection
- [Wikipedia](https://wikipedia.org): [LEB128](https://en.wikipedia.org/wiki/LEB128)
- [Moraea](https://github.com/moraea): code, guidance and testing

## status

- [x] copy header and load commands
- [x] copy segments/sections, updating offsets and addresses
- [x] process cache rebase chain
	- [x] generate opcodes
- [x] generate bind opcodes
	- [x] from symbol pointer sections
	- [x] by scanning whole image and resolving external pointers
- [ ] generate exports trie
	- [x] regular
	- [x] re-export
	- [ ] stub and resolver
- [x] copy symbols, indirect symbols, and string table
- [x] fix Objective-C structures
	- [x] revert selector uniquing
	- [x] revert protocol uniquing
	- [x] fix class, category, and protocol method lists
- [x] mark UUIDs for testing
- [ ] produce fully compliant images
	- [x] satisfy `install_name_tool -id test`
	- [x] satisfy `codesign -fs -`
	- [ ] satisfy `dyld_info -objc`
	- [x] satisfy Stubber (`nm`, Objective-C runtime, linker)
	- [ ] satisfy `lldb`
- [ ] produce working images
	- [ ] work normally with selected images extracted and installed
		- [x] 12.0 DP6 - GeForce bundles
		- [x] 12.5 DP2 - MetalPerformanceShaders and sub-frameworks
		- [x] 12.5 DP3 - QuartzCore, CoreGraphics, Carbon, AppKit
		- [x] 12.5 - AMDMTLBronzeDriver, AMDShared, Metal, MetalPerformanceShaders, MTLCompiler, GPUCompiler
		- [x] 13.0 DP4 - QuartzCore, CoreGraphics, Carbon
		- [ ] 13.0 DP4 - AppKit
	- [ ] work normally with all images extracted and cache removed
- [ ] support Big Sur
- [x] support Monterey
- [x] support Ventura
	- [ ] without the `__objc_imageinfo` hack
- [ ] use sane amounts of RAM and CPU
- [ ] write automated tests to detect regressions