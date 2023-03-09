@interface ImageHeader:NSObject

@property(retain) NSMutableData* data;

-(instancetype)initWithPointer:(char*)pointer;
-(instancetype)initEmpty;

-(struct mach_header_64*)header;
-(void)forEachCommand:(void (^)(struct load_command*))block;
-(struct load_command*)commandWithType:(int)type;
-(void)forEachSegmentCommand:(void (^)(struct segment_command_64*))block;
-(struct segment_command_64*)segmentCommandWithName:(char*)name;
-(struct segment_command_64*)segmentCommandWithAddress:(long)address indexOut:(int*)indexOut;
-(struct segment_command_64*)segmentCommandWithOffset:(long)offset indexOut:(int*)indexOut;
-(void)forEachSectionCommand:(void (^)(struct segment_command_64*,struct section_64*))block;
-(struct section_64*)sectionCommandWithName:(char*)name;
-(void)addCommand:(struct load_command*)command;
-(int)ordinalWithDylibPath:(NSString*)target cache:(CacheSet*)cache symbol:(NSString*)symbol newSymbolOut:(NSString**)newSymbolOut;

@end