@implementation CacheImage

-(instancetype)initWithCacheFile:(CacheFile*)file info:(struct dyld_cache_image_info*)info
{
	self=super.init;
	
	Location* headerLocation=wrapAddressUnsafe(file,info->address);
	if(!headerLocation)
	{
		return nil;
	}
	
	// TODO: make this fully conform to LocationBase...?
	
	self.baseAddress=headerLocation.address;
	
	self.header=[ImageHeader.alloc initWithPointer:headerLocation.pointer].autorelease;
	
	self.file=file;
	self.path=[NSString stringWithUTF8String:wrapOffset(file,info->pathFileOffset).pointer];
	
	self.loadSymbols;
	
	return self;
}

// TODO: bit weird to put this here, move to ImageHeader

-(void)forEachLegacySymbol:(void (^)(struct nlist_64*,char*))block
{
	struct symtab_command* symtab=(struct symtab_command*)[self.header commandWithType:LC_SYMTAB];
	assert(symtab);
	
	struct nlist_64* symbols=(struct nlist_64*)wrapOffset(self.file,symtab->symoff).pointer;
	char* strings=wrapOffset(self.file,symtab->stroff).pointer;
	
	for(int index=0;index<symtab->nsyms;index++)
	{
		block(&symbols[index],strings+symbols[index].n_un.n_strx);
	}
}

-(void)loadSymbols
{
	// now that i noticed dyld_info_command has exports in some images
	// scanning legacy symtab is never necessary 🤦🏻‍♀️
	
	NSMutableArray<Address*>* exports=NSMutableArray.alloc.init.autorelease;
	
	char* trieData=NULL;
	long trieSize;
	
	struct linkedit_data_command* trieCommand=(struct linkedit_data_command*)[self.header commandWithType:LC_DYLD_EXPORTS_TRIE];
	if(trieCommand&&trieCommand->datasize!=0)
	{
		trieData=wrapOffset(self.file,trieCommand->dataoff).pointer;
		trieSize=trieCommand->datasize;
	}
	
	struct dyld_info_command* infoCommand=(struct dyld_info_command*)[self.header commandWithType:LC_DYLD_INFO];
	struct dyld_info_command* infoCommandOnly=(struct dyld_info_command*)[self.header commandWithType:LC_DYLD_INFO_ONLY];
	if(infoCommandOnly)
	{
		assert(!infoCommand);
		infoCommand=infoCommandOnly;
	}
	
	if(infoCommand&&infoCommand->export_size!=0)
	{
		assert(!trieData);
		trieData=wrapOffset(self.file,infoCommand->export_off).pointer;
		trieSize=infoCommand->export_size;
	}
	
	if(trieData)
	{
		std::vector<ExportInfoTrie::Entry> entries;
		assert(ExportInfoTrie::parseTrie((const unsigned char*)trieData,(const unsigned char*)trieData+trieSize,entries));
		
		for(ExportInfoTrie::Entry entry:entries)
		{
			long address=0;
			if(entry.info.address)
			{
				address=self.baseAddress+entry.info.address;
			}
			
			Address* item;
			NSString* name=[NSString stringWithUTF8String:entry.name.c_str()];
			
			if(entry.info.flags&EXPORT_SYMBOL_FLAGS_REEXPORT)
			{
				assert(address==0);
				
				// blank if unchanged
				
				NSString* importName=[NSString stringWithUTF8String:entry.info.importName.c_str()];
				item=[Address reexportWithName:name importName:importName importOrdinal:entry.info.other];
			}
			else
			{
				// TODO: sufficient to bind against these, but can't extract images with them
				
				item=[Address exportWithAddress:address name:name];
			}
			
			[exports addObject:item];
		}
	}
	
	self.exports=exports;
}

// TODO: slow

-(Address*)exportWithAddress:(long)address
{
	for(Address* item in self.exports)
	{
		if(item.address==address)
		{
			return item;
		}
	}
	
	return nil;
}

-(Address*)reexportWithName:(NSString*)name
{
	for(Address* item in self.exports)
	{
		if(item.isReexport)
		{
			if([item.name isEqual:name]||[item.importName isEqual:name])
			{
				return item;
			}
		}
	}
	
	return nil;
}

@end