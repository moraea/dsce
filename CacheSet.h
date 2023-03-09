@interface CacheSet:NSObject<LocationBase>

@property(retain) NSArray<CacheFile*>* files;
@property(assign) long magicSelAddress;

-(instancetype)initWithPathPrefix:(NSString*)prefix;

-(CacheImage*)imageWithPath:(NSString*)path;
-(NSArray<CacheImage*>*)imagesWithPathPrefix:(NSString*)path;
-(CacheImage*)imageWithAddress:(long)address;

@end