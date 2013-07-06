//
//  PcsxrMemCardManager.m
//  Pcsxr
//
//  Created by Charles Betts on 11/23/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PcsxrMemCardController.h"
#import "PcsxrMemoryObject.h"
#import "ConfigurationController.h"
#import "PcsxrMemCardHandler.h"
#include "sio.h"
#import "ARCBridge.h"

#define MAX_MEMCARD_BLOCKS 15

static inline void CopyMemcardData(char *from, char *to, int srci, int dsti, char *str)
{
		// header
		memcpy(to + (dsti + 1) * 128, from + (srci + 1) * 128, 128);
		SaveMcd(str, to, (dsti + 1) * 128, 128);
	
		// data
		memcpy(to + (dsti + 1) * 1024 * 8, from + (srci+1) * 1024 * 8, 1024 * 8);
		SaveMcd(str, to, (dsti + 1) * 1024 * 8, 1024 * 8);
	
		//printf("data = %s\n", from + (srci+1) * 128);
}

@implementation PcsxrMemCardController

//memCard1Array KVO functions

- (void)setupValues:(int)theCards
{
	NSParameterAssert(theCards < 4 && theCards > 0);
	if (theCards == 3) {
		LoadMcds(Config.Mcd1, Config.Mcd2);
	} else {
		LoadMcd(theCards, theCards == 1 ? Config.Mcd1 : Config.Mcd2);
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	NSString *fullPath = nil;
	NSString *fileName = nil;
	
	if (theCards & 1) {
		fullPath = [[def URLForKey:@"Mcd1"] path];
		fileName = [fm displayNameAtPath:fullPath];
		
		[memCard1Label setTitleWithMnemonic:fileName];
		
		[memCard1Label setToolTip:fullPath];
		
		[self loadMemoryCardInfoForCard:1];
	}
	
	if (theCards & 2) {
		fullPath = [[def URLForKey:@"Mcd2"] path];
		fileName = [fm displayNameAtPath:fullPath];
		
		[memCard2Label setTitleWithMnemonic:fileName];
		
		[memCard2Label setToolTip:fullPath];
		
		[self loadMemoryCardInfoForCard:2];
	}
}

-(void)insertObject:(PcsxrMemoryObject *)p inMemCard1ArrayAtIndex:(NSUInteger)index
{
    [memCard1Array insertObject:p atIndex:index];
}

-(void)removeObjectFromMemCard1ArrayAtIndex:(NSUInteger)index
{
    [memCard1Array removeObjectAtIndex:index];
}

- (void)setMemCard1Array:(NSMutableArray *)a
{
	if (memCard1Array != a) {
#if !__has_feature(objc_arc)
		[memCard1Array release];
#endif
		memCard1Array = [a mutableCopy];
	}
}

- (NSArray *)memCard1Array
{
	return [NSArray arrayWithArray:memCard1Array];
}

//memCard2Array KVO functions

-(void)insertObject:(PcsxrMemoryObject *)p inMemCard2ArrayAtIndex:(NSUInteger)index
{
    [memCard2Array insertObject:p atIndex:index];
}

-(void)removeObjectFromMemCard2ArrayAtIndex:(NSUInteger)index
{
    [memCard2Array removeObjectAtIndex:index];
}

- (void)setMemCard2Array:(NSMutableArray *)a
{
	if (memCard2Array != a) {
#if !__has_feature(objc_arc)
		[memCard2Array release];
#endif
		memCard2Array = [a mutableCopy];
	}
}

- (NSArray *)memCard2Array
{
	return [NSArray arrayWithArray:memCard2Array];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        //LoadMcds(Config.Mcd1, Config.Mcd2);
    }
    
    return self;
}

- (int)blockCount:(int)card fromIndex:(int)idx
{
	int i = 1;
	NSArray *memArray = nil;
	if (card == 1) {
		memArray = [self memCard1Array];
	} else {
		memArray = [self memCard2Array];
	}

	for (i = 1; i <= (MAX_MEMCARD_BLOCKS-idx); i++) {
		//Get the mem card +1 from the current card
		//And check its attributes
		PcsxrMemoryObject *obj = [memArray objectAtIndex:(i + idx)];
		
		//GetMcdBlockInfo(mcd, idx+i, &b);
		//printf("i=%i, mcd=%i, startblock=%i, diff=%i, flags=%x\n", i, mcd, startblock, (MAX_MEMCARD_BLOCKS-startblock), b.Flags);
		if ((obj.memFlags & 0x3) == 0x3) {
			return i+1;
		} else if ((obj.memFlags & 0x2) == 0x2) {
			//i++
		} else {
			return i;
		}
	}
	return i; // startblock was the last block so count = 1
}

- (void)loadMemoryCardInfoForCard:(int)theCard
{
	NSInteger i;
	McdBlock info;
	NSMutableArray *newArray = [[NSMutableArray alloc] initWithCapacity:MAX_MEMCARD_BLOCKS];
	
	for (i = 0; i < MAX_MEMCARD_BLOCKS; i++) {
		GetMcdBlockInfo(theCard, i + 1, &info);
		PcsxrMemoryObject *ob = [[PcsxrMemoryObject alloc] initWithMcdBlock:&info];

		[newArray insertObject:ob atIndex:i];
		RELEASEOBJ(ob);
	}
	if (theCard == 1) {
		[self setMemCard1Array:newArray];
	} else {
		[self setMemCard2Array:newArray];
	}
	RELEASEOBJ(newArray);
}

- (void)memoryCardDidChangeNotification:(NSNotification *)aNote
{
	NSDictionary *dict = [aNote userInfo];
	NSNumber *theNum = [dict objectForKey:memCardChangeNumberKey];
	[self setupValues: theNum ? [theNum intValue] : 3];
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setupValues:3];
    
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryCardDidChangeNotification:) name:memChangeNotifier object:nil];

	imageAnimateTimer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:3.0/10.0 target:self selector:@selector(animateMemCards:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:imageAnimateTimer forMode:NSRunLoopCommonModes];
}

- (void)animateMemCards:(NSTimer*)theTimer
{
	[[NSNotificationCenter defaultCenter] postNotificationName:memoryAnimateTimerKey object:self];
}

- (int)findFreeMemCardBlockInCard:(int)target_card length:(int)len
{
	int foundcount = 0, i = 0;
	
	NSArray *cardArray;
	if (target_card == 1) {
		cardArray = [self memCard1Array];
	}else {
		cardArray = [self memCard2Array];
	}
	
	// search for empty (formatted) blocks first
	while (i < MAX_MEMCARD_BLOCKS && foundcount < len) {
		PcsxrMemoryObject *obj = [cardArray objectAtIndex:i++]; //&Blocks[target_card][++i];
		if ((obj.memFlags & 0xFF) == 0xA0) { // if A0 but not A1
			foundcount++;
		} else if (foundcount >= 1) { // need to find n count consecutive blocks
			foundcount = 0;
		} else {
			//i++;
		}
		//printf("formatstatus=%x\n", Info->Flags);
 	}
	
	if (foundcount == len)
		return (i-foundcount);
	
	// no free formatted slots, try to find a deleted one
	foundcount = i = 0;
	while (i < MAX_MEMCARD_BLOCKS && foundcount < len) {
		PcsxrMemoryObject *obj = [cardArray objectAtIndex:i++];
		if ((obj.memFlags & 0xF0) == 0xA0) { // A2 or A6 f.e.
			foundcount++;
		} else if (foundcount >= 1) { // need to find n count consecutive blocks
			foundcount = 0;
		} else {
			//i++;
		}
		//printf("delstatus=%x\n", Info->Flags);
 	}
	
	if (foundcount == len)
		return (i-foundcount);
	
 	return -1;
}

- (int)findFreeMemCardBlockInCard:(int)target_card
{
	return [self findFreeMemCardBlockInCard:target_card length:1];
}

- (IBAction)moveBlock:(id)sender
{
	NSInteger memCardSelect = [sender tag];
	NSCollectionView *cardView;
	NSIndexSet *selection;
	int toCard, fromCard, freeSlot;
	int count;
	int j = 0;
	char *str, *source, *destination;
	if (memCardSelect == 1) {
		str = Config.Mcd1;
		source = Mcd2Data;
		destination = Mcd1Data;
		cardView = memCard2view;
		toCard = 1;
		fromCard = 2;
	} else {
		str = Config.Mcd2;
		source = Mcd1Data;
		destination = Mcd2Data;
		cardView = memCard1view;
		toCard = 2;
		fromCard = 1;
	}
	selection = [cardView selectionIndexes];
	if (!selection || [selection count] == 0) {
		NSBeep();
		return;
	}
	
	NSInteger selectedIndex = [selection firstIndex];
	
	count = [self blockCount:fromCard fromIndex:selectedIndex];
	
	freeSlot = [self findFreeMemCardBlockInCard:toCard length:count];
	if (freeSlot == -1) {
		NSRunCriticalAlertPanel(NSLocalizedString(@"No Free Space", nil), NSLocalizedString(@"Memory card %d doesn't have %d free consecutive blocks on it. Please remove some blocks on that card to continue", nil), nil, nil, nil, count, toCard);
		return;
	}
	
	for (j=0; j < count; j++) {
		CopyMemcardData(source, destination, (selectedIndex+j), (freeSlot+j), str);
		//printf("count = %i, firstfree=%i, i=%i\n", count, first_free_slot, j);
	}
	
	if (toCard == 1) {
		LoadMcd(1, Config.Mcd1);
	} else {
		LoadMcd(2, Config.Mcd2);
	}
	[self loadMemoryCardInfoForCard:toCard];
}

- (IBAction)formatCard:(id)sender
{
	NSInteger formatOkay = NSRunAlertPanel(NSLocalizedString(@"Format Card", nil), NSLocalizedString(@"Formatting a memory card will remove all data on it.\n\nThis cannot be undone.", nil), NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"Format", nil), nil);
	if (formatOkay == NSAlertAlternateReturn) {
		NSInteger memCardSelect = [sender tag];
		if (memCardSelect == 1) {
			CreateMcd(Config.Mcd1);
			LoadMcd(1, Config.Mcd1);
		} else {
			CreateMcd(Config.Mcd2);
			LoadMcd(2, Config.Mcd2);
		}
		[self loadMemoryCardInfoForCard:memCardSelect];
	}
}

- (void)deleteMemoryBlockAtSlot:(int)slotnum card:(int)cardNum
{
	int xor = 0, i, j;
	char *data, *ptr, *filename;
	NSArray *cardArray;
	PcsxrMemoryObject *memObject;
	if (cardNum == 1) {
		filename = Config.Mcd1;
		data = Mcd1Data;
		cardArray = [self memCard1Array];
	} else {
		filename = Config.Mcd2;
		data = Mcd2Data;
		cardArray = [self memCard2Array];
	}
	memObject = [cardArray objectAtIndex:slotnum];
	unsigned char flags = [memObject memFlags];
	i = slotnum;
	i++;
	ptr = data + i * 128;
	
	if ((flags & 0xF0) == 0xA0) {
		if ((flags & 0xF) >= 1 &&
			(flags & 0xF) <= 3) { // deleted
			*ptr = 0x50 | (flags & 0xF);
		} else return;
	} else if ((flags & 0xF0) == 0x50) { // used
		*ptr = 0xA0 | (flags & 0xF);
	} else { return; }
	
	for (j = 0; j < 127; j++) xor ^= *ptr++;
	*ptr = xor;
	
	SaveMcd(filename, data, i * 128, 128);
}

- (IBAction)deleteMemoryObject:(id)sender {
	NSInteger deleteOkay = NSRunAlertPanel(NSLocalizedString(@"Delete Block", nil), NSLocalizedString(@"Deleting a block will remove all saved data on that block.\n\nThis cannot be undone.", nil), NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"Delete", nil), nil);
	if (deleteOkay == NSAlertAlternateReturn) {
		NSInteger memCardSelect = [sender tag];
		NSIndexSet *selected;
		if (memCardSelect == 1) {
			selected = [memCard1view selectionIndexes];
		} else {
			selected = [memCard2view selectionIndexes];
		}
		
		if (!selected || [selected count] == 0) {
			NSBeep();
			return;
		}
		
		NSInteger selectedIndex = [selected firstIndex];
		[self deleteMemoryBlockAtSlot:selectedIndex card:memCardSelect];
		
		if (memCardSelect == 1) {
			LoadMcd(1, Config.Mcd1);
		} else {
			LoadMcd(2, Config.Mcd2);
		}
		[self loadMemoryCardInfoForCard:memCardSelect];
	}
}

- (IBAction)changeMemCard:(id)sender
{
	[ConfigurationController mcdChangeClicked:sender];
}

- (IBAction)newMemCard:(id)sender
{
	[ConfigurationController mcdNewClicked:sender];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[imageAnimateTimer invalidate];
	
	RELEASEOBJ(imageAnimateTimer);
	RELEASEOBJ(memCard1Array);
	RELEASEOBJ(memCard2Array);

	SUPERDEALLOC;
}

- (BOOL)isMemoryBlockEmptyOnCard:(int)aCard block:(int)aBlock
{
	NSArray *memArray;
	PcsxrMemoryObject *obj;
	if (aCard == 1) {
		memArray = [self memCard1Array];
	} else {
		memArray = [self memCard2Array];
	}
	obj = [memArray objectAtIndex:aBlock];
#if 0
	if (([obj memFlags] & 0xF0) != 0x50)
		return YES;
	
	//FIXME: Does this properly handle saves that span more than one block?
	if ([[obj englishName] isEqualToString:@""]) {
		return YES;
	}
#else
	if (![obj isNotDeleted]) {
		return YES;
	} 
#endif
	
	return NO;
}

- (int)countFreeBlocksOnCard:(int)aCard
{
	int i, count = 0;
	for (i = 0; i < MAX_MEMCARD_BLOCKS; i++) {
		if ([self isMemoryBlockEmptyOnCard:aCard block:i]) {
			count++;
		}
	}
	return count;
}

@end
