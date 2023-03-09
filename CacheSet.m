@implementation CacheSet

-(instancetype)initWithPathPrefix:(NSString*)prefix
{
	trace(@"reading %@",prefix);
	
	NSMutableArray<CacheFile*>* files=NSMutableArray.alloc.init.autorelease;
	
	CacheFile* file=[CacheFile.alloc initWithPath:prefix].autorelease;
	if(!file)
	{
		return nil;
	}
	
	[files addObject:file];
	
	// TODO: silly, can probably use dyld_subcache_entry
	
	for(NSString* format in @[@"%@.%d",@"%@.%02d"])
	{
		for(int index=1;;index++)
		{
			NSString* path=[NSString stringWithFormat:format,prefix,index];
			
			CacheFile* file=[CacheFile.alloc initWithPath:path].autorelease;
			if(!file)
			{
				break;
			}
			
			[files addObject:file];
		}
	}
	
	if(files.count==0)
	{
		return nil;
	}
	
	self.files=files;
	
	trace(@"os version %d.%d.%d, subcache count %x",self.majorVersion,self.minorVersion,self.subMinorVersion,files.count);
	
	self.findMagicSel;
	
	return self;
}

-(int)majorVersion
{
	return self.files[0].header->osVersion/0x10000;
}

-(int)minorVersion
{
	return (self.files[0].header->osVersion/0x100)%0x100;
}

-(int)subMinorVersion
{
	return self.files[0].header->osVersion%0x100;
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

-(CacheImage*)imageWithPath:(NSString*)path
{
	for(CacheFile* file in self.files)
	{
		CacheImage* image=[file imageWithPath:path];
		if(image)
		{
			return image;
		}
	}
	
	return nil;
}

-(NSArray<CacheImage*>*)imagesWithPathPrefix:(NSString*)path
{
	NSMutableArray<CacheImage*>* result=NSMutableArray.alloc.init.autorelease;
	
	for(CacheFile* file in self.files)
	{
		NSArray<CacheImage*>* images=[file imagesWithPathPrefix:path];
		[result addObjectsFromArray:images];
	}
	
	return result;
}

-(CacheImage*)imageWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		CacheImage* image=[file imageWithAddress:address];
		if(image)
		{
			return image;
		}
	}
	
	return nil;
}

-(void)findMagicSel
{
	CacheImage* image=[self imagesWithPathPrefix:@"/usr/lib/libobjc.A.dylib"].firstObject;
	assert(image);
	
	struct section_64* section=[image.header sectionCommandWithName:(char*)"__objc_selrefs"];
	assert(section);
	
	long* refs=(long*)wrapOffset(image.file,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	for(int index=0;index<count;index++)
	{
		char* name=wrapAddress(self,refs[index]).pointer;
		
		if(name&&!strcmp(name,"\xf0\x9f\xa4\xaf"))
		{
			self.magicSelAddress=refs[index];
			trace(@"found magic selector at %lx",self.magicSelAddress);
			break;
		}
	}
	
	assert(self.magicSelAddress);
}

@end