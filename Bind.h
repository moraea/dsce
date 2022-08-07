@interface Bind:NSObject

@property(assign) long address;
@property(assign) int ordinal;
@property(retain) NSString* symbol;

+(instancetype)bindWithAddress:(long)address ordinal:(int)ordinal symbol:(NSString*)symbol;

@end