// TODO: rename to CacheImage for clarity
// since this is immutable and references the cache, unlike ImageHeader/Output

@interface Image:NSObject

@property(assign) CacheFile* file;
@property(retain) ImageHeader* header;
@property(retain) NSString* path;
@property(retain) NSDictionary<NSString*,Symbol*>* symbols;
@property(retain) NSDictionary<NSNumber*,Symbol*>* symbolsByIndex;
@property(retain) NSDictionary<NSNumber*,Symbol*>* symbolsByAddress;

-(instancetype)initWithCacheFile:(CacheFile*)file info:(struct dyld_cache_image_info*)info;

-(void)forEachSymbol:(void (^)(struct nlist_64*,char*))block;
-(Symbol*)exportWithAddress:(long)address;
-(Symbol*)importWithName:(NSString*)name;
-(Symbol*)importWithIndex:(long)index;

@end