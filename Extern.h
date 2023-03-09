@import Foundation;
@import MachO.nlist;

// TODO: works as of 2023-3-2 but not stable across Apple opensource releases
// i had to adjust clang command as well this time

#import "dyld/cache-builder/dyld_cache_format.h"
#import "dyld/cache-builder/Trie.hpp"

#define OBJC_DECLARE_SYMBOLS 1
#import "objc4/runtime/objc-abi.h"

// TODO: pasted from various places, check

#define OptimizedByDyld 0x8
#define usesRelativeOffsets 0x80000000
#define usesDirectOffsetsToSelectors 0x40000000

// TODO: copied from Hopper, which is weird
// much better to import from objc4 if possible

struct objc_ivar
{
	int32_t* offset;
	char* name;
	char* type;
	uint32_t alignment_raw;
	uint32_t size;
};
struct objc_method
{
	char* name;
	char* signature;
	void* implementation;
};
struct objc_relative_method
{
	int32_t name;
	int32_t signature;
	int32_t implementation;
};
struct objc_method_list
{
	uint32_t flags;
	uint32_t count;
};
struct objc_property
{
	char* name;
	char* attributes;
};
struct objc_property_list
{
	uint32_t entsize;
	uint32_t count;
};
struct objc_protocol
{
	void* isa;
	char* name;
	struct objc_protocol_list* protocols;
	struct objc_method_list* instanceMethods;
	struct objc_method_list* classMethods;
	struct objc_method_list* optionalInstanceMethods;
	struct objc_method_list* optionalClassMethods;
	struct objc_property_list* instanceProperties;
	uint32_t size;
	uint32_t flags;
};
struct objc_data
{
	uint32_t flags;
	uint32_t instanceStart;
	uint32_t instanceSize;
	uint32_t reserved;
	void* ivarLayout;
	char* name;
	struct objc_method_list* baseMethods;
	struct objc_protos* baseProtocols;
	struct objc_ivars* ivars;
	void* weakIvarLayout;
	struct objc_property_list* baseProperties;
};
struct objc_class
{
	struct objc_class* metaclass;
	struct objc_class* superclass;
	struct objc_cache* cache;
	struct objc_vtable* vtable;
	struct objc_data* data;
};
struct objc_category
{
	char* name;
	struct objc_class* cls;
	struct objc_method_list* instanceMethods;
	struct objc_method_list* classMethods;
	struct objc_protocol_list* protocols;
	struct objc_property_list* instanceProperties;
};