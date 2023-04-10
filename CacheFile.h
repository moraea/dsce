// TODO: properly tune this

#define FAST_CHUNK_SIZE 0x10000

@interface CacheFile:NSObject<LocationBase>

@property(retain) NSMutableData* data;
@property(retain) NSArray<CacheImage*>* images;

@property(retain) NSDictionary<NSNumber*,NSArray<NSNumber*>*>* fastRebasesByChunk;
@property(retain) NSDictionary<NSNumber*,NSArray<CacheImage*>*>* fastImagesByChunk;
@property(retain) NSDictionary<NSString*,CacheImage*>* fastImagesByPath;

-(instancetype)initWithPath:(NSString*)path;

-(long)maxConstDataMappingAddress;
-(long)maxConstDataSegmentAddress;
-(CacheImage*)imageWithPath:(NSString*)path;
-(NSArray<CacheImage*>*)imagesWithPathPrefix:(NSString*)path;
-(CacheImage*)imageWithAddress:(long)address;
-(NSArray<NSNumber*>*)rebasesWithStartAddress:(long)start endAddress:(long)end;

@end