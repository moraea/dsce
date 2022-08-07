@interface CacheFile:NSObject<LocationBase>

@property(retain) NSMutableData* data;
@property(assign) struct dyld_cache_header* header;
@property(retain) NSArray<Image*>* images;
@property(retain) NSArray<NSNumber*>* rebaseAddresses;

-(instancetype)initWithPath:(NSString*)path;

-(NSArray<Image*>*)imagesWithPathPrefix:(NSString*)path;
-(Image*)imageWithAddress:(long)address;

@end