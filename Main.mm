// TODO: use a Makefile already, this is ridiculous

#import "Extern.h"

void trace(NSString* format,...)
{
	va_list args;
	va_start(args,format);
	NSString* message=[NSString.alloc initWithFormat:format arguments:args].autorelease;
	va_end(args);
	
	printf("\e[%dm%s\e[0m\n",31+DSCE_VERSION%6,message.UTF8String);
}

BOOL flagList=false;
BOOL flagPad=false;

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
	NSString* edge=[@"" stringByPaddingToLength:9+log10(DSCE_VERSION) withString:@"─" startingAtIndex:0];
	trace(@"┌%@┐",edge);
	trace(@"│ dsce v%d │",DSCE_VERSION);
	trace(@"└%@┘",edge);
	
	if(argc<3)
	{
		trace(@"usage: dsce <first cache file> [list] [pad] [path prefix ...]");
		return 1;
	}
	
	double startTime=NSDate.date.timeIntervalSince1970;
	
	NSString* cachePath=[NSString stringWithUTF8String:argv[1]];
	CacheSet* cache=[CacheSet.alloc initWithPathPrefix:cachePath].autorelease;
	assert(cache);
	
	NSMutableArray<CacheImage*>* images=NSMutableArray.alloc.init.autorelease;
	
	for(int index=2;index<argc;index++)
	{
		NSString* arg=[NSString stringWithUTF8String:argv[index]];
		
		if([arg isEqual:@"list"])
		{
			flagList=true;
			continue;
		}
		
		if([arg isEqual:@"pad"])
		{
			flagPad=true;
			continue;
		}
		
		NSArray<CacheImage*>* subset=[cache imagesWithPathPrefix:arg];
		if(subset.count==0)
		{
			trace(@"no images found for %@*",arg);
			abort();
		}
		[images addObjectsFromArray:subset];
	}
	
	if(flagList)
	{
		if(images.count==0)
		{
			[images addObjectsFromArray:[cache imagesWithPathPrefix:@"/"]];
		}
		
		trace(@"list %x images",images.count);
		
		for(CacheImage* image in images)
		{
			trace(@"%@",image.path);
		}
	}
	else
	{
		for(int index=0;index<images.count;index++)
		{
			trace(@"extract %@ (%x/%x)",images[index].path,index+1,images.count);
			extract(cache,images[index]);
		}
	}
	
	trace(@"total %.2lf seconds",NSDate.date.timeIntervalSince1970-startTime);
	
	return 0;
}