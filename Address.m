@implementation Address

+(instancetype)rebaseWithAddress:(long)address
{
	Address* result=Address.alloc.init.autorelease;
	result.type=ADDRESS_REBASE;
	result.address=address;
	return result;
}

+(instancetype)bindWithAddress:(long)address ordinal:(int)ordinal name:(NSString*)name addend:(int)addend
{
	Address* result=Address.alloc.init.autorelease;
	result.type=ADDRESS_BIND;
	result.address=address;
	result.dylibOrdinal=ordinal;
	result.name=name;
	result.addend=addend;
	return result;
}

+(instancetype)exportWithAddress:(long)address name:(NSString*)name
{
	Address* result=Address.alloc.init.autorelease;
	result.type=ADDRESS_EXPORT;
	result.address=address;
	result.name=name;
	return result;
}

+(instancetype)reexportWithName:(NSString*)name importName:(NSString*)importName importOrdinal:(int)ordinal
{
	Address* result=Address.alloc.init.autorelease;
	result.type=ADDRESS_REEXPORT;
	result.name=name;
	result.importName=importName;
	result.dylibOrdinal=ordinal;
	return result;
}

-(BOOL)isRebase
{
	return self.type==ADDRESS_REBASE;
}

-(BOOL)isBind
{
	return self.type==ADDRESS_BIND;
}

-(BOOL)isExport
{
	return self.type==ADDRESS_EXPORT;
}

-(BOOL)isReexport
{
	return self.type==ADDRESS_REEXPORT;
}

@end