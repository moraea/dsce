@interface CacheFile:NSObject<LocationBase>

@property(retain) NSMutableData* data;
@property(retain) NSArray<CacheImage*>* images;
@property(retain) NSArray<NSNumber*>* rebaseAddresses;

-(instancetype)initWithPath:(NSString*)path;

-(long)maxConstDataMappingAddress;
-(long)maxConstDataSegmentAddress;

-(CacheImage*)imageWithPath:(NSString*)path;
-(NSArray<CacheImage*>*)imagesWithPathPrefix:(NSString*)path;
-(CacheImage*)imageWithAddress:(long)address;

@end