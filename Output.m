// https://en.wikipedia.org/wiki/LEB128

NSData* ulebWithLong(long value)
{
	NSMutableData* output=NSMutableData.alloc.init;
	do
	{
		char byte=value&0x7f;
		value>>=7;
		if(value)
		{
			byte|=0x80;
		}
		[output appendBytes:&byte length:1];
	}
	while(value);
	return output;
}

long align(long address,int amount,BOOL ceil,int* deltaOut)
{
	long newAddress=address/amount*amount;
	if(ceil&&newAddress!=address)
	{
		newAddress+=amount;
	}
	
	if(deltaOut)
	{
		*deltaOut=newAddress-address;
	}
	
	return newAddress;
}

BOOL isAligned(long address,int amount)
{
	return align(address,amount,false,NULL)==address;
}

@implementation Output

+(void)runWithCache:(CacheSet*)cache image:(CacheImage*)image outPath:(NSString*)outPath
{
	trace(@"extract %@",image.path);
	
	Output* output=[Output.alloc initWithCache:cache image:image].autorelease;
	[output extractWithPath:outPath];
}

-(instancetype)initWithCache:(CacheSet*)cache image:(CacheImage*)image
{
	self=super.init;
	
	assert(cache);
	self.cache=cache;
	
	assert(image);
	self.cacheImage=image;
	
	return self;
}

// TODO: calling this multiple times on one instance would be bad

-(void)extractWithPath:(NSString*)outPath
{
	NSArray<NSString*>* steps=@[@"stepImportHeader",@"stepImportSegmentsExceptLinkedit",@"stepImportRebases",@"stepImportExports",@"stepFixImageInfo",@"stepFindMagicSel",@"stepFindEmbeddedSels",@"stepFixSelRefs",@"stepFixClasses",@"stepFixCats",@"stepFixProtoRefs",@"stepFixProtos",@"stepFixPointersNew",@"stepBuildLinkedit",@"stepMarkUUID",@"stepSyncHeader"];
	
	for(NSString* step in steps)
	{
		[self performSelector:NSSelectorFromString(step)];
	}
	
	trace(@"write %@",outPath);
	[self.data writeToFile:outPath atomically:false];
}

-(BOOL)needsObjcImpostor
{
	return !![self.cacheImage.header sectionCommandWithName:(char*)"__objc_imageinfo"];
}

-(BOOL)needsGotImpostor
{
	if(self.cache.majorVersion!=13)
	{
		return false;
	}
	
	struct section_64* section=[self.cacheImage.header sectionCommandWithName:(char*)"__got"];
	if(section)
	{
		if(!(section->flags&SECTION_TYPE&S_NON_LAZY_SYMBOL_POINTERS))
		{
			return true;
		}
	}
	
	return false;
}

-(void)stepImportHeader
{
	self.header=ImageHeader.alloc.initEmpty.autorelease;
	
	self.header.header->flags=self.cacheImage.header.header->flags;
	
	__block int copied=0;
	__block int skipped=0;
	
	// MachOAnalyzer.cpp - load command order must mirror offset/address order
	// TODO: dumb way to do this
	
	NSMutableArray<NSNumber*>* addresses=NSMutableArray.alloc.init.autorelease;
	[self.cacheImage.header forEachSegmentCommand:^(struct segment_command_64* command)
	{
		[addresses addObject:[NSNumber numberWithLong:command->vmaddr]];
	}];
	[addresses sortUsingComparator:^NSComparisonResult(NSNumber* first,NSNumber* second)
	{
		return first.longValue<second.longValue?NSOrderedAscending:NSOrderedDescending;
	}];
	
	for(NSNumber* address in addresses)
	{
		[self.cacheImage.header forEachSegmentCommand:^(struct segment_command_64* command)
		{
			if(command->vmaddr==address.longValue)
			{
				[self.header addCommand:(struct load_command*)command];
				
				copied++;
				
				// Ventura assumes __DATA,__objc_imageinfo is right after __TEXT
				// can't adjust addresses without LC_SEGMENT_SPLIT_INFO or very good static analysis
				// so just create a second fake one 😅
				
				if(self.needsObjcImpostor&&!strcmp(command->segname,SEG_TEXT))
				{
					int impostorSize=sizeof(struct segment_command_64)+sizeof(struct section_64);
					
					NSMutableData* impostorData=[NSMutableData dataWithLength:impostorSize];
					
					struct segment_command_64* impostor=(struct segment_command_64*)impostorData.mutableBytes;
					impostor->cmd=LC_SEGMENT_64;
					impostor->cmdsize=impostorSize;
					memcpy(impostor->segname,SEG_DATA,strlen(SEG_DATA));
					impostor->maxprot=VM_PROT_READ;
					impostor->initprot=VM_PROT_READ;
					impostor->nsects=1;
					
					[self.header addCommand:(struct load_command*)impostor];
					
					// finished when importing segments
				}
				
				// Ventura cache builder uniques __got sections into a region outside all images
				// infeasible to restore just needed ones, again lacking LC_SEGMENT_SPLIT_INFO
				// copying the entire thing works...
				
				if(self.needsGotImpostor&&!strcmp(command->segname,"__DATA_CONST"))
				{
					int impostorSize=sizeof(struct segment_command_64)+sizeof(struct section_64);
					
					NSMutableData* impostorData=[NSMutableData dataWithLength:impostorSize];
					
					struct segment_command_64* impostor=(struct segment_command_64*)impostorData.mutableBytes;
					impostor->cmd=LC_SEGMENT_64;
					impostor->cmdsize=impostorSize;
					memcpy(impostor->segname,"dsce.got",9);
					
					// must be writable for binding
					
					impostor->maxprot=VM_PROT_READ|VM_PROT_WRITE;
					impostor->initprot=VM_PROT_READ| VM_PROT_WRITE;
					impostor->nsects=1;
					
					[self.header addCommand:(struct load_command*)impostor];
					
					// finished when importing segments
				}
			}
		}];
	}
	
	[self.cacheImage.header forEachCommand:^(struct load_command* command)
	{
		switch(command->cmd)
		{
			case LC_SEGMENT_64:
				
				// don't count as skipped
				
				break;
			
			case LC_ID_DYLIB:
			case LC_UUID:
			case LC_BUILD_VERSION:
			case LC_SOURCE_VERSION:
			
			case LC_LOAD_DYLIB:
			case LC_LOAD_WEAK_DYLIB:
			case LC_LOAD_UPWARD_DYLIB:
			case LC_REEXPORT_DYLIB:
			
				[self.header addCommand:command];
				copied++;
				break;
			
			// TODO: explicitly list ignored commands, add assert for unrecognied
			
			default:
				skipped++;
		}
	}];
	
	trace(@"copied %x load commands (skipped %x)",copied,skipped);
}

-(void)stepImportSegmentsExceptLinkedit
{
	// TODO: similar problem and workaround as ImageHeader
	
	self.data=[NSMutableData dataWithCapacity:0x100000000];
	
	[self importSegmentsCommon:false];
}

-(void)stepBuildLinkedit
{
	[self importSegmentsCommon:true];
}

// TODO: ugly due to special linkedit treatment
// but difficult to separate without code duplication

-(void)importSegmentsCommon:(BOOL)linkeditPhase
{
	__block struct segment_command_64* nextPrevCommand=NULL;
	
	[self.header forEachSegmentCommand:^(struct segment_command_64* command)
	{
		// TODO: weird
		
		struct segment_command_64* prevCommand=nextPrevCommand;
		nextPrevCommand=command;
		
		BOOL isLinkedit=!strcmp(command->segname,SEG_LINKEDIT);
		if(linkeditPhase!=isLinkedit)
		{
			return;
		}
		
		if(self.needsObjcImpostor&&prevCommand&&!strcmp(prevCommand->segname,SEG_TEXT))
		{
			command->vmaddr=prevCommand->vmaddr+prevCommand->vmsize;
			command->fileoff=self.data.length;
			command->vmsize=0x1000;
			command->filesize=0x1000;
			
			struct section_64* impostor=(struct section_64*)(command+1);
			impostor->offset=command->fileoff;
			impostor->addr=command->vmaddr;
			impostor->size=sizeof(objc_image_info);
			
			struct section_64* original=[self.cacheImage.header sectionCommandWithName:(char*)"__objc_imageinfo"];
			assert(original);
			objc_image_info* originalInfo=(objc_image_info*)wrapOffset(self.cacheImage.file,original->offset).pointer;
			
			objc_image_info* info=(objc_image_info*)wrapOffset(self,impostor->offset).pointer;
			[self.data increaseLengthBy:0x1000];
			memcpy(info,originalInfo,sizeof(objc_image_info));
			
			memcpy(impostor->segname,SEG_DATA,strlen(SEG_DATA));
			memcpy(impostor->sectname,"__objc_imageinfo",16);
			
			trace(@"created __objc_imageinfo impostor");
			
			return;
		}
		
		if(!strcmp(command->segname,"dsce.got"))
		{
			// no obvious way to locate this section, but (so far) it's consistently at the end
			// of the read-only data mapping
			// TODO: may be brittle, and copies slightly more than necessary
			
			long gotStartAddress=align(self.cacheImage.file.maxConstDataSegmentAddress,0x1000,false,NULL);
			long gotEndAddress=self.cacheImage.file.maxConstDataMappingAddress;
			long gotLength=gotEndAddress-gotStartAddress;
			assert(isAligned(gotEndAddress,0x1000));
			
			command->vmaddr=gotStartAddress;
			command->fileoff=self.data.length;
			command->vmsize=gotLength;
			command->filesize=gotLength;
			
			struct section_64* impostor=(struct section_64*)(command+1);
			impostor->offset=command->fileoff;
			impostor->addr=command->vmaddr;
			impostor->size=gotLength;
			memcpy(impostor->sectname,command->segname,strlen(command->segname));
			memcpy(impostor->segname,command->segname,strlen(command->segname));
			
			char* destination=wrapOffset(self,impostor->offset).pointer;
			char* source=wrapAddress(self.cacheImage.file,gotStartAddress).pointer;
			[self.data increaseLengthBy:gotLength];
			memcpy(destination,source,gotLength);
			
			trace(@"copied uniqued __got section (source %lx, length %lx)",gotStartAddress,gotLength);
			
			return;
		}
		
		trace(@"building %s",command->segname);
		
		NSMutableData* data=NSMutableData.alloc.init.autorelease;
		
		// silently fails to mmap segments with un-aligned vmaddr
		// so, move vmaddr to a page boundary, then left-pad to keep section addresses unchanged
		
		int addressDelta;
		long newSegAddress=align(command->vmaddr,0x1000,false,&addressDelta);
		
		// offset is aligned by right-pad at the end of this function
		
		long newSegOffset=self.data.length;
		assert(isAligned(newSegOffset,0x1000));
		
		[data increaseLengthBy:-addressDelta];
		
		[self.header forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* section)
		{
			if(segment==command)
			{
				long newSectOffset=0;
				if(section->offset)
				{
					long fileOffsetInSegment=section->offset-command->fileoff-addressDelta;
					newSectOffset=newSegOffset+fileOffsetInSegment;
				}
				
				section->offset=newSectOffset;
				
				// TODO: remove rather than just renaming?
				
				if(self.needsObjcImpostor&&!strncmp(section->sectname,"__objc_imageinfo",16))
				{
					memcpy(section->sectname,"dsce.objc.old",14);
				}
			}
		}];
		
		// filesize (but not vmsize) must be an integer multiple of page size
		// does not apply to linkedit, and tools complain if there is unused space at the end
		
		unsigned long newSegFileSize;
		unsigned long newSegMemorySize;
		
		if(isLinkedit)
		{
			[self buildLinkeditWithData:data];
			
			newSegFileSize=data.length;
			newSegMemorySize=data.length;
		}
		else
		{
			[data appendBytes:wrapAddress(self.cache,command->vmaddr).pointer length:command->filesize];
			
			newSegFileSize=command->filesize-addressDelta;
			
			int sizeDelta;
			newSegFileSize=align(newSegFileSize,0x1000,true,&sizeDelta);
			[data increaseLengthBy:sizeDelta];
			
			newSegMemorySize=command->vmsize-addressDelta+sizeDelta;
		}
		
		assert(newSegMemorySize>=newSegFileSize);
		
		command->fileoff=newSegOffset;
		command->vmaddr=newSegAddress;
		
		command->filesize=newSegFileSize;
		command->vmsize=newSegMemorySize;
		
		[self.data appendData:data];
	}];
}

-(void)buildLinkeditWithData:(NSMutableData*)data
{
	// checkout.c - dyld info must be at the start of linkedit
	
	[self writeFixupsWithData:data];
	
	[self importLegacyCommandsWithData:data];
}

-(void)writeFixupsWithData:(NSMutableData*)data
{
	assert(isAligned(self.data.length+data.length,0x1000));
	
	struct segment_command_64* linkeditCommand=[self.header segmentCommandWithName:(char*)SEG_LINKEDIT];
	assert(linkeditCommand);
	
	long rebaseStart=data.length;
	
	// TODO: much less space-efficient than compiler output (binds too)
	// possible to steal Apple's implementation like the export trie?
	
	char byte=REBASE_OPCODE_SET_TYPE_IMM|REBASE_TYPE_POINTER;
	[data appendBytes:&byte length:1];
	
	int rebaseCount=0;
	for(Address* fixup in self.fixups.allValues)
	{
		if(!fixup.isRebase)
		{
			continue;
		}
		
		int segmentIndex;
		struct segment_command_64* command=[self.header segmentCommandWithAddress:fixup.address indexOut:&segmentIndex];
		assert(command);
		long segmentOffset=fixup.address-command->vmaddr;
		
		byte=REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB|segmentIndex;
		[data appendBytes:&byte length:1];
		[data appendData:ulebWithLong(segmentOffset)];
		
		byte=REBASE_OPCODE_DO_REBASE_IMM_TIMES|1;
		[data appendBytes:&byte length:1];
		
		rebaseCount++;
	}
	
	byte=REBASE_OPCODE_DONE;
	[data appendBytes:&byte length:1];
	
	long rebaseLength=data.length-rebaseStart;
	
	// MachOAnalyzer.cpp - must be 8 byte aligned
	
	int padding;
	align(data.length,8,true,&padding);
	[data increaseLengthBy:padding];
	
	long bindStart=data.length;
	
	byte=BIND_OPCODE_SET_TYPE_IMM|BIND_TYPE_POINTER;
	[data appendBytes:&byte length:1];
	
	int bindCount=0;
	for(Address* fixup in self.fixups.allValues)
	{
		if(!fixup.isBind)
		{
			continue;
		}
		
		int segmentIndex;
		struct segment_command_64* command=[self.header segmentCommandWithAddress:fixup.address indexOut:&segmentIndex];
		assert(command);
		long segmentOffset=fixup.address-command->vmaddr;
		
		byte=BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB;
		[data appendBytes:&byte length:1];
		[data appendData:ulebWithLong(fixup.dylibOrdinal)];
		
		byte=BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB|segmentIndex;
		[data appendBytes:&byte length:1];
		[data appendData:ulebWithLong(segmentOffset)];
		
		byte=BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM|0;
		[data appendBytes:&byte length:1];
		[data appendBytes:fixup.name.UTF8String length:fixup.name.length+1];
		
		if(!!fixup.addend)
		{
			// TODO: implement SLEB if needed
			
			assert(fixup.addend>0);
			
			byte=BIND_OPCODE_SET_ADDEND_SLEB;
			[data appendBytes:&byte length:1];
			[data appendData:ulebWithLong(fixup.addend)];
		}
		
		byte=BIND_OPCODE_DO_BIND;
		[data appendBytes:&byte length:1];
		
		if(!!fixup.addend)
		{
			// addend persists across binds and breaks everything otherwise
			
			byte=BIND_OPCODE_SET_ADDEND_SLEB;
			[data appendBytes:&byte length:1];
			[data appendData:ulebWithLong(0)];
		}
		
		bindCount++;
	}
	
	byte=BIND_OPCODE_DONE;
	[data appendBytes:&byte length:1];
	
	long bindLength=data.length-bindStart;
	
	align(data.length,8,true,&padding);
	[data increaseLengthBy:padding];
	
	long exportStart=data.length;
	
	// instead of trying to write a trie generator (terrifying) just use Apple's
	// Trie.hpp, SharedCacheBuilder.cpp
	
	long reexportCount=0;
	
	std::vector<ExportInfoTrie::Entry> trieEntries;
	for(Address* item in self.exports)
	{
		assert(item.isExport||item.isReexport);
		
		struct ExportInfo info={};
		if(item.address)
		{
			info.address=item.address-self.cacheImage.baseAddress;
		}
		
		if(item.isReexport)
		{
			info.flags=EXPORT_SYMBOL_FLAGS_REEXPORT;
			info.importName=std::string(item.importName.UTF8String);
			info.other=item.dylibOrdinal;
			reexportCount++;
		}
		else
		{
			info.flags=EXPORT_SYMBOL_FLAGS_KIND_REGULAR;
		}
		
		ExportInfoTrie::Entry entry(std::string(item.name.UTF8String),info);
		trieEntries.push_back(entry);
	}
	
	ExportInfoTrie trie(trieEntries);
	std::vector<unsigned char> trieBytes;
	trie.emit(trieBytes);
	[data appendBytes:trieBytes.data() length:trieBytes.size()];
	
	// to avoid gap before symtab, the padding is counted as part of the exports trie
	// this is not an issue since the structure defines its own end
	
	align(data.length,0x1000,true,&padding);
	[data increaseLengthBy:padding];
	
	long exportLength=data.length-exportStart;
	
	// TODO: any difference between LC_DYLD_INFO and LC_DYLD_INFO_ONLY?
	
	struct dyld_info_command command={};
	command.cmd=LC_DYLD_INFO;
	command.cmdsize=sizeof(struct dyld_info_command);
	
	command.rebase_off=self.data.length+rebaseStart;
	command.rebase_size=rebaseLength;
	command.bind_off=self.data.length+bindStart;
	command.bind_size=bindLength;
	command.export_off=self.data.length+exportStart;
	command.export_size=exportLength;
	
	[self.header addCommand:(struct load_command*)&command];
	
	trace(@"generated %x rebases (%lx bytes), %x binds (%lx bytes), %x exports (%lx re-exports, %lx bytes), total size %lx",rebaseCount,rebaseLength,bindCount,bindLength,trieEntries.size(),reexportCount,exportLength,data.length);
}

// LC_SYMTAB and LC_DYSYMTAB are completely superseded by LC_DYLD_INFO for linking
// purely needed for nm and Hopper external symbols
// TODO: not entirely sure this still works correctly in Ventura, particularly with __got uniquing

-(void)importLegacyCommandsWithData:(NSMutableData*)data
{
	// checkout.c - order must be symbols, indirects, strings with no gaps
	// MachOAnalyzer.cpp - must be 8 byte aligned
	
	long symbolsStart=self.data.length+data.length;
	
	// should be aligned by writeFixupsWithData:
	
	assert(isAligned(symbolsStart,0x1000));
	
	NSMutableData* stringsData=NSMutableData.alloc.init.autorelease;
	
	// zero string table offset is interpreted as null symbol name
	
	[stringsData increaseLengthBy:1];
	
	__block int symbolCount=0;
	[self.cacheImage forEachLegacySymbol:^(struct nlist_64* cacheEntry,char* name)
	{
		struct nlist_64 entry={};
		memcpy(&entry,cacheEntry,sizeof(struct nlist_64));
		entry.n_un.n_strx=stringsData.length;
		
		if(entry.n_value)
		{
			assert(entry.n_value!=-1);
		}
		
		[data appendBytes:&entry length:sizeof(struct nlist_64)];
		
		[stringsData appendBytes:name length:strlen(name)+1];
		
		symbolCount++;
	}];
	
	struct dysymtab_command* cacheDysymtabCommand=(struct dysymtab_command*)[self.cacheImage.header commandWithType:LC_DYSYMTAB];
	assert(cacheDysymtabCommand);
	
	long indirectStart=self.data.length+data.length;
	
	// should be 8-byte aligned since nlist_64 are 16 bytes
	
	assert(isAligned(indirectStart,8));
	
	long indirectSize=cacheDysymtabCommand->nindirectsyms*sizeof(int);
	[data appendBytes:wrapOffset(self.cacheImage.file,cacheDysymtabCommand->indirectsymoff).pointer length:indirectSize];
	
	// TODO: this is only guaranteed to be aligned to 4 bytes
	// not sure if that's a problem or not
	
	long stringsStart=self.data.length+data.length;
	
	[data appendData:stringsData];
	
	struct symtab_command symtabCommand={};
	symtabCommand.cmd=LC_SYMTAB;
	symtabCommand.cmdsize=sizeof(struct symtab_command);
	symtabCommand.symoff=symbolsStart;
	symtabCommand.nsyms=symbolCount;
	symtabCommand.stroff=stringsStart;
	symtabCommand.strsize=stringsData.length;
	
	[self.header addCommand:(struct load_command*)&symtabCommand];
	
	struct dysymtab_command dysymtabCommand={};
	dysymtabCommand.cmd=LC_DYSYMTAB;
	dysymtabCommand.cmdsize=sizeof(struct dysymtab_command);
	dysymtabCommand.indirectsymoff=indirectStart;
	dysymtabCommand.nindirectsyms=cacheDysymtabCommand->nindirectsyms;
	
	[self.header addCommand:(struct load_command*)&dysymtabCommand];
	
	trace(@"copied %lx symtab entries, %lx bytes of indirect entries, %lx bytes of strings",symbolCount,indirectSize,stringsData.length);
}

-(long)addressWithOffset:(long)offset
{
	struct segment_command_64* command=[self.header segmentCommandWithOffset:offset indexOut:NULL];
	if(!command)
	{
		return -1;
	}
	
	long segmentOffset=offset-command->fileoff;
	return command->vmaddr+segmentOffset;
	
	// Location checks address validity
}

-(long)addressWithPointer:(char*)pointer
{
	return [self addressWithOffset:pointer-(char*)self.data.mutableBytes];
}

-(long)offsetWithAddress:(long)address
{
	struct segment_command_64* command=[self.header segmentCommandWithAddress:address indexOut:NULL];
	if(!command)
	{
		return -1;
	}
	
	long segmentOffset=address-command->vmaddr;
	long offset=command->fileoff+segmentOffset;
	
	__block BOOL inSection=false;
	[self.header forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* section)
	{
		if(segment==command)
		{
			if(address>=section->addr&&address<section->addr+section->size)
			{
				inSection=true;
			}
		}
	}];
	
	if(!inSection)
	{
		return -1;
	}
	
	return offset;
}

-(char*)pointerWithAddress:(long)address
{
	return (char*)self.data.mutableBytes+[self offsetWithAddress:address];
}

-(void)stepImportRebases
{
	self.fixups=NSMutableDictionary.alloc.init.autorelease;
	
	// TODO: extremely slow, could find bounds via binary search, or at least exit early
	
	for(NSNumber* rebase in self.cacheImage.file.rebaseAddresses)
	{
		Location* location=wrapAddressUnsafe(self,rebase.longValue);
		
		if(!location)
		{
			continue;
		}
		
		NSNumber* key=[NSNumber numberWithLong:location.address];
		self.fixups[key]=[Address rebaseWithAddress:location.address];
	}
	
	trace(@"found %x rebases",self.fixups.count);
}

-(void)stepImportExports
{
	self.exports=self.cacheImage.exports.copy;
	self.exports.autorelease;
	
	trace(@"found %lx exports",self.exports.count);
}

-(void)stepFixImageInfo
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_imageinfo"];
	if(!section)
	{
		return;
	}
	
	objc_image_info* info=(objc_image_info*)wrapOffset(self,section->offset).pointer;
	
	// prevents crash in map_images_nolock
	
	int oldFlags=info->flags;
	info->flags&=~OptimizedByDyld;
	
	trace(@"objc version %x flags %x (was %x)",info->version,info->flags,oldFlags);
}

// TODO: move to Cache

-(void)stepFindMagicSel
{
	CacheImage* image=[self.cache imagesWithPathPrefix:@"/usr/lib/libobjc.A.dylib"].firstObject;
	assert(image);
	
	struct section_64* section=[image.header sectionCommandWithName:(char*)"__objc_selrefs"];
	assert(section);
	
	long* refs=(long*)wrapOffset(image.file,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	for(int index=0;index<count;index++)
	{
		char* name=wrapAddress(self.cache,refs[index]).pointer;
		
		if(name&&!strcmp(name,"\xf0\x9f\xa4\xaf"))
		{
			self.magicSelAddress=refs[index];
			break;
		}
	}
	
	assert(self.magicSelAddress);
}

// selector strings get uniqued and copied to libobjc, but originals remain (for now)
// just revert the pointers without copying any strings

-(void)stepFindEmbeddedSels
{
	self.sels=NSMutableDictionary.alloc.init.autorelease;
	
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_methname"];
	if(!section)
	{
		return;
	}
	
	char* name=wrapOffset(self,section->offset).pointer;
	char* end=name+section->size;
	while(name<end)
	{
		Selector* sel=Selector.alloc.init.autorelease;
		sel.stringAddress=wrapPointer(self,name).address;
		self.sels[[NSString stringWithUTF8String:name]]=sel;
		
		name+=strlen(name)+1;
	}
	
	trace(@"found %x embedded selectors",self.sels.count);
}

-(void)stepFixSelRefs
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_selrefs"];
	if(!section)
	{
		return;
	}
	
	long* refs=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	trace(@"fixing %x selector refs",count);
	
	for(int index=0;index<count;index++)
	{
		NSString* name=[NSString stringWithUTF8String:wrapAddress(self.cache,refs[index]).pointer];
		
		refs[index]=[self selStringAddressWithName:name];
		
		long refAddress=wrapPointer(self,(char*)&refs[index]).address;
		self.sels[name].refAddress=refAddress;
	}
}

-(long)selRefAddressWithName:(NSString*)target
{
	Selector* sel=self.sels[target];
	assert(sel);
	
	return sel.refAddress;
}

-(long)selStringAddressWithName:(NSString*)target
{
	Selector* sel=self.sels[target];
	assert(sel);
	
	return sel.stringAddress;
}

-(void)stepFixClasses
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_classlist"];
	if(!section)
	{
		return;
	}
	
	long* classes=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	trace(@"fixing %x classes",count);
	
	for(int index=0;index<count;index++)
	{
		struct objc_class* cls=(struct objc_class*)wrapAddress(self,classes[index]).pointer;
		struct objc_data* data=(struct objc_data*)wrapAddress(self,(long)cls->data).pointer;
		struct objc_class* metaCls=(struct objc_class*)wrapAddress(self,(long)cls->metaclass).pointer;
		struct objc_data* metaData=(struct objc_data*)wrapAddress(self,(long)metaCls->data).pointer;
		
		// superclass/metaclass pointers now auto-fixed
		
		[self fixMethodListWithAddress:(long)data->baseMethods];
		[self fixMethodListWithAddress:(long)metaData->baseMethods];
		[self fixProtoListWithAddress:(long)data->baseProtocols];
		[self fixProtoListWithAddress:(long)metaData->baseProtocols];
	}
}

-(void)stepFixCats
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_catlist"];
	if(!section)
	{
		return;
	}
	
	long* cats=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	trace(@"fixing %x categories",count);
	
	for(int index=0;index<count;index++)
	{
		struct objc_category* cat=(struct objc_category*)wrapAddress(self,cats[index]).pointer;
		
		[self fixMethodListWithAddress:(long)cat->instanceMethods];
		[self fixMethodListWithAddress:(long)cat->classMethods];
		[self fixProtoListWithAddress:(long)cat->protocols];
	}
}

// like selectors, these have been uniqued, but the originals aren't removed

-(void)stepFixProtoRefs
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_protorefs"];
	if(!section)
	{
		return;
	}
	
	long* refs=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	trace(@"fixing %x protocol refs",count);
	
	for(int index=0;index<count;index++)
	{
		struct objc_protocol* proto=(struct objc_protocol*)wrapAddress(self.cache,refs[index]).pointer;
		
		char* name=wrapAddress(self.cache,(long)proto->name).pointer;
		refs[index]=[self embeddedProtoAddressWithName:name];
	}
}

-(void)stepFixProtos
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_protolist"];
	if(!section)
	{
		return;
	}
	
	long* refs=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	trace(@"fixing %x protocols",count);
	
	for(int index=0;index<count;index++)
	{
		struct objc_protocol* proto=(struct objc_protocol*)wrapAddress(self,refs[index]).pointer;
		
		[self fixMethodListWithAddress:(long)proto->instanceMethods];
		[self fixMethodListWithAddress:(long)proto->classMethods];
		[self fixMethodListWithAddress:(long)proto->optionalInstanceMethods];
		[self fixMethodListWithAddress:(long)proto->optionalClassMethods];
		[self fixProtoListWithAddress:(long)proto->protocols];
	}
}

// TODO: improve performance with a map (like selectors)

-(long)embeddedProtoAddressWithName:(char*)target
{
	struct section_64* section=[self.header sectionCommandWithName:(char*)"__objc_protolist"];
	assert(section);
	
	long* refs=(long*)wrapOffset(self,section->offset).pointer;
	int count=section->size/sizeof(long*);
	
	for(int index=0;index<count;index++)
	{
		struct objc_protocol* proto=(struct objc_protocol*)wrapAddress(self,refs[index]).pointer;
		char* name=wrapAddress(self,(long)proto->name).pointer;
		
		if(!strcmp(name,target))
		{
			return refs[index];
		}
	}
	
	abort();
}

-(void)fixProtoListWithAddress:(long)address
{
	if(!address)
	{
		return;
	}
	
	// TODO: there should be a struct for this like method lists
	
	long* list=(long*)wrapAddress(self,address).pointer;
	int count=list[0];
	
	for(int index=1;index<count+1;index++)
	{
		if(wrapAddressUnsafe(self,list[index]))
		{
			// some already point within me
			
			continue;
		}
		
		struct objc_protocol* proto=(struct objc_protocol*)wrapAddress(self.cache,list[index]).pointer;
		char* name=wrapAddress(self.cache,(long)proto->name).pointer;
		
		list[index]=[self embeddedProtoAddressWithName:name];
	}
}

-(void)fixMethodListWithAddress:(long)address
{
	if(!address)
	{
		return;
	}
	
	struct objc_method_list* header=(struct objc_method_list*)wrapAddress(self,address).pointer;
	
	char* methods=(char*)(header+1);
	
	for(int index=0;index<header->count;index++)
	{
		// two method list formats, both actively used
		
		if(header->flags&usesRelativeOffsets)
		{
			// TODO: confirm these flags mean exactly what i think
			
			assert(header->flags&usesDirectOffsetsToSelectors);
			
			struct objc_relative_method* method=(struct objc_relative_method*)(methods+sizeof(struct objc_relative_method)*index);
			
			long nameAddress=method->name+self.magicSelAddress;
			NSString* name=[NSString stringWithUTF8String:wrapAddress(self.cache,nameAddress).pointer];
			
			long address=[self selRefAddressWithName:name];
			int relative=address-wrapPointer(self,(char*)method).address;
			method->name=relative;
		}
		else
		{
			struct objc_method* method=(struct objc_method*)(methods+sizeof(struct objc_method)*index);
			
			NSString* name=[NSString stringWithUTF8String:wrapAddress(self.cache,(long)method->name).pointer];
			
			method->name=(char*)[self selStringAddressWithName:name];
		}
	}
	
	// remove flags marking method list as already processed
	// fixes protocols seeming to work but having multiple distinct selectors with the same name
	// e.g. AppKit spelling XPC service weirdness
	
	// TODO: names and check
	
	header->flags&=~0x3;
}

-(void)stepFixPointersNew
{
	trace(@"scanning %lx rebases",self.fixups.count);
	
	long internalCount=0;
	long cppCount=0;
	long unresolvedCount=0;
	long unreachableCount=0;
	long successCount=0;
	
	for(NSNumber* key in self.fixups.allKeys)
	{
		Address* rebase=self.fixups[key];
		assert(rebase.isRebase);
		
		long destination=*(long*)wrapAddress(self,rebase.address).pointer;
		
		if(wrapAddressUnsafe(self,destination))
		{
			// internal pointer, only needs rebase
			
			internalCount++;
			continue;
		}
		
		CacheImage* image=[self.cache imageWithAddress:destination];
		assert(image);
		
		// delete rebase (usually overwritten but can exit early)
		// TODO: also zero/mark the destination for debugging?
		
		self.fixups[key]=nil;
		
		int addend=0;
		
		Address* item=[image exportWithAddress:destination];
		if(!item)
		{
			// found an image but no corresponding symbol name
			
			if([image.path containsString:@"libc++abi"])
			{
				// hack for C++ vtables in particular images (e.g. AMDRadeonVADriver2)
				// this shifts the pointer inside the imported image
				// matches observed binds in uncached Big Sur beta dylibs
				
				cppCount++;
				
				destination-=0x10;
				item=[image exportWithAddress:destination];
				assert(item);
				
				addend=0x10;
			}
			else
			{
				// TODO: this should never happen...
				// indicates either bugs, or better addend heuristic?
				
				unresolvedCount++;
				continue;
			}
		}
		
		NSString* name=item.name;
		int ordinal=[self.header ordinalWithDylibPath:image.path cache:self.cache symbol:name newSymbolOut:&name];
		if(ordinal==-1)
		{
			// resolved to a particular image+symbol, but can't reach that image via imports
			// TODO: often occurs due to __got uniquing, should never happen otherwise
			// at least we should detect which of the two it is...
			
			unreachableCount++;
			continue;
		}
		
		successCount++;
		self.fixups[key]=[Address bindWithAddress:rebase.address ordinal:ordinal name:name addend:addend];
	}
	
	trace(@"found %lx binds (%lx via C++ hack), skipped %lx internal pointers, failed to resolve %lx addresses to symbols, failed to reach %lx dylibs in imports tree",successCount,cppCount,internalCount,unresolvedCount,unreachableCount);
}

-(void)stepMarkUUID
{
	struct uuid_command* command=(struct uuid_command*)[self.header commandWithType:LC_UUID];
	
	// memcpy(command->uuid,"Amy",4);
	
	assert(DSCE_VERSION<0x100);
	char info[4]={};
	info[0]=0xd5;
	info[1]=0xce;
	info[3]=DSCE_VERSION;
	memcpy(command->uuid,info,4);
	
	NSUUID* newUUID=[NSUUID.alloc initWithUUIDBytes:command->uuid].autorelease;
	trace(@"updated uuid to %@",newUUID.UUIDString);
}

-(void)stepSyncHeader
{
	// TODO: ensure we don't overrun TEXT
	
	trace(@"syncing modified header (%lx bytes)",self.header.data.length);
	
	memcpy(self.data.mutableBytes,self.header.data.mutableBytes,self.header.data.length);
}

@end