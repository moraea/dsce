@interface MoveRecord:NSObject

@property(assign) long oldStart;
@property(assign) long oldEnd;
@property(assign) long newStart;
@property(assign) long newEnd;

+(instancetype)recordWithOldStart:(long)oldStart newStart:(long)newStart size:(long)size;

-(BOOL)containsOld:(long)address;
-(BOOL)containsNew:(long)address;
-(long)convert:(long)address;

@end