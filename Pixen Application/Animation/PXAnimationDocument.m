//
//  PXAnimationDocument.m
//  Pixen
//
//  Created by Joe Osborn on 2005.08.09.
//  Copyright 2005 Pixen. All rights reserved.
//

#import "PXAnimationDocument.h"
#import "PXAnimation.h"
#import "PXAnimationWindowController.h"
#import "PXCel.h"
#import "PXAnimatedGifExporter.h"
#import "PXCanvas_ImportingExporting.h"
#import "OSProgressPopup.h"
#import "PXCanvasWindowController_IBActions.h"

@implementation PXAnimationDocument

@synthesize animation;

- init
{
	self = [super init];
	animation = [[PXAnimation alloc] init];
	return self;
}

- (void)dealloc
{
	[ (PXAnimationWindowController *) self.windowController setAnimation:nil];
	[animation release];
	[super dealloc];
}

//FIXME: consider removing these three once coupling decreases

- (id)canvasController
{
	return [self.windowController canvasController];
}

- canvas
{
	return [[animation objectInCelsAtIndex:0] canvas];
}

- (NSArray *)canvases
{
  return [animation canvases];
}

- (void)delete:(id)sender
{
	[self.windowController delete:sender];
}

- (void)initWindowController
{
	self.windowController = [[[PXAnimationWindowController alloc] initWithWindowNibName:@"PXAnimationDocument"] autorelease];
}

- (void)setWindowControllerData
{
	[ (PXAnimationWindowController *) self.windowController setAnimation:animation];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)aType error:(NSError **)outError
{
	if ([aType isEqualToString:PixenAnimationFileType] ||
		[aType isEqualToString:PixenAnimationFileTypeOld])
	{
		NSMutableDictionary *files = [NSMutableDictionary dictionaryWithCapacity:[animation countOfCels]];
		NSMutableArray *celData = [NSMutableArray arrayWithCapacity:[animation countOfCels]];
		int i;
		for (i = 0; i < [animation countOfCels]; i++)
		{
			PXCel *current = [animation objectInCelsAtIndex:i];
			NSFileWrapper *file = [[[NSFileWrapper alloc] initRegularFileWithContents:[NSKeyedArchiver archivedDataWithRootObject:[current canvas]]] autorelease];
			[files setObject:file forKey:[NSString stringWithFormat:@"%d.%@", i, PXISuffix]];
			[celData addObject:[current info]];
		}
		NSString *error = nil;
		NSData *xmlData = [NSPropertyListSerialization dataFromPropertyList:celData format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
		if(!xmlData)
		{
			NSLog(@"%@", error);
			[error release];
			return nil;
		}
		[files setObject:[[[NSFileWrapper alloc] initRegularFileWithContents:xmlData] autorelease] forKey:@"CelData.plist"];
		return [[[NSFileWrapper alloc] initDirectoryWithFileWrappers:files] autorelease];
	}
	else if (UTTypeEqual(kUTTypeGIF, (__bridge CFStringRef)aType))
	{
		NSError *err = nil;
		NSData *data = [self dataOfType:(NSString *)kUTTypeGIF error:&err];
		if(err) 
		{
			[self presentError:err];
			return nil;
		}
		else
		{
			return [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
		}
	}
	return nil;
}

- (NSData *)dataOfType:(NSString *)aType error:(NSError **)err
{
	if (UTTypeEqual(kUTTypeGIF, (__bridge CFStringRef) aType))
	{
		OSProgressPopup *popup = [OSProgressPopup sharedProgressPopup];
		PXAnimatedGifExporter *exporter = [[[PXAnimatedGifExporter alloc] initWithSize:[animation size] iterations:1] autorelease];
		int i;
		NSUInteger numberOfCels = [animation countOfCels];
		[popup setMaxProgress:numberOfCels];
		
		[popup beginOperationWithStatusText:[NSString stringWithFormat:@"Exporting GIF... (1 of %d)", numberOfCels]
							   parentWindow:[self.windowController window]];
		
		[popup setProgress:0];
		id exportAnimation = [[animation copy] autorelease];
		[exportAnimation reduceColorsTo:256 withTransparency:YES matteColor:[NSColor whiteColor]];
		NSColor *transparentColor = nil;
		for (i = 0; i < numberOfCels; i++)
		{
			PXCanvas * celCanvas = [[exportAnimation objectInCelsAtIndex:i] canvas];
			transparentColor = [exporter writeCanvas:celCanvas withDuration:[[exportAnimation objectInCelsAtIndex:i] duration] transparentColor:transparentColor];
			[popup setStatusText:[NSString stringWithFormat:@"Exporting GIF... (%d of %d)", i + 1, numberOfCels]];
			[popup setProgress:i + 1];
		}
		
		[exporter finalizeExport];
		[popup endOperation];
		return [exporter data];
	}
	return nil;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)wrapper ofType:(NSString *)docType error:(NSError **)outError
{
	if ([docType isEqualToString:PixenAnimationFileType] ||
			[docType isEqualToString:PixenAnimationFileTypeOld])
	{
		[animation removeCel:[animation objectInCelsAtIndex:0]];
		NSDictionary *files = [wrapper fileWrappers];
		NSString *error = nil;
		NSData *plistData = [[files objectForKey:@"CelData.plist"] regularFileContents];
		NSArray *plist = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error];
		if(!plist)
		{
			NSLog(@"%@", error);
			[error release];
			return NO;
		}
		if([plist count] == 0) { return NO; }
		PXGrid *firstGrid = nil;
		
		int i;
		for (i = 0; i < [plist count]; i++)
		{
			NSFileWrapper *currentFile = [files objectForKey:[NSString stringWithFormat:@"%d.%@", i, PXISuffix]];
			
			PXCel *cel = [[PXCel alloc] init];
			[cel setCanvas:[NSKeyedUnarchiver unarchiveObjectWithData:[currentFile regularFileContents]]];
			[cel setInfo:[plist objectAtIndex:i]];
			
			if (firstGrid == nil) {
				firstGrid = [[cel canvas] grid];
			} else {
				[[cel canvas] setGrid:firstGrid];
			}
			
			[animation addCel:cel];
			[cel release];
		}
		
		[[self undoManager] removeAllActions];
		[self updateChangeCount:NSChangeCleared];
		
		return (animation != nil) && ([animation countOfCels] > 0);
	}
	else if (UTTypeEqual(kUTTypeGIF, (__bridge CFStringRef) docType))
	{
		return [self readFromData:[wrapper regularFileContents] ofType:docType error:outError];
	}
	else
	{
		return NO;
	}
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)docType error:(NSError **)err
{
	if (UTTypeEqual(kUTTypeGIF, (__bridge CFStringRef) docType))
	{
		[animation removeCel:[animation objectInCelsAtIndex:0]];
		NSImage *tempImage = [[[NSImage alloc] initWithData:data] autorelease];
		NSBitmapImageRep *bitmapRep = [[tempImage representations] objectAtIndex:0];
		int frameCount = [[bitmapRep valueForProperty:NSImageFrameCount] intValue];
		int i;
		for (i = 0; i < frameCount; i++)
		{
			[bitmapRep setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithInt:i]];
			PXCel *newCel = [[[PXCel alloc] initWithImage:[[tempImage copy] autorelease] animation:animation] autorelease];
			// PXCel is retained by the animation in the initializer used above
			// [newCel retain];
			[newCel setDuration:[[bitmapRep valueForProperty:NSImageCurrentFrameDuration] floatValue]];
		}
		[[self undoManager] removeAllActions];
		[self updateChangeCount:NSChangeCleared];
		return (animation != nil) && ([animation countOfCels] > 0);
	}
	[[self undoManager] removeAllActions];
	[self updateChangeCount:NSChangeCleared];
	return (animation != nil) && ([animation countOfCels] > 0);
}

+ (BOOL)isNativeType:(NSString *)type
{
	if (UTTypeEqual(kUTTypeGIF, (__bridge CFStringRef) type)) { return YES; }
	return [super isNativeType:type];
}

+ writableTypes
{
	return [[super writableTypes] arrayByAddingObject:(NSString *)kUTTypeGIF];
}

@end
