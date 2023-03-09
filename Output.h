@interface Output:NSObject<LocationBase>

@property(assign) CacheSet* cache;
@property(assign) CacheImage* cacheImage;
@property(retain) ImageHeader* header;
@property(retain) NSMutableData* data;
@property(retain) NSMutableDictionary<NSNumber*,Address*>* fixups;
@property(retain) NSMutableArray<Address*>* exports;
@property(assign) long magicSelAddress;
@property(retain) NSMutableDictionary<NSString*,Selector*>* sels;

+(void)runWithCache:(CacheSet*)cache image:(CacheImage*)image outPath:(NSString*)outPath;

@end