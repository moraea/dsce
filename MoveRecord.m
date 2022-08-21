@implementation MoveRecord

+(instancetype)recordWithOldStart:(long)oldStart newStart:(long)newStart size:(long)size
{
	MoveRecord* record=MoveRecord.alloc.init.autorelease;
	record.oldStart=oldStart;
	record.oldEnd=oldStart+size;
	record.newStart=newStart;
	record.newEnd=newStart+size;
	return record;
}

-(BOOL)containsOld:(long)address
{
	return address>=self.oldStart&&address<self.oldEnd;
}

-(BOOL)containsNew:(long)address
{
	return address>=self.newStart&&address<self.newEnd;
}

-(long)convert:(long)address
{
	assert([self containsOld:address]);
	
	long result=address-self.oldStart+self.newStart;
	
	assert([self containsNew:result]);
	
	return result;
}

@end