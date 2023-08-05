#import "Location.h"

@implementation Location

+(instancetype)locationWithBase:(NSObject<LocationBase>*)base address:(long)address
{
	if(address<0)
	{
		return nil;
	}
	if([base offsetWithAddress:address]<0)
	{
		return nil;
	}
	if(![base pointerWithAddress:address])
	{
		return nil;
	}
	
	Location* location=Location.alloc.init.autorelease;
	location.base=base;
	location.address=address;
	
	return location;
}

-(long)offset
{
	return [self.base offsetWithAddress:self.address];
}

-(char*)pointer
{
	return [self.base pointerWithAddress:self.address];
}

@end

Location* wrapAddressUnsafe(NSObject<LocationBase>* base,long address)
{
	return [Location locationWithBase:base address:address];
}

Location* wrapOffsetUnsafe(NSObject<LocationBase>* base,long offset)
{
	return wrapAddressUnsafe(base,[base addressWithOffset:offset]);
}

Location* wrapPointerUnsafe(NSObject<LocationBase>* base,char* pointer)
{
	return wrapAddressUnsafe(base,[base addressWithPointer:pointer]);
}

Location* wrapAddress(NSObject<LocationBase>* base,long address)
{
	Location* result=wrapAddressUnsafe(base,address);
	assert(result);
	return result;
}

Location* wrapOffset(NSObject<LocationBase>* base,long offset)
{
	Location* result=wrapOffsetUnsafe(base,offset);
	assert(result);
	return result;
}

Location* wrapPointer(NSObject<LocationBase>* base,char* pointer)
{
	Location* result=wrapPointerUnsafe(base,pointer);
	assert(result);
	return result;
}