@interface Cache:NSObject<LocationBase>

@property(retain) NSArray<CacheFile*>* files;

-(instancetype)initWithPathPrefix:(NSString*)prefix;

-(NSArray<Image*>*)imagesWithPathPrefix:(NSString*)path;
-(Image*)imageWithAddress:(long)address;

@end