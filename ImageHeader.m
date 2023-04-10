@implementation ImageHeader

-(instancetype)init;
{
	// TODO: some Output operations use addCommand: without reloading pointers
	// which causes crashes when the NSMutableData backing gets enlarged
	// preallocating should prevent this, but it's ugly and not explicitly documented
	
	self.data=[NSMutableData dataWithCapacity:0x10000];
	
	return self;
}

-(instancetype)initWithPointer:(char*)pointer
{
	self=self.init;
	
	int size=sizeof(struct mach_header_64)+((struct mach_header_64*)pointer)->sizeofcmds;
	[self.data appendBytes:pointer length:size];
	
	return self;
}

-(instancetype)initEmpty
{
	self=self.init;
	
	[self.data increaseLengthBy:sizeof(struct mach_header_64)];
	
	// TODO: check
	
	self.header->magic=MH_MAGIC_64;
	self.header->cputype=CPU_TYPE_X86_64;
	self.header->cpusubtype=CPU_SUBTYPE_X86_64_ALL;
	self.header->filetype=MH_DYLIB;
	
	return self;
}

-(struct mach_header_64*)header
{
	return (struct mach_header_64*)self.data.mutableBytes;
}

-(void)forEachCommand:(void (^)(struct load_command*))block
{
	struct load_command* command=(struct load_command*)(self.header+1);
	
	for(int commandIndex=0;commandIndex<self.header->ncmds;commandIndex++)
	{
		block(command);
		command=(struct load_command*)(((char*)command)+command->cmdsize);
	}
}

-(struct load_command*)commandWithType:(int)type
{
	__block struct load_command* result=NULL;
	
	[self forEachCommand:^(struct load_command* command)
	{
		if(command->cmd==type)
		{
			assert(!result);
			result=command;
		}
	}];
	
	return result;
}

-(void)forEachSegmentCommand:(void (^)(struct segment_command_64*))block
{
	[self forEachCommand:^(struct load_command* command)
	{
		if(command->cmd==LC_SEGMENT_64)
		{
			struct segment_command_64* segment=(struct segment_command_64*)command;
			block(segment);
		}
	}];
}

-(struct segment_command_64*)segmentCommandWithName:(char*)name
{
	__block struct segment_command_64* output=NULL;
	
	[self forEachSegmentCommand:^(struct segment_command_64* command)
	{
		int length=MIN(16,MAX(strlen(command->segname),strlen(name)));
		if(!strncmp(command->segname,name,length))
		{
			assert(!output);
			output=command;
		}
	}];
	
	return output;
}

// TODO: slow and ugly, may be worth abstracting Segment and creating a map

-(struct segment_command_64*)segmentCommandWithAddress:(long)address indexOut:(int*)indexOut
{
	__block struct segment_command_64* result=NULL;
	__block int index=0;
	
	[self forEachSegmentCommand:^(struct segment_command_64* command)
	{
		if(address>=command->vmaddr&&address<command->vmaddr+command->vmsize)
		{
			if(result)
			{
				trace(@"multiple segments cover address %lx",address);
				self.dumpSegments;
				abort();
			}
			
			result=command;
			
			if(indexOut)
			{
				*indexOut=index;
			}
		}
		
		index++;
	}];
	
	return result;
}

-(struct segment_command_64*)segmentCommandWithOffset:(long)offset indexOut:(int*)indexOut
{
	__block struct segment_command_64* result=NULL;
	__block int index=0;
	
	[self forEachSegmentCommand:^(struct segment_command_64* command)
	{
		if(offset>=command->fileoff&&offset<command->fileoff+command->filesize)
		{
			if(result)
			{
				trace(@"multiple segments cover offset %lx",offset);
				self.dumpSegments;
				abort();
			}
			
			result=command;
			
			if(indexOut)
			{
				*indexOut=index;
			}
		}
		
		index++;
	}];
	
	return result;
}

-(void)forEachSectionCommand:(void (^)(struct segment_command_64*,struct section_64*))block
{
	[self forEachSegmentCommand:^(struct segment_command_64* command)
	{
		struct section_64* sections=(struct section_64*)(command+1);
		for(int index=0;index<command->nsects;index++)
		{
			block(command,&sections[index]);
		}
	}];
}

-(struct section_64*)sectionCommandWithName:(char*)name
{
	__block struct section_64* output=NULL;
	
	[self forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* command)
	{
		// hack to avoid matching subsets or overrunning into segname
		
		int length=MIN(16,MAX(strlen(command->sectname),strlen(name)));
		if(!strncmp(command->sectname,name,length))
		{
			assert(!output);
			output=command;
		}
	}];
	
	return output;
}

-(void)addCommand:(struct load_command*)command
{
	// TODO: confirm Ventura requires this, and pad instead of crashing
	
	assert(command->cmdsize%8==0);
	
	[self.data appendBytes:(char*)command length:command->cmdsize];
	
	self.header->ncmds++;
	self.header->sizeofcmds+=command->cmdsize;
}

// TODO: everything below here is a bit weird, refactor? move to other classes?

-(NSArray<NSString*>*)dylibPathsReexportOnly:(BOOL)reexportOnly
{
	NSMutableArray* result=NSMutableArray.alloc.init.autorelease;
	
	[self forEachCommand:^(struct load_command* command)
	{
		if(command->cmd==LC_LOAD_DYLIB||command->cmd==LC_LOAD_WEAK_DYLIB||command->cmd==LC_LOAD_UPWARD_DYLIB||command->cmd==LC_REEXPORT_DYLIB)
		{
			if(!reexportOnly||command->cmd==LC_REEXPORT_DYLIB)
			{
				int nameOffset=((struct dylib_command*)command)->dylib.name.offset;
				NSString* name=[NSString stringWithUTF8String:(char*)command+nameOffset];
				[result addObject:name];
			}
		}
	}];
	
	return result;
}

-(NSArray<NSString*>*)dylibPaths
{
	// order matters here (bind ordinal)
	
	if(!self.fastShallowPaths)
	{
		self.fastShallowPaths=[self dylibPathsReexportOnly:false];
	}
	
	return self.fastShallowPaths;
}

-(NSSet<NSString*>*)reexportedDylibPathsRecursiveWithCache:(CacheSet*)cache
{
	if(!self.fastRecursivePaths)
	{
		// order doesn't matter here, since we're getting children of one import
		
		NSArray<NSString*>* reexports=[self dylibPathsReexportOnly:true];
		
		NSMutableSet* result=NSMutableSet.alloc.init.autorelease;
		[result addObjectsFromArray:reexports];
		
		for(NSString* path in reexports)
		{
			CacheImage* image=[cache imageWithPath:path];
			assert(image);
			[result unionSet:[image.header reexportedDylibPathsRecursiveWithCache:cache]];
		}
		
		self.fastRecursivePaths=result;
	}
	
	return self.fastRecursivePaths;
}

-(int)ordinalWithDylibPath:(NSString*)target cache:(CacheSet*)cache symbol:(NSString*)symbol newSymbolOut:(NSString**)newSymbolOut
{
	NSArray<NSString*>* shallowPaths=self.dylibPaths;
	long shallowFound=[shallowPaths indexOfObject:target];
	if(shallowFound!=NSNotFound)
	{
		return shallowFound+1;
	}
	
	for(int index=0;index<shallowPaths.count;index++)
	{
		CacheImage* shallowImage=[cache imageWithPath:shallowPaths[index]];
		assert(shallowImage);
		
		NSSet<NSString*>* deepPaths=[shallowImage.header reexportedDylibPathsRecursiveWithCache:cache];
		if([deepPaths containsObject:target])
		{
			return index+1;
		}
		
		// TODO: check if symbol actually comes from the dylib we originally matched
		// name collisions are theoretically possible...
		
		Address* reexport=[shallowImage reexportWithName:symbol];
		if(reexport)
		{
			*newSymbolOut=reexport.name;
			return index+1;
		}
		
		for(NSString* deepPath in deepPaths)
		{
			CacheImage* deepImage=[cache imageWithPath:deepPath];
			Address* reexport=[deepImage reexportWithName:symbol];
			if(reexport)
			{
				*newSymbolOut=reexport.name;
				return index+1;
			}
		}
	}
	
	return -1;
}

-(void)dumpSegments
{
	[self forEachSegmentCommand:^(struct segment_command_64* seg)
	{
		trace(@"segment %s address %lx offset %lx memory size %lx file size %lx",seg->segname,seg->vmaddr,seg->fileoff,seg->vmsize,seg->filesize);
	}];
}

@end