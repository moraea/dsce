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

+(void)runWithCache:(Cache*)cache image:(Image*)image outPath:(NSString*)outPath
{
	trace(@"begin extraction %@",image.path);
	
	Output* output=[Output.alloc initWithCache:cache image:image].autorelease;
	[output extractWithPath:outPath];
	[output signAndSetPermissions:outPath];
}

-(instancetype)initWithCache:(Cache*)cache image:(Image*)image
{
	self=super.init;
	
	assert(cache);
	self.cache=cache;
	
	assert(image);
	self.cacheImage=image;
	
	return self;
}

-(void)extractWithPath:(NSString*)outPath
{
	// TODO: calling this multiple times on one instance would be bad
	
	NSArray<NSString*>* steps=@[@"stepImportHeader",@"stepImportSegmentsExceptLinkedit",@"stepImportRebases",@"stepFixImageInfo",@"stepFindMagicSel",@"stepFindEmbeddedSels",@"stepFixSelRefs",@"stepFixClasses",@"stepFixCats",@"stepFixProtoRefs",@"stepFixProtos",@"stepFixSymbolPointers",@"stepFixOtherPointers",@"stepBuildLinkedit",@"stepMarkUUID",@"stepSyncHeader"];
	
	for(NSString* step in steps)
	{
		// trace(@"enter %@",step);
		
		[self performSelector:NSSelectorFromString(step)];
	}
	
	trace(@"write %@",outPath);
	[self.data writeToFile:outPath atomically:false];

}

-(void)signAndSetPermissions:(NSString*)outPath
{
	/*
	Fix binary for usage in-OS:
	   codesign -f -s - <binary>
	   chmod -f 775 <binary>
	   chown -f root:wheel <binary>
	*/

	trace(@"codesigning and setting permissions on binary: %@",outPath);

	NSTask* task=NSTask.alloc.init;

	// codesign -f -s - <binary>
	task.launchPath=@"/usr/bin/codesign";
	task.arguments=@[@"-f",@"-s",@"-",outPath];
	task.standardOutput=NSPipe.pipe;
	task.standardError=NSPipe.pipe;
	[task launch];
	[task waitUntilExit];

	// chmod -f 775 <binary>
	task=NSTask.alloc.init;
	task.launchPath=@"/bin/chmod";
	task.arguments=@[@"-f",@"775",outPath];
	task.standardOutput=NSPipe.pipe;
	task.standardError=NSPipe.pipe;
	[task launch];
	[task waitUntilExit];

	// chown -f root:wheel <binary>
	task=NSTask.alloc.init;
	task.launchPath=@"/usr/sbin/chown";
	task.arguments=@[@"-f",@"root:wheel",outPath];
	task.standardOutput=NSPipe.pipe;
	task.standardError=NSPipe.pipe;
	[task launch];
	[task waitUntilExit];
}

-(void)stepImportHeader
{
	self.header=ImageHeader.alloc.initEmpty.autorelease;
	
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
				return;
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
	
	self.segmentLeftPads=NSMutableArray.alloc.init.autorelease;
	self.segmentRightPads=NSMutableArray.alloc.init.autorelease;
	
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
	[self.header forEachSegmentCommand:^(struct segment_command_64* command)
	{
		BOOL isLinkedit=!strcmp(command->segname,SEG_LINKEDIT);
		if(linkeditPhase&&!isLinkedit)
		{
			return;
		}
		if(!linkeditPhase&&isLinkedit)
		{
			return;
		}
		
		trace(@"copying %s",command->segname);
		
		NSMutableData* data=NSMutableData.alloc.init.autorelease;
		
		long oldAddress=command->vmaddr;
		long oldSize=command->filesize;
		
		// vmaddr must be page aligned, move left to nearest page boundary
		// pad so the addresses of given data are not changed
		
		int addressDelta;
		command->vmaddr=align(command->vmaddr,0x1000,false,&addressDelta);
		assert(addressDelta<=0);
		
		NSMutableData* leftPad=[NSMutableData dataWithLength:-addressDelta];
		
		long offsetDelta=self.data.length-command->fileoff;
		command->fileoff+=offsetDelta;
		assert(offsetDelta<0);
		
		// line up sections with new offsets
		
		[self.header forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* section)
		{
			if(segment==command)
			{
				if(!section->offset)
				{
					// zero-fill
					
					return;
				}
				
				section->offset+=offsetDelta+leftPad.length;
			}
		}];
		
		[data appendData:leftPad];
		
		if(isLinkedit)
		{
			[self buildLinkeditWithData:data];
			
			command->filesize=data.length;
			command->vmsize=data.length;
		}
		else
		{
			[data appendBytes:wrapAddress(self.cache,oldAddress).pointer length:oldSize];
		}
		
		// filesize (but not vmsize) must be an integer multiple of page size
		// this does not seem to apply to linkedit
		// and tools complain if there is unused space at the end
		
		int sizeDelta=0;
		
		if(!isLinkedit)
		{
			command->filesize=align(data.length,0x1000,true,&sizeDelta);
			assert(sizeDelta>=0);
		}
		
		NSMutableData* rightPad=[NSMutableData dataWithLength:sizeDelta];
		[data appendData:rightPad];
		
		// TODO: correct?
		
		command->vmsize+=leftPad.length+rightPad.length;
		
		[self.data appendData:data];
		
		[self.segmentLeftPads addObject:[NSNumber numberWithInt:leftPad.length]];
		[self.segmentRightPads addObject:[NSNumber numberWithInt:rightPad.length]];
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
	int rebaseSkipCount=0;
	for(Rebase* fixup in self.rebases.allValues)
	{
		if([self hasBindWithAddress:fixup.address])
		{
			rebaseSkipCount++;
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
	for(Bind* fixup in self.binds.allValues)
	{
		int segmentIndex;
		struct segment_command_64* command=[self.header segmentCommandWithAddress:fixup.address indexOut:&segmentIndex];
		assert(command);
		long segmentOffset=fixup.address-command->vmaddr;
		
		byte=BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB;
		[data appendBytes:&byte length:1];
		[data appendData:ulebWithLong(fixup.ordinal)];
		
		byte=BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB|segmentIndex;
		[data appendBytes:&byte length:1];
		[data appendData:ulebWithLong(segmentOffset)];
		
		byte=BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM|0;
		[data appendBytes:&byte length:1];
		[data appendBytes:fixup.symbol.UTF8String length:fixup.symbol.length+1];
		
		byte=BIND_OPCODE_DO_BIND;
		[data appendBytes:&byte length:1];
		
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
	
	long baseAddress=wrapOffset(self,0).address;
	long reexportCount=0;
	
	std::vector<ExportInfoTrie::Entry> trieEntries;
	for(Symbol* item in self.cacheImage.symbols.allValues)
	{
		if(!item.isExport)
		{
			continue;
		}
		
		struct ExportInfo info;
		info.address=item.address-baseAddress;
		
		if(item.importName)
		{
			info.flags=EXPORT_SYMBOL_FLAGS_REEXPORT;
			info.importName=std::string(item.importName.UTF8String);
			info.other=item.importOrdinal;
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
	
	trace(@"generated %x rebases (%x skipped, %lx bytes), %x binds (%lx bytes), %x exports (%lx re-exports, %lx bytes), total size %lx",rebaseCount,rebaseSkipCount,rebaseLength,bindCount,bindLength,trieEntries.size(),reexportCount,exportLength,data.length);
}

// LC_SYMTAB and LC_DYSYMTAB are completely superseded by LC_DYLD_INFO for linking
// and extraction uses cached versions
// purely needed for nm and Hopper external symbols

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
	[self.cacheImage forEachSymbol:^(struct nlist_64* cacheEntry,char* name)
	{
		struct nlist_64 entry={};
		memcpy(&entry,cacheEntry,sizeof(struct nlist_64));
		entry.n_un.n_strx=stringsData.length;
		
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
	int segmentIndex;
	struct segment_command_64* command=[self.header segmentCommandWithOffset:offset indexOut:&segmentIndex];
	if(!command)
	{
		return -1;
	}
	
	long segmentOffset=offset-command->fileoff;
	
	if([self inPaddingWithSegmentIndex:segmentIndex offset:segmentOffset length:command->filesize])
	{
		return -1;
	}
	
	return command->vmaddr+segmentOffset;
}

-(long)addressWithPointer:(char*)pointer
{
	return [self addressWithOffset:pointer-(char*)self.data.mutableBytes];
}

-(long)offsetWithAddress:(long)address
{
	int segmentIndex;
	struct segment_command_64* command=[self.header segmentCommandWithAddress:address indexOut:&segmentIndex];
	if(!command)
	{
		return -1;
	}
	
	long segmentOffset=address-command->vmaddr;
	
	if([self inPaddingWithSegmentIndex:segmentIndex offset:segmentOffset length:command->vmsize])
	{
		return -1;
	}
	
	return command->fileoff+segmentOffset;
}

-(char*)pointerWithAddress:(long)address
{
	return (char*)self.data.mutableBytes+[self offsetWithAddress:address];
}

-(BOOL)inPaddingWithSegmentIndex:(int)index offset:(long)offset length:(long)length
{
	if(offset<self.segmentLeftPads[index].intValue)
	{
		return true;
	}
	if(length-offset<self.segmentRightPads[index].intValue)
	{
		return true;
	}
	
	return false;
}

-(void)stepImportRebases
{
	self.rebases=NSMutableDictionary.alloc.init.autorelease;
	self.binds=NSMutableDictionary.alloc.init.autorelease;
	
	// TODO: extremely slow
	// addresses are sorted, could find bounds via binary search
	
	for(NSNumber* rebase in self.cacheImage.file.rebaseAddresses)
	{
		if([self.header segmentCommandWithAddress:rebase.longValue indexOut:NULL])
		{
			[self addRebaseWithAddress:rebase.longValue];
		}
	}
	
	trace(@"copied %x rebases",self.rebases.count);
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

// TODO: this could be in Cache

-(void)stepFindMagicSel
{
	Image* image=[self.cache imagesWithPathPrefix:@"/usr/lib/libobjc.A.dylib"].firstObject;
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
			trace(@"magic selector name %@ address %lx",[NSString stringWithUTF8String:name],self.magicSelAddress);
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
		
		// superclass/metaclass pointers now auto-fixed by stepFixOtherPointers
		
		if(data->baseMethods)
		{
			[self fixMethodListWithAddress:(long)data->baseMethods];
		}
		if(metaData->baseMethods)
		{
			[self fixMethodListWithAddress:(long)metaData->baseMethods];
		}
		
		if(data->baseProtocols)
		{
			[self fixProtoListWithAddress:(long)data->baseProtocols];
		}
		if(metaData->baseProtocols)
		{
			[self fixProtoListWithAddress:(long)metaData->baseProtocols];
		}
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
		
		if(cat->instanceMethods)
		{
			[self fixMethodListWithAddress:(long)cat->instanceMethods];
		}
		if(cat->classMethods)
		{
			[self fixMethodListWithAddress:(long)cat->classMethods];
		}
		
		if(cat->protocols)
		{
			[self fixProtoListWithAddress:(long)cat->protocols];
		}
	}
}

// TODO: purely from looking in Hopper

-(void)fixProtoListWithAddress:(long)address
{
	long* list=(long*)wrapAddress(self,address).pointer;
	int count=list[0];
	
	for(int index=1;index<count+1;index++)
	{
		struct objc_protocol* proto=(struct objc_protocol*)wrapAddress(self.cache,list[index]).pointer;
		char* name=wrapAddress(self.cache,(long)proto->name).pointer;
		
		list[index]=[self embeddedProtoAddressWithName:name];
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
		char* name=wrapAddress(self,(long)proto->name).pointer;
		
		if(proto->instanceMethods)
		{
			[self fixMethodListWithAddress:(long)proto->instanceMethods];
		}
		if(proto->classMethods)
		{
			[self fixMethodListWithAddress:(long)proto->classMethods];
		}
		if(proto->optionalInstanceMethods)
		{
			[self fixMethodListWithAddress:(long)proto->optionalInstanceMethods];
		}
		if(proto->optionalClassMethods)
		{
			[self fixMethodListWithAddress:(long)proto->optionalClassMethods];
		}
		
		if(proto->protocols)
		{
			[self fixProtoListWithAddress:(long)proto->protocols];
		}
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

// transfer S_NON_LAZY_SYMBOL_POINTERS from indirect symbol table (ignored) to dyld info binds

-(void)stepFixSymbolPointers
{
	struct dysymtab_command* dysymtab=(struct dysymtab_command*)[self.cacheImage.header commandWithType:LC_DYSYMTAB];
	unsigned int* indirects=(unsigned int*)wrapOffset(self.cacheImage.file,dysymtab->indirectsymoff).pointer;
	
	[self.header forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* section)
	{
		if((section->flags&SECTION_TYPE)!=S_NON_LAZY_SYMBOL_POINTERS)
		{
			return;
		}
		
		long* data=(long*)wrapOffset(self,section->offset).pointer;
		int count=section->size/sizeof(long*);
		
		trace(@"binding %x symbol pointers in %s",count,section->sectname);
		
		for(int index=0;index<count;index++)
		{
			long address=wrapPointer(self,(char*)&data[index]).address;
			
			unsigned int indirectIndex=section->reserved1+index;
			assert(indirectIndex<dysymtab->nindirectsyms);
			unsigned int symbolIndex=indirects[indirectIndex];
			
			[self addBindWithAddress:address symbolIndex:symbolIndex symbolName:nil];
		}
	}];
}

// scan for things that look like pointers and try to fix them

-(void)stepFixOtherPointers
{
	// TODO: false positives?
	// TODO: reduce the chance by denylisting sections in TEXT?
	
	__block long sectionCount=0;
	__block long bindCount=0;
	__block long errorCount=0;
	
	[self.header forEachSectionCommand:^(struct segment_command_64* segment,struct section_64* section)
	{
		if(section->offset==0)
		{
			// zero-fill
			
			return;
		}
		
		sectionCount++;
		
		long* data=(long*)wrapOffset(self,section->offset).pointer;
		int count=section->size/sizeof(long*);
		
		for(int index=0;index<count;index++)
		{
			long address=data[index];
			
			if(!wrapAddressUnsafe(self.cache,address))
			{
				// not an address
				
				continue;
			}
			
			long refAddress=wrapPointer(self,(char*)&data[index]).address;
			
			if(wrapAddressUnsafe(self,address))
			{
				// an address, but points inside me
				
				continue;
			}
			
			if([self hasBindWithAddress:refAddress])
			{
				// points outside me but already has bind
				
				continue;
			}
			
			// TODO: determine the causes of these errors
			// and see if they can (and should) be corrected
			
			Image* image=[self.cache imageWithAddress:address];
			if(!image)
			{
				// trace(@"CANNOT determine image for address %lx",address);
				
				errorCount++;
				continue;
			}
			
			Symbol* item=[image exportWithAddress:address];
			if(!item)
			{
				// trace(@"CANNOT resolve name for address %lx in image %@",address,image.path);
				
				errorCount++;
				continue;
			}
			
			[self addBindWithAddress:refAddress symbolIndex:-1 symbolName:item.name];
			
			bindCount++;
		}
	}];
	
	trace(@"scanned %lx sections and generated %lx binds (%lx errors)",sectionCount,bindCount,errorCount);
}

-(void)fixMethodListWithAddress:(long)address
{
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

-(void)addBindWithAddress:(long)address symbolIndex:(int)targetIndex symbolName:(NSString*)targetName
{
	__block int index=0;
	__block BOOL found=false;
	
	Symbol* item=nil;
	
	if(targetIndex!=-1)
	{
		item=[self.cacheImage importWithIndex:targetIndex];
	}
	
	if(targetName)
	{
		assert(!item);
		item=[self.cacheImage importWithName:targetName];
	}
	
	if(!item)
	{
		// TODO: why does this happen with some __got pointers?
		
		// trace(@"CANNOT resolve address %lx target index %x target name %@",address,targetIndex,targetName);
		
		return;
	}
	
	if(item.importOrdinal==SELF_LIBRARY_ORDINAL)
	{
		// TODO: any special behavior needed for this?
	}
	
	[self addBindWithAddress:address ordinal:item.importOrdinal symbol:item.importName];
}

-(BOOL)hasBindWithAddress:(long)address
{
	return !!self.binds[[NSNumber numberWithLong:address]];
}

// TODO: unused now
// logically, the cache header should always contain all rebases needed by any image
// but it may be a good idea to add some asserts again

-(BOOL)hasRebaseWithAddress:(long)address
{
	return !!self.rebases[[NSNumber numberWithLong:address]];
}

-(void)addBindWithAddress:(long)address ordinal:(int)ordinal symbol:(NSString*)symbol
{
	Bind* bind=[Bind bindWithAddress:address ordinal:ordinal symbol:symbol];
	self.binds[[NSNumber numberWithLong:address]]=bind;
}

-(void)addRebaseWithAddress:(long)address
{
	Rebase* rebase=[Rebase rebaseWithAddress:address];
	self.rebases[[NSNumber numberWithLong:address]]=rebase;
}

-(void)stepMarkUUID
{
	struct uuid_command* command=(struct uuid_command*)[self.header commandWithType:LC_UUID];
	
	NSUUID* oldUUID=[NSUUID.alloc initWithUUIDBytes:command->uuid].autorelease;
	
	memcpy(command->uuid,"Amy",4);
	
	NSUUID* newUUID=[NSUUID.alloc initWithUUIDBytes:command->uuid].autorelease;
	
	trace(@"updated uuid to %@ (old %@) for visibility in logs",newUUID.UUIDString,oldUUID.UUIDString);
}

-(void)stepSyncHeader
{
	// TODO: ensure we don't overrun TEXT
	
	trace(@"syncing modified header (%lx bytes)",self.header.data.length);
	
	memcpy(self.data.mutableBytes,self.header.data.mutableBytes,self.header.data.length);
}

@end