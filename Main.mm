// TODO: use a Makefile already, this is ridiculous

#import "Extern.h"

BOOL flagPad = false;

#import "Address.h"
#import "CacheFile.h"
#import "CacheImage.h"
#import "CacheSet.h"
#import "ImageHeader.h"
#import "Location.h"
#import "LocationBase.h"
#import "Output.h"
#import "Selector.h"
#import "Util.h"

void process(NSMutableArray<NSString*>* args) {
    NSString* cachePath = args[0];
    [args removeObjectAtIndex:0];

    CacheSet* cache = [CacheSet.alloc initWithPathPrefix:cachePath].autorelease;
    assert(cache);

    if ([args containsObject:@"list"]) {
        assert(args.count == 1);

        NSArray<CacheImage*>* images = [cache imagesWithPathPrefix:@"/"];

        trace(@"list %x images", images.count);

        for (CacheImage* image in images) {
            trace(@"%@", image.path);
        }

        return;
    }

    if ([args containsObject:@"search"]) {
        assert(args.count == 2);

        NSData* target = [args[1] dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableSet* seen = NSMutableSet.alloc.init.autorelease;

        trace(@"search %@", target);

        for (CacheFile* file in cache.files) {
            long offset = 0;
            while (true) {
                NSRange range = [file.data rangeOfData:target options:0 range:NSMakeRange(offset, file.data.length - offset)];
                if (range.location == NSNotFound) {
                    break;
                } else {
                    CacheImage* image = [cache imageWithAddress:wrapOffset(file, range.location).address];

                    if (![seen containsObject:image.path]) {
                        trace(@"%@", image.path);
                        if (image.path) {
                            [seen addObject:image.path];
                        }
                    }

                    offset = range.location + range.length;
                }
            }
        }

        return;
    }

    flagPad = [args containsObject:@"pad"];
    [args removeObject:@"pad"];

    NSMutableArray<CacheImage*>* images = NSMutableArray.alloc.init.autorelease;
    for (NSString* arg in args) {
        NSArray<CacheImage*>* subset = [cache imagesWithPathPrefix:arg];

        if (subset.count == 0) {
            trace(@"no images found for %@*", arg);
            abort();
        }

        [images addObjectsFromArray:subset];
    }

    for (int index = 0; index < images.count; index++) {
        trace(@"extract %@ (%x/%x)", images[index].path, index + 1, images.count);

        // TODO: check for leaks between images

        @autoreleasepool {
            double startTime = NSDate.date.timeIntervalSince1970;

            NSString* outPath = [@"Out" stringByAppendingString:images[index].path];

            NSString* outFolder = outPath.stringByDeletingLastPathComponent;
            assert([NSFileManager.defaultManager createDirectoryAtPath:outFolder withIntermediateDirectories:true attributes:nil
                                                                 error:nil]);

            [Output runWithCache:cache image:images[index] outPath:outPath];

            trace(@"image took %.2lf seconds", NSDate.date.timeIntervalSince1970 - startTime);
        }
    }
}

int main(int argc, char** argv) {
    NSString* edge = [@"" stringByPaddingToLength:9 + log10(DSCE_VERSION) withString:@"─" startingAtIndex:0];
    trace(@"┌%@┐", edge);
    trace(@"│ dsce v%d │", DSCE_VERSION);
    trace(@"└%@┘", edge);

    if (argc < 3) {
        trace(@"usage: dsce <first cache file> ( list | search <string> | [pad] <extraction path prefix> ... )");
        return 1;
    }

    double startTime = NSDate.date.timeIntervalSince1970;

    NSMutableArray<NSString*>* args = NSMutableArray.alloc.init.autorelease;
    for (int index = 1; index < argc; index++) {
        NSString* arg = [NSString stringWithUTF8String:argv[index]];
        [args addObject:arg];
    }

    process(args);

    trace(@"total %.2lf seconds", NSDate.date.timeIntervalSince1970 - startTime);

    return 0;
}