@protocol LocationBase

// expected to return -1 on error

-(long)addressWithOffset:(long)offset;
-(long)addressWithPointer:(char*)pointer;
-(long)offsetWithAddress:(long)address;

// expected to return NULL on error

-(char*)pointerWithAddress:(long)address;

@end