@interface Output:NSObject<LocationBase>

@property(assign) Cache* cache;
@property(assign) Image* cacheImage;
@property(retain) ImageHeader* header;
@property(retain) NSMutableData* data;
@property(retain) NSMutableDictionary<NSNumber*,Rebase*>* rebases;
@property(retain) NSMutableDictionary<NSNumber*,Bind*>* binds;
@property(retain) NSMutableArray<Symbol*>* exports;
@property(retain) NSMutableArray<MoveRecord*>* sectionRecords;
@property(assign) long magicSelAddress;
@property(retain) NSMutableDictionary<NSString*,Selector*>* sels;
@property(assign) BOOL shouldMakeImpostor;

+(void)runWithCache:(Cache*)cache image:(Image*)image outPath:(NSString*)outPath;

@end