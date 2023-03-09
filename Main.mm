// TODO: use a Makefile already, this is ridiculous

#import "Extern.h"

void trace(NSString* format,...)
{
	va_list args;
	va_start(args,format);
	NSString* message=[NSString.alloc initWithFormat:format arguments:args].autorelease;
	va_end(args);
	
	printf("\e[%dm%s\e[0m\n",31+(DSCE_VERSION+1)%6,message.UTF8String);
}

#import "LocationBase.h"
#import "Location.h"
@class CacheImage;
#import "CacheFile.h"
@class CacheSet;
#import "ImageHeader.h"
#import "Address.h"
#import "CacheImage.h"
#import "CacheSet.h"
#import "Selector.h"
#import "Output.h"

#import "Location.m"
#import "CacheFile.m"
#import "ImageHeader.m"
#import "Address.m"
#import "CacheImage.m"
#import "CacheSet.m"
#import "Selector.m"
#import "Output.m"

void extract(CacheSet* cache,CacheImage* image)
{
	// TODO: check for leaks between images
	
	@autoreleasepool
	{
		double startTime=NSDate.date.timeIntervalSince1970;
		
		NSString* outPath=[@"Out" stringByAppendingString:image.path];
		NSString* outFolder=outPath.stringByDeletingLastPathComponent;
		assert([NSFileManager.defaultManager createDirectoryAtPath:outFolder withIntermediateDirectories:true attributes:nil error:nil]);
		
		[Output runWithCache:cache image:image outPath:outPath];
		
		trace(@"image took %.2lf seconds",NSDate.date.timeIntervalSince1970-startTime);
	}
}

int main(int argc,char** argv)
{
	// just exiting is more efficient
	
	// @autoreleasepool
	{
		trace(@"amy's dsce v%d",DSCE_VERSION);
		
		if(argc<3)
		{
			trace(@"usage: %s <cache> ( <image prefix> ... | list )",argv[0]);
			return 1;
		}
		
		double startTime=NSDate.date.timeIntervalSince1970;
		
		NSString* cachePath=[NSString stringWithUTF8String:argv[1]];
		CacheSet* cache=[CacheSet.alloc initWithPathPrefix:cachePath].autorelease;
		assert(cache);
		
		NSString* keyword=[NSString stringWithUTF8String:argv[2]];
		
		// TODO: cringe
		
		if([keyword isEqual:@"list"])
		{
			NSArray<CacheImage*>* images=[cache imagesWithPathPrefix:@"/"];
			
			trace(@"listing %x images",images.count);
			
			for(CacheImage* image in images)
			{
				trace(@"%@",image.path);
			}
		}
		else
		{
			// TODO: i wonder what would happen if i ran a few of these in parallel...
			// shouldn't require too many changes?
			
			NSMutableArray<CacheImage*>* images=NSMutableArray.alloc.init.autorelease;
			
			for(int index=2;index<argc;index++)
			{
				NSString* prefix=[NSString stringWithUTF8String:argv[index]];
				NSArray<CacheImage*>* subset=[cache imagesWithPathPrefix:prefix];
				if(subset.count==0)
				{
					trace(@"no images found for %@*",prefix);
					abort();
				}
				[images addObjectsFromArray:subset];
			}
			
			trace(@"matched %x images",images.count);
				
			for(CacheImage* image in images)
			{
				extract(cache,image);
			}
		}
		
		trace(@"total %.2lf seconds",NSDate.date.timeIntervalSince1970-startTime);
	}
	
	return 0;
}