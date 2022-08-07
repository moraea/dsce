@implementation Rebase

+(instancetype)rebaseWithAddress:(long)address
{
	Rebase* result=Rebase.alloc.init.autorelease;
	result.address=address;
	return result;
}

@end