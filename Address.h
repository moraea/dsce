@import Foundation;

#define ADDRESS_REBASE 1
#define ADDRESS_BIND 2
#define ADDRESS_EXPORT 3
#define ADDRESS_REEXPORT 4

@interface Address:NSObject

@property(assign) int type;
@property(assign) long address;

@property(retain) NSString* name;
@property(retain) NSString* importName;
@property(assign) int dylibOrdinal;
@property(assign) int addend;

+(instancetype)rebaseWithAddress:(long)address;
+(instancetype)bindWithAddress:(long)address ordinal:(int)ordinal name:(NSString*)name addend:(int)addend;
+(instancetype)exportWithAddress:(long)address name:(NSString*)name;
+(instancetype)reexportWithName:(NSString*)name importName:(NSString*)importName importOrdinal:(int)ordinal;

-(BOOL)isRebase;
-(BOOL)isBind;
-(BOOL)isExport;
-(BOOL)isReexport;

@end