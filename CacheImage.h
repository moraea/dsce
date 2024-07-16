#import "Address.h"
#import "ImageHeader.h"
@import Foundation;
#import "CacheFile.h"

@interface CacheImage : NSObject

@property(assign) CacheFile* file;
@property(assign) long baseAddress;
@property(retain) ImageHeader* header;
@property(retain) NSString* path;
@property(retain) NSMutableArray<Address*>* exports;
@property(retain) NSMutableDictionary<NSNumber*, Address*>* fastExportsByAddress;
@property(retain) NSMutableDictionary<NSString*, Address*>* fastReexportsByName;

- (instancetype)initWithCacheFile:(CacheFile*)file info:(struct dyld_cache_image_info*)info;

- (void)forEachLegacySymbol:(void (^)(struct nlist_64*, char*))block;
- (Address*)exportWithAddress:(long)address;
- (Address*)reexportWithName:(NSString*)name;
- (NSArray<NSNumber*>*)enclosingChunksWithSize:(long)chunkSize;

@end