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
			assert(!result);
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
			assert(!result);
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

-(NSArray<NSString*>*)reexportedDylibPaths
{
	return [self dylibPathsReexportOnly:true];
}

-(NSArray<NSString*>*)dylibPaths
{
	return [self dylibPathsReexportOnly:false];
}

-(NSArray<NSString*>*)reexportedDylibPathsRecursiveWithCache:(CacheSet*)cache
{
	NSMutableArray* result=NSMutableArray.alloc.init.autorelease;
	[result addObjectsFromArray:self.reexportedDylibPaths];
	
	for(NSString* path in self.reexportedDylibPaths)
	{
		CacheImage* image=[cache imageWithPath:path];
		assert(image);
		[result addObjectsFromArray:[image.header reexportedDylibPathsRecursiveWithCache:cache]];
	}
	
	return result;
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
		CacheImage* image=[cache imageWithPath:shallowPaths[index]];
		assert(image);
		
		NSArray<NSString*>* deepPaths=[image.header reexportedDylibPathsRecursiveWithCache:cache];
		if([deepPaths containsObject:target])
		{
			return index+1;
		}
		
		Address* reexport=[image reexportWithName:symbol];
		if(reexport)
		{
			*newSymbolOut=reexport.name;
			return index+1;
		}
		
		for(NSString* deepPath in deepPaths)
		{
			CacheImage* image=[cache imageWithPath:deepPath];
			Address* reexport=[image reexportWithName:symbol];
			if(reexport)
			{
				*newSymbolOut=reexport.name;
				return index+1;
			}
		}
	}
	
	return -1;
}

@end