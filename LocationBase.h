@protocol LocationBase

// return -1 on error

-(long)addressWithOffset:(long)offset;
-(long)addressWithPointer:(char*)pointer;
-(long)offsetWithAddress:(long)address;

// return NULL on error

-(char*)pointerWithAddress:(long)address;

@end