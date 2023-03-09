# dsce

Incomplete macOS 12+ dyld cache extractor. Used by [OCLP](https://github.com/dortania/Opencore-Legacy-Patcher/) to support some legacy GPUs and Wi-Fi hardware. Produces working images in many cases, but treat outputs with extreme suspicion...

## credits

- [Apple](https://apple.com): [dyld](https://github.com/apple-oss-distributions/dyld), [objc4](https://github.com/apple-oss-distributions/objc4) (prerequisites)
- [Hopper Disassembler](https://www.hopperapp.com): Mach-O inspection, Objective-C struct definitions
- [Mach-O Explorer](https://github.com/DeVaukz/MachO-Explorer), [MachOView](https://github.com/mythkiven/MachOView): Mach-O inspection
- [Wikipedia](https://wikipedia.org): [LEB128](https://en.wikipedia.org/wiki/LEB128)
- [Moraea](https://github.com/moraea): guidance, testing, encouragement

## status

- [x] copy header and load commands
	- [ ] allocate extra space for additional load commands
- [x] copy segments/sections, fixing offsets and alignment
- [x] generate rebase opcodes
	- [x] by applying cache rebase chain
- [x] generate bind opcodes
	- [x] by scanning rebases for external pointers
		- [x] match imported dylib exports
		- [x] recurse re-exported dylibs/symbols
	- [x] by restoring uniqued `__got` section
	- [x] using C++ addend hack
	- [ ] from weak/lazy bind info
- [x] generate exports trie
	- [x] regular
	- [x] re-export
	- [ ] stub and resolver
- [x] copy legacy symbols, indirect symbols, and string table
- [x] fix Objective-C structures
	- [x] revert selector uniquing
	- [x] revert protocol uniquing
	- [x] fix class, category, and protocol method lists
	- [x] create fake `__objc_imageinfo`
- [x] update UUIDs to `D5CE<version>-...` for visibility in logs (formerly `416D7900-...`)
- [ ] produce fully compliant images
	- [x] satisfy `install_name_tool -id test`
	- [x] satisfy `codesign -fs -`
	- [ ] satisfy `dyld_info -objc`
	- [x] satisfy Stubber (`nm`, Objective-C runtime, linker)
	- [ ] satisfy `lldb`
- [ ] produce working images
	- [x] 12.0 DP6 - GeForceAIRPlugin, GeForceMTLDriver
	- [ ] 12.0 DP6 - GeForceGLDriver
	- [x] 12.6 - AppKit, QuartzCore, CoreGraphics, Carbon, RenderBox, VectorKit, Metal, MetalPerformanceShaders, MTLCompiler, GPUCompiler, AppleGVA, AppleGVACore
	- [x] 12.6 - AMDMTLBronzeDriver, AMDShared, AMDRadeonVADriver, AMDRadeonVADriver2
	- [x] 13.2.1 - AppKit, QuartzCore, CoreGraphics, Carbon, RenderBox, VectorKit, Metal, MetalPerformanceShaders, MTLCompiler, GPUCompiler
	- [ ] 13.2.1 - Combine, libSystem
- [ ] support Big Sur
- [x] support Monterey
- [x] support Ventura
- [ ] use sane amounts of RAM and CPU
- [ ] write automated tests to detect regressions