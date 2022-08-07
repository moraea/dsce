@interface Output:NSObject<LocationBase>

@property(assign) Cache* cache;
@property(assign) Image* cacheImage;
@property(retain) ImageHeader* header;
@property(retain) NSMutableData* data;
@property(retain) NSMutableArray<NSNumber*>* segmentLeftPads;
@property(retain) NSMutableArray<NSNumber*>* segmentRightPads;
@property(retain) NSMutableDictionary<NSNumber*,Rebase*>* rebases;
@property(retain) NSMutableDictionary<NSNumber*,Bind*>* binds;
@property(assign) long magicSelAddress;
@property(retain) NSMutableDictionary<NSString*,Selector*>* sels;

+(void)runWithCache:(Cache*)cache image:(Image*)image outPath:(NSString*)outPath;

@end