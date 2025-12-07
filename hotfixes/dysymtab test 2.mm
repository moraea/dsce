#import "Extern.h"

int main(int argc,char** argv)
{
	NSString* input=[NSString stringWithUTF8String:argv[1]];
	NSString* output=[NSString stringWithUTF8String:argv[2]];
	NSMutableData* data=[NSMutableData dataWithContentsOfFile:input];
	assert(data);
	
	NSData* oldData=data.copy;
	struct mach_header_64* oldHeader=(struct mach_header_64*)oldData.bytes;
	
	struct nlist_64* newSymbolPointer=NULL;
	struct symtab_command* symtab=NULL;
	struct dyld_info_command* info=NULL;
	struct segment_command_64* linkedit=NULL;
	
	struct mach_header_64* newHeader=(struct mach_header_64*)data.mutableBytes;
	int newCommandIndex=0;
	char* newCommandPointer=(char*)(newHeader+1);
	
	struct load_command* oldCommand=(struct load_command*)(oldHeader+1);
	for(int commandIndex=0;commandIndex<oldHeader->ncmds;commandIndex++)
	{
		BOOL skip=false;
		
		if(oldCommand->cmd==LC_DYSYMTAB)
		{
			struct dysymtab_command* dysymtab=(struct dysymtab_command*)oldCommand;
			newSymbolPointer=(struct nlist_64*)((char*)newHeader+dysymtab->indirectsymoff);
			skip=true;
		}
		
		if(oldCommand->cmd==LC_SYMTAB)
		{
			symtab=(struct symtab_command*)newCommandPointer;
		}
		
		if(oldCommand->cmd==LC_DYLD_INFO)
		{
			info=(struct dyld_info_command*)newCommandPointer;
		}
		
		if(oldCommand->cmd==LC_SEGMENT_64)
		{
			struct segment_command_64* segment=(struct segment_command_64*)oldCommand;
			if(!strcmp(segment->segname,SEG_LINKEDIT))
			{
				linkedit=(struct segment_command_64*)newCommandPointer;
			}
		}
		
		if(oldCommand->cmd==LC_CODE_SIGNATURE)
		{
			skip=true;
		}
		
		if(oldCommand->cmd==LC_UUID)
		{
			// t39 "rfr2.m" (MH_DYLIB_IN_CACHE hotfix) used d5cf0007
			// we'll use d5cf01xx here then; try to keep d5cf<hotfix number><original version> in future as well
			
			struct uuid_command* command=(struct uuid_command*)oldCommand;
			assert(command->uuid[0]==0xd5&&(command->uuid[1]==0xce||command->uuid[1]==0xcf));
			command->uuid[1]=0xcf;
			command->uuid[2]=0x01;
		}
		
		if(!skip)
		{
			memcpy(newCommandPointer,oldCommand,oldCommand->cmdsize);
			newCommandPointer+=oldCommand->cmdsize;
			newCommandIndex++;
		}
		
		oldCommand=(struct load_command*)(((char*)oldCommand)+oldCommand->cmdsize);
	}
	
	newHeader->ncmds=newCommandIndex;
	newHeader->sizeofcmds=newCommandPointer-(char*)(newHeader+1);
	
	assert(newSymbolPointer);
	assert(symtab);
	assert(info);
	assert(linkedit);
	
	symtab->nsyms=0;
	
	NSMutableData* strings=NSMutableData.alloc.init;
	[strings increaseLengthBy:1];
	
	std::vector<ExportInfoTrie::Entry> entries;
	assert(ExportInfoTrie::parseTrie((const unsigned char*)newHeader+info->export_off,(const unsigned char*)newHeader+info->export_off+info->export_size,entries));
	for(ExportInfoTrie::Entry entry:entries)
	{
		// TODO: dummy address and type; only nm uses these
		
		struct nlist_64 legacy={};
		legacy.n_un.n_strx=strings.length;
		legacy.n_value=1;
		legacy.n_type=N_EXT;
		newSymbolPointer[symtab->nsyms]=legacy;
		symtab->nsyms++;
		
		NSString* name=[NSString stringWithUTF8String:entry.name.c_str()];
		[strings appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
		[strings increaseLengthBy:1];
	}
	
	char* stringsStart=(char*)&newSymbolPointer[symtab->nsyms];
	memcpy(stringsStart,strings.bytes,strings.length);
	
	symtab->symoff=(char*)newSymbolPointer-(char*)newHeader;
	symtab->stroff=stringsStart-(char*)newHeader;
	symtab->strsize=strings.length;
	
	long oldLength=data.length;
	data.length=stringsStart-(char*)newHeader+strings.length;
	linkedit->filesize+=data.length-oldLength;
	linkedit->vmsize+=data.length-oldLength;
	
	assert([data writeToFile:output atomically:true]);
}
