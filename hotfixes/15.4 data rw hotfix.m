/*

clang -fmodules '15.4 data rw hotfix.m' -o /tmp/hotfix

/tmp/hotfix /Users/amy/Desktop/NearFieldOld.dylib

*/

@import Foundation;
@import MachO;

int main(int argc,char** argv)
{
	assert(argc==2);
	NSString* path=[NSString stringWithUTF8String:argv[1]];
	
	NSLog(@"read %@",path);
	
	NSMutableData* data=[NSMutableData dataWithContentsOfFile:path];
	assert(data);
	
	BOOL updatedImpostor=false;
	BOOL updatedUuid=false;
	// BOOL updatedConst=false;
	BOOL updatedEpoch=false;
	
	struct mach_header_64* header=(struct mach_header_64*)data.mutableBytes;
	struct load_command* command=(struct load_command*)(header+1);
	for(int index=0;index<header->ncmds;index++)
	{
		if(command->cmd==LC_SEGMENT_64)
		{
			struct segment_command_64* segmentCommand=(struct segment_command_64*)command;
			
			if(!strcmp(segmentCommand->segname,SEG_DATA))
			{
				if(segmentCommand->nsects==1)
				{
					struct section_64* sections=(struct section_64*)(segmentCommand+1);
					if(!strncmp(sections[0].sectname,"__objc_imageinfo",16))
					{
						if(segmentCommand->maxprot==VM_PROT_READ&&segmentCommand->initprot==VM_PROT_READ)
						{
							// not strictly necessary with 13.0 SDK, but might as well
							
							NSLog(@"updating perms on likely impostor segment");
							
							segmentCommand->maxprot|=VM_PROT_WRITE;
							segmentCommand->initprot|=VM_PROT_WRITE;
							
							assert(!updatedImpostor);
							updatedImpostor=true;
						}
					}
				}
			}
			
			if(!strcmp(segmentCommand->segname,"__DATA_CONST"))
			{
				if(!(segmentCommand->flags&SG_READ_ONLY))
				{
					/*
					
					> Library not loaded: /System/Library/PrivateFrameworks/NearField.framework/Versions/A/NearFieldOld.dylib
					> Referenced from: <E934E23E-EDFF-38B8-A531-A71AE0309096> /System/Library/PrivateFrameworks/NearField.framework/Versions/A/NearField
					> Reason: tried: '/System/Library/PrivateFrameworks/NearField.framework/Versions/A/NearFieldOld.dylib' (__DATA_CONST segment missing SG_READ_ONLY flag), '/System/Volumes/Preboot/Cryptexes/OS/System/Library/PrivateFrameworks/NearField.framework/Versions/A/NearFieldOld.dylib' (no such file), '/System/Library/PrivateFrameworks/NearField.framework/Versions/A/NearFieldOld.dylib' (__DATA_CONST segment missing SG_READ_ONLY flag)
					
					adding SG_READ_ONLY (previous commit) works for some bins but the objc runtime wants to write selector pointers:
					
					> 0   libobjc.A.dylib               	    0x7ff813f1186f fixupMethodList(method_list_t*, bool, bool, bool, objc_selector***) + 563
					> 1   libobjc.A.dylib               	    0x7ff813f12eff fixupProtocolMethodList(protocol_t*, method_list_t*, bool, bool, bool, objc_selector***) + 102
					> 2   libobjc.A.dylib               	    0x7ff813f12cb6 fixupProtocol(protocol_t*, unsigned int, bool, void (unsigned int) block_pointer) + 536
					> 3   libobjc.A.dylib               	    0x7ff813efc761 protocol_copyMethodDescriptionList + 121
					> 4   nearfieldtest                 	       0x10b7e4f02 main + 130
					
					so __DATA_CONST must remain writable unless we want to move objc data to another segment, which sounds hard
					
					anyways, SG_READ_ONLY and RW- checks are actually conditional per Policy::enforceDataSegmentPermissions
					we can just pretend to be from a pre-fall-2023 SDK, see below
					
					*/
					
					/*unsigned int newFlags=segmentCommand->flags|SG_READ_ONLY;
					
					NSLog(@"updating __DATA_CONST flags 0x%x to 0x%x",segmentCommand->flags,newFlags);
					
					segmentCommand->flags=newFlags;
					
					updatedConst=true;*/
				}
			}
		}
		
		if(command->cmd==LC_BUILD_VERSION)
		{
			struct build_version_command* versionCommand=(struct build_version_command*)command;
			
			if(versionCommand->sdk>=0xe0000)
			{
				NSLog(@"updating sdk version 0x%x to 0xd0000",versionCommand->sdk);
				
				versionCommand->sdk=0xd0000;
				
				updatedEpoch=true;
			}
		}
		
		if(command->cmd==LC_UUID)
		{
			/*
			
			last hotfix was "dysymtab test 2.mm" with d5 cf 01 <version>
			bump again for epoch hack, bins with 02 have incorrect SG_READ_ONLY and should be updated again
			
			*/
			
			NSLog(@"marking uuid");
			
			struct uuid_command* uuidCommand=(struct uuid_command*)command;
			assert(uuidCommand->uuid[0]==0xd5&&(uuidCommand->uuid[1]==0xce||uuidCommand->uuid[1]==0xcf));
			uuidCommand->uuid[1]=0xcf;
			uuidCommand->uuid[2]=0x03;
			
			assert(!updatedUuid);
			updatedUuid=true;
		}
		
		command=(struct load_command*)(((char*)command)+command->cmdsize);
	}
	
	if(!updatedImpostor)
	{
		NSLog(@"didn't find impostor needing update");
	}
	
	/*if(!updatedConst)
	{
		NSLog(@"didn't find __DATA_CONST needing update");
	}*/
	
	if(!updatedEpoch)
	{
		NSLog(@"didn't find LC_BUILD_VERSION needing update");
	}
	
	if(!updatedUuid)
	{
		NSLog(@"didn't find uuid");
		return 1;
	}
	
	NSLog(@"write %@",path);
	
	assert([data writeToFile:path atomically:true]);
	
	NSLog(@"done");
	
	return 0;
}
