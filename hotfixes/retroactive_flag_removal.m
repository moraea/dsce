@import Foundation;
@import MachO;
#define trace NSLog

int main(int argc,char** argv)
{
	NSMutableArray<NSString*>* paths=NSMutableArray.alloc.init;
	for(int i=1;i<argc;i++)
	{
		[paths addObject:[NSString stringWithUTF8String:argv[i]]];
	}
	
	assert(paths.count>0);
	
	for(NSString* path in paths)
	{
		NSMutableData* data=[NSMutableData dataWithContentsOfFile:path];
		assert(data);
		
		struct mach_header_64* header=data.mutableBytes;
		
		if(header->flags&MH_DYLIB_IN_CACHE)
		{
			unsigned int newFlags=header->flags&~MH_DYLIB_IN_CACHE;
			trace(@"fix %@: %x -> %x",path,header->flags,newFlags);
			header->flags=newFlags;
			
			struct load_command* command=(struct load_command *)(header+1);
			for(int i=0;i<header->ncmds;i++)
			{
				if(command->cmd==LC_UUID)
				{
					struct uuid_command* uuid=(struct uuid_command*)command;
					
					NSUUID* oldUUID=[NSUUID.alloc initWithUUIDBytes:uuid->uuid];
					
					uuid->uuid[0]=0xd5;
					uuid->uuid[1]=0xcf; // uhhh put F instead of E here so we know it's the hotfix script and not actual dsce v7
					uuid->uuid[2]=0;
					uuid->uuid[3]=7;
					
					NSUUID* newUUID=[NSUUID.alloc initWithUUIDBytes:uuid->uuid];
					trace(@"uuid %@ -> %@",oldUUID.UUIDString,newUUID.UUIDString);
				}
				
				command=(struct load_command *)((char*)command+command->cmdsize);
			}
			
			[data writeToFile:path atomically:false];
		}
	}
}