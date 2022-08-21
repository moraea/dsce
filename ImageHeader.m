@implementation ImageHeader

-(instancetype)init;
{
	self.data=NSMutableData.alloc.init.autorelease;
	
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
	
	// TODO: some Output operations use addCommand: inside a forEach*
	// this can (and does) randomly corrupt pointers if the NSMutableData backing is copied
	// preallocating it should prevent this, but it's (1) ugly (2) not explicitly documented
	
	self.data=[NSMutableData dataWithCapacity:0x10000];
	
	[self.data increaseLengthBy:sizeof(struct mach_header_64)];
	
	// TODO: check
	
	self.header->magic=MH_MAGIC_64;
	self.header->cputype=CPU_TYPE_X86_64;
	self.header->cpusubtype=CPU_SUBTYPE_X86_64_ALL;
	self.header->filetype=MH_DYLIB;
	// self.header->flags=MH_DYLDLINK|MH_BINDS_TO_WEAK|MH_TWOLEVEL|MH_ROOT_SAFE|MH_SETUID_SAFE;
	
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
		if(!strncmp(command->segname,name,strlen(name)))
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
		// 16 char sectname runs into sectname
		
		if(!strncmp(command->sectname,name,16))
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

@end