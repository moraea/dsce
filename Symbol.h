@interface Symbol:NSObject

@property(assign) BOOL isExport;
@property(retain) NSString* name;
@property(assign) long address;
@property(retain) NSString* importName;
@property(assign) int importOrdinal;

+(instancetype)exportWithAddress:(long)address name:(NSString*)name;
+(instancetype)reexportWithAddress:(long)address name:(NSString*)name importName:(NSString*)importName importOrdinal:(int)importOrdinal;
+(instancetype)importWithName:(NSString*)name ordinal:(int)ordinal;

@end