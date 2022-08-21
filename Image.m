@implementation Image

-(instancetype)initWithCacheFile:(CacheFile*)file info:(struct dyld_cache_image_info*)info
{
	self=super.init;
	
	Location* headerLocation=wrapAddressUnsafe(file,info->address);
	if(!headerLocation)
	{
		return nil;
	}
	
	self.header=[ImageHeader.alloc initWithPointer:headerLocation.pointer].autorelease;
	
	self.file=file;
	self.path=[NSString stringWithUTF8String:wrapOffset(file,info->pathFileOffset).pointer];
	
	self.loadSymbols;
	
	return self;
}

// TODO: bit weird to put this here
// but in ImageHeader, it would need to be passed a LocationBase

-(void)forEachSymbol:(void (^)(struct nlist_64*,char*))block
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
	// store references in multiple maps for fast lookups, reduces extraction time by ~80%
	// note - by index/address are subsets
	
	NSMutableDictionary<NSString*,Symbol*>* symbols=NSMutableDictionary.alloc.init.autorelease;
	NSMutableDictionary<NSNumber*,Symbol*>* symbolsByIndex=NSMutableDictionary.alloc.init.autorelease;
	NSMutableDictionary<NSNumber*,Symbol*>* symbolsByAddress=NSMutableDictionary.alloc.init.autorelease;
	
	// LC_DYLD_EXPORTS_TRIE contains re-exports but isn't present in every image
	// and only contains exports (not even all of them?)
	// LC_SYMTAB lacks re-exports but is reliably present and contains imports
	// so, combine them
	
	struct linkedit_data_command* trieCommand=(struct linkedit_data_command*)[self.header commandWithType:LC_DYLD_EXPORTS_TRIE];
	if(trieCommand)
	{
		char* trieData=wrapOffset(self.file,trieCommand->dataoff).pointer;
		
		std::vector<ExportInfoTrie::Entry> entries;
		if(ExportInfoTrie::parseTrie((const unsigned char*)trieData,(const unsigned char*)trieData+trieCommand->datasize,entries))
		{
			for(ExportInfoTrie::Entry entry:entries)
			{
				Symbol* item;
				NSString* name=[NSString stringWithUTF8String:entry.name.c_str()];
				
				if(entry.info.flags==EXPORT_SYMBOL_FLAGS_REEXPORT)
				{
					item=[Symbol reexportWithAddress:entry.info.address name:name importName:[NSString stringWithUTF8String:entry.info.importName.c_str()] importOrdinal:entry.info.other];
				}
				else if(entry.info.flags==EXPORT_SYMBOL_FLAGS_KIND_REGULAR)
				{
					item=[Symbol exportWithAddress:entry.info.address name:name];
				}
				else
				{
					// TODO: implement EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER, etc
					// only used in a couple dylibs
					
					continue;
				}
				
				symbols[name]=item;
				
				// re-exports are zero
				
				if(entry.info.address)
				{
					symbolsByAddress[[NSNumber numberWithLong:entry.info.address]]=item;
				}
			}
		}
		else
		{
			// TODO: when and why does this fail?
		}
	}
	
	// TODO: should probably put some asserts that duplicates between trie/symtab are the same
	
	__block long symbolIndex=0;
	
	[self forEachSymbol:^(struct nlist_64* entry,char* nameC)
	{
		NSString* name=[NSString stringWithUTF8String:nameC];
		Symbol* item=nil;
		
		if(entry->n_type==(N_EXT|N_SECT))
		{
			item=[Symbol exportWithAddress:entry->n_value name:name];
		}
		else if(entry->n_type==(N_EXT|N_UNDF))
		{
			int refType=entry->n_desc&REFERENCE_TYPE;
			if(refType==REFERENCE_FLAG_UNDEFINED_NON_LAZY||refType==REFERENCE_FLAG_UNDEFINED_LAZY)
			{
				int ordinal=GET_LIBRARY_ORDINAL(entry->n_desc);
				
				assert(!item);
				item=[Symbol importWithName:name ordinal:ordinal];
			}
		}
		
		if(item)
		{
			symbols[name]=item;
			
			if(entry->n_value)
			{
				symbolsByAddress[[NSNumber numberWithLong:entry->n_value]]=item;
			}
			
			symbolsByIndex[[NSNumber numberWithLong:symbolIndex]]=item;
		}
		
		symbolIndex++;
	}];
	
	self.symbols=symbols;
	self.symbolsByAddress=symbolsByAddress;
	self.symbolsByIndex=symbolsByIndex;
}

-(Symbol*)exportWithAddress:(long)address
{
	Symbol* item=self.symbolsByAddress[[NSNumber numberWithLong:address]];
	if(item&&item.isExport)
	{
		return item;
	}
	
	return nil;
}

-(Symbol*)importWithName:(NSString*)name
{
	Symbol* item=self.symbols[name];
	if(item&&!item.isExport)
	{
		return item;
	}
	
	return nil;
}

-(Symbol*)importWithIndex:(long)index
{
	Symbol* item=self.symbolsByIndex[[NSNumber numberWithLong:index]];
	if(item&&!item.isExport)
	{
		return item;
	}
	
	return nil;
}

@end