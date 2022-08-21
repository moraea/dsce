@implementation Symbol

+(instancetype)exportWithAddress:(long)address name:(NSString*)name
{
	Symbol* result=Symbol.alloc.init.autorelease;
	result.isExport=true;
	result.address=address;
	result.name=name;
	return result;
}

+(instancetype)reexportWithAddress:(long)address name:(NSString*)name importName:(NSString*)importName importOrdinal:(int)importOrdinal
{
	Symbol* result=Symbol.alloc.init.autorelease;
	result.isExport=true;
	result.address=address;
	result.name=name;
	result.importName=importName;
	result.importOrdinal=importOrdinal;
	return result;
}

+(instancetype)importWithName:(NSString*)name ordinal:(int)ordinal
{
	Symbol* result=Symbol.alloc.init.autorelease;
	result.importName=name;
	result.importOrdinal=ordinal;
	return result;
}

-(instancetype)copy
{
	Symbol* clone=Symbol.alloc.init;
	clone.isExport=self.isExport;
	clone.name=self.name;
	clone.address=self.address;
	clone.importName=self.importName;
	clone.importOrdinal=self.importOrdinal;
	return clone;
}

@end