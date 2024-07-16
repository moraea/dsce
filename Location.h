@import Foundation;

#import "LocationBase.h"

@interface Location : NSObject

@property(assign) NSObject<LocationBase> *base;
@property(assign) long address;

- (long)offset;
- (char *)pointer;

@end

// return nil on error

Location *wrapAddressUnsafe(NSObject<LocationBase> *base, long address);
Location *wrapOffsetUnsafe(NSObject<LocationBase> *base, long offset);
Location *wrapPointerUnsafe(NSObject<LocationBase> *base, char *pointer);

// abort on error

Location *wrapAddress(NSObject<LocationBase> *base, long address);
Location *wrapOffset(NSObject<LocationBase> *base, long offset);
Location *wrapPointer(NSObject<LocationBase> *base, char *pointer);