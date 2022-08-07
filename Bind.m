@implementation Bind

+(instancetype)bindWithAddress:(long)address ordinal:(int)ordinal symbol:(NSString*)symbol
{
	Bind* result=Bind.alloc.init.autorelease;
	result.address=address;
	result.ordinal=ordinal;
	result.symbol=symbol;
	return result;
}

@end