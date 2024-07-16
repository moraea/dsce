@import Foundation;

#import "Address.h"
#import "CacheImage.h"
#import "CacheSet.h"
#import "ImageHeader.h"
#import "Selector.h"

@interface Output : NSObject <LocationBase>

@property(assign) CacheSet *cache;
@property(assign) CacheImage *cacheImage;
@property(retain) ImageHeader *header;
@property(retain) NSMutableData *data;
@property(retain) NSMutableDictionary<NSNumber *, Address *> *fixups;
@property(retain) NSMutableArray<Address *> *exports;
@property(retain) NSMutableDictionary<NSString *, Selector *> *sels;
@property(assign) long baseAddressDelta;

+ (void)runWithCache:(CacheSet *)cache
               image:(CacheImage *)image
             outPath:(NSString *)outPath;

@end