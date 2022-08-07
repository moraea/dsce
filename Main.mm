// TODO: use a Makefile already, this is ridiculous

#import "Extern.h"

void trace(NSString* format,...)
{
	va_list args;
	va_start(args,format);
	NSString* message=[NSString.alloc initWithFormat:format arguments:args].autorelease;
	va_end(args);
	
	printf("\e[%dm%s\e[0m\n",34,message.UTF8String);
}

#import "LocationBase.h"
#import "Location.h"
@class Image;
#import "CacheFile.h"
#import "ImageHeader.h"
#import "Symbol.h"
#import "Image.h"
#import "Cache.h"
#import "Rebase.h"
#import "Bind.h"
#import "Selector.h"
#import "Output.h"

#import "Location.m"
#import "CacheFile.m"
#import "ImageHeader.m"
#import "Symbol.m"
#import "Image.m"
#import "Cache.m"
#import "Rebase.m"
#import "Bind.m"
#import "Selector.m"
#import "Output.m"

void extract(Cache* cache,Image* image)
{
	// TODO: draining this adds a significant delay between images
	// but i am not about to rewrite everything with manual retain/release
	
	@autoreleasepool
	{
		double time=NSDate.date.timeIntervalSince1970;
		
		NSString* outPath=[@"Out" stringByAppendingString:image.path];
		NSString* outFolder=outPath.stringByDeletingLastPathComponent;
		assert([NSFileManager.defaultManager createDirectoryAtPath:outFolder withIntermediateDirectories:true attributes:nil error:nil]);
		
		[Output runWithCache:cache image:image outPath:outPath];
		
		double delta=NSDate.date.timeIntervalSince1970-time;
		trace(@"took %lf seconds",delta);
	}
}

int main(int argc,char** argv)
{
	@autoreleasepool
	{
		if(argc<3)
		{
			trace(@"usage: %s <cache> ( <image prefix> ... | list )",argv[0]);
			return 1;
		}
		
		NSString* cachePath=[NSString stringWithUTF8String:argv[1]];
		Cache* cache=[Cache.alloc initWithPathPrefix:cachePath].autorelease;
		
		// TODO: check for leaks extracting many images in one run
		
		NSString* keyword=[NSString stringWithUTF8String:argv[2]];
		
		if([keyword isEqual:@"list"])
		{
			NSArray<Image*>* images=[cache imagesWithPathPrefix:@"/"];
			
			trace(@"listing %x images",images.count);
			
			for(Image* image in images)
			{
				trace(@"%@",image.path);
			}
		}
		else
		{
			for(int index=2;index<argc;index++)
			{
				NSString* prefix=[NSString stringWithUTF8String:argv[index]];
				NSArray<Image*>* images=[cache imagesWithPathPrefix:prefix];
				
				trace(@"matched %x images for prefix %@*",images.count,prefix);
				
				for(Image* image in images)
				{
					extract(cache,image);
				}
			}
		}
	}
	
	return 0;
}