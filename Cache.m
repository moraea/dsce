@implementation Cache

-(instancetype)initWithPathPrefix:(NSString*)prefix
{
	NSMutableArray<CacheFile*>* files=NSMutableArray.alloc.init.autorelease;
	
	for(int index=0;;index++)
	{
		// TODO: support Ventura scheme
		
		NSString* path=index==0?prefix:[NSString stringWithFormat:@"%@.%d",prefix,index];
		
		CacheFile* file=[CacheFile.alloc initWithPath:path].autorelease;
		if(!file)
		{
			break;
		}
		
		[files addObject:file];
	}
	
	if(files.count==0)
	{
		return nil;
	}
	
	self.files=files;
	
	return self;
}

-(long)addressWithOffset:(long)offset
{
	// lacks context of which cache file
	
	abort();
}

-(long)addressWithPointer:(char*)pointer
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapPointerUnsafe(file,pointer);
		if(location)
		{
			return location.address;
		}
	}
	
	return -1;
}

-(long)offsetWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapAddressUnsafe(file,address);
		if(location)
		{
			return location.offset;
		}
	}
	
	return -1;
}

-(char*)pointerWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapAddressUnsafe(file,address);
		if(location)
		{
			return location.pointer;
		}
	}
	
	return NULL;
}

-(NSArray<Image*>*)imagesWithPathPrefix:(NSString*)path
{
	NSMutableArray<Image*>* result=NSMutableArray.alloc.init.autorelease;
	
	for(CacheFile* file in self.files)
	{
		NSArray<Image*>* images=[file imagesWithPathPrefix:path];
		[result addObjectsFromArray:images];
	}
	
	return result;
}

-(Image*)imageWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		Image* image=[file imageWithAddress:address];
		if(image)
		{
			return image;
		}
	}
	
	return nil;
}

@end