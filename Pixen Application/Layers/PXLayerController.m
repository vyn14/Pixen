//
//  PXLayerController.m
//  Pixen
//

#import "PXLayerController.h"
#import "PXLayerDetailsView.h"
#import "PXCanvas.h"
#import "PXCanvas_Layers.h"
#import "PXCanvas_Modifying.h"
#import "PXLayer.h"
#import "PXNotifications.h"
#import "PXCanvasDocument.h"
#import "PXAnimationDocument.h"

@interface PXLayerController()
- (void)propagateSelectedLayer:(NSInteger)row;
@end

@implementation PXLayerController

- (id)init
{
	if(!(self = [super initWithNibName:@"PXLayerController" bundle:nil])) {
		return nil;
	}
	views = [[NSMutableArray alloc] init];
	return self;
}

-(id) initWithCanvas:(PXCanvas*) aCanvas
{
	if ( ! ( self = [self init] ) ) 
		return nil;	
	[self setCanvas:aCanvas];
	return self;
}

- (void)setCanvas:(PXCanvas *)aCanvas
{
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	
	[nc removeObserver:self];
	[aCanvas retain];
	[canvas release];
	canvas = aCanvas;
	
	[nc addObserver:self
				 selector:@selector(reloadData:)
						 name:PXCanvasLayersChangedNotificationName 
					 object:canvas];
	
	[nc addObserver:self
				 selector:@selector(canvasLayerChanged:) 
						 name:PXCanvasLayerSelectionDidChangeName 
					 object:canvas];
	
	[self reloadData:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[layersView removeObserver:self forKeyPath:@"selectionIndexes"];
	[canvas release];
	[views release];
	[super dealloc];
}

- (void)awakeFromNib
{
	[layersView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	[layersView setDraggingSourceOperationMask:NSDragOperationNone forLocal:NO];
	[layersView setMinItemSize:NSMakeSize(200, 49)];
	[layersView setMaxItemSize:NSMakeSize(0, 49)];
	[layersView registerForDraggedTypes:[NSArray arrayWithObject:PXLayerRowPboardType]];
	[layersView addObserver:self 
							 forKeyPath:@"selectionIndexes" 
									options:NSKeyValueObservingOptionNew
									context:nil];
}

- (id)document
{
	return document;
}

- (void)setDocument:(id)doc
{
	document = doc;
}

- (void)canvasLayerChanged:(NSNotification *) notification
{
	[self selectRow:[[canvas layers] indexOfObject:[canvas activeLayer]]];
}

- (BOOL) isSubviewCollapsed {
	return [(NSSplitView *)[subview superview] isSubviewCollapsed:subview];
}

- (void)reloadData:(NSNotification *) aNotification
{
	NSInteger i, selectedRow;
	
	NSUInteger idx = [[layersView selectionIndexes] indexGreaterThanOrEqualToIndex:0];
	if (idx == NSNotFound || idx >= [[canvas layers] count])
	{
		selectedRow = 0; 
	}
	else
	{
		selectedRow = [self invertLayerIndex:idx];
	}
	
	for (i = 0; i < [[canvas layers] count]; i++)
	{
		PXLayer *layer = [[canvas layers] objectAtIndex:i];
		if([views count] > i)
		{
			[(PXLayerDetailsView *)[views objectAtIndex:i] setLayer: layer];
			[[views objectAtIndex:i] updatePreview:nil];
		}
		else
		{
			id newView = [[[PXLayerDetailsView alloc] initWithLayer:layer] autorelease];
			[newView setLayerController:self];
			[views addObject:newView];
			[newView updatePreview:nil];
		}
	}
	[views removeObjectsInRange:NSMakeRange([[canvas layers] count], [views count] - [[canvas layers] count])];
	[self selectRow:selectedRow];
	
	[layersView setContent:[[views reverseObjectEnumerator] allObjects]];
	id newLayer = [[aNotification userInfo] objectForKey:PXCanvasNewLayerKey];
	if(newLayer)
	{
		for (id current in views)
		{
			if([current layer] == newLayer)
			{
				[current focusOnName];
			}
		}
	}
	//else if ([[canvas layers] count] && [canvas activeLayer])
	//	[self canvasLayerChanged:nil];
}

- (IBAction)nextLayer:(id)sender
{
	[self selectRow:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]+1]];
	[self selectLayer:[[canvas layers] objectAtIndex:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]]]];
}

- (IBAction)previousLayer:(id)sender
{
	[self selectRow:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]-1]];
	[self selectLayer:[[canvas layers] objectAtIndex:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]]]];
}

- (void)selectRow:(NSUInteger)index
{
	if(index == NSNotFound || !canvas || [[canvas layers] count] == 0) { return; }
	[layersView setSelectionIndexes:[NSIndexSet indexSetWithIndex:[self invertLayerIndex:index]]];
	[self updateRemoveButtonStatus];
}

- (IBAction)displayHelp:sender
{
	[[NSHelpManager sharedHelpManager] openHelpAnchor:@"workingwithlayers" inBook:@"Pixen Help"];	
}

- (void)setSubview:(NSView *)sv;
{
	subview = sv;
	lastSubviewHeight = [subview frame].size.height;
	[[NSNotificationCenter defaultCenter] addObserver:self
																					 selector:@selector(splitViewWillResizeSubviews:)
																							 name:NSSplitViewWillResizeSubviewsNotification
																						 object:[subview superview]];
}


// this is the handler the above snippet refers to
- (void) splitViewWillResizeSubviews:(id)object
{
	lastSubviewHeight = [subview frame].size.height;
}

// wire this to the UI control you wish to use to toggle the
// expanded/collapsed state of splitViewSubViewLeft
- (void)expandSubview
{
	NSSplitView *splitView = (NSSplitView *)[subview superview];
	[splitView adjustSubviews];
	if ([splitView isSubviewCollapsed:subview])
		[splitView setPosition:lastSubviewHeight
					ofDividerAtIndex:0];
}

- (void)collapseSubview {
	NSSplitView *splitView = (NSSplitView *)[subview superview];
	[splitView adjustSubviews];
	if ([splitView isSubviewCollapsed:subview])
		[splitView setPosition:[splitView minPossiblePositionOfDividerAtIndex:0]
					ofDividerAtIndex:0];
}

- (IBAction)addLayer:(id)sender
{
	layersCreated++;
	PXLayer *layer =[[PXLayer alloc] initWithName:[NSString stringWithFormat:NSLocalizedString(@"New Layer %d", @"New Layer %d"), layersCreated]
											 size:[canvas size]
									fillWithColor:[[NSColor clearColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
	
	//[[[self document] undoManager] beginUndoGrouping];
	[canvas addLayer:layer];
	[layer release];
	
	//[[[self document] undoManager] endUndoGrouping];
	[self selectRow:[self invertLayerIndex:0]];
	[self selectLayer:nil];
}

- (PXCanvas *)canvas
{
	return canvas;
}

- (IBAction)duplicateLayer:(id)sender
{
	NSInteger index = [self invertLayerIndex:[[layersView selectionIndexes] firstIndex]];
	[canvas duplicateLayerAtIndex:index];
	
	[self selectRow:index+1];
	[self selectLayer:nil];
}

- (void)duplicateLayerObject:(PXLayer *)layer
{
	NSInteger index = [[canvas layers] indexOfObject:layer];
	[canvas duplicateLayerAtIndex:index];
	
	[self selectRow:index+1];
	[self selectLayer:nil];
}

- (void)removeLayerAtCanvasLayersIndex:(NSUInteger)index
{
	if([[canvas layers] count] <= 1) { return; }
	[canvas removeLayerAtIndex:index];
	NSUInteger newIndex = MAX(index - 1, 0);
	[self selectRow:newIndex];
	[self selectLayer:nil];
}

- (void)removeLayerObject:(PXLayer *)layer
{
	[self removeLayerAtCanvasLayersIndex:[[canvas layers] indexOfObject:layer]];
}

- (IBAction)removeLayer:(id) sender
{
	NSUInteger idx = [[layersView selectionIndexes] indexGreaterThanOrEqualToIndex:0];
	if (idx == NSNotFound || idx >= [[canvas layers] count]) 
		return; 
	
	[self removeLayerAtCanvasLayersIndex:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
	if(!canvas) { return; }
	NSIndexSet *newSel = [change objectForKey:NSKeyValueChangeNewKey];
	NSUInteger idx = [newSel indexGreaterThanOrEqualToIndex:0];
	if (idx == NSNotFound || idx >= [[canvas layers] count]) {
		[self selectRow:0];
	} else {
		NSUInteger row = [self invertLayerIndex:idx];
		[self propagateSelectedLayer:row];
	}
}

- (void)propagateSelectedLayer:(NSInteger)row {
	if(!canvas || row < 0) { return; }
	PXLayer *layer = [[canvas layers] objectAtIndex:row];
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc postNotificationName:PXLayerSelectionDidChangeName
										object:self
									userInfo:[NSDictionary dictionaryWithObject:layer
																											 forKey:PXLayerKey]];
}

- (IBAction)selectLayer:(id)sender
{
	NSUInteger idx = [[layersView selectionIndexes] indexGreaterThanOrEqualToIndex:0];
	if (idx == NSNotFound || idx >= [[canvas layers] count]) {
		[self selectRow:[[canvas layers] indexOfObject:[canvas activeLayer]]]; 
		return;
	}
	NSUInteger row = [self invertLayerIndex:[[layersView selectionIndexes] firstIndex]];
	[self selectRow:row];	
	[self propagateSelectedLayer:row];
}

- (void)updateRemoveButtonStatus
{
	if ([[canvas layers] count] == 1)
		[removeButton setEnabled:NO];
	else 
		[removeButton setEnabled:YES];
}

- (NSUInteger)invertLayerIndex:(NSUInteger)anIndex
{
	NSInteger idx = [[canvas layers] count] - anIndex - 1;
	
	if (idx == -1)
		return NSNotFound;
	
	return idx;
}

- (void)mergeDownLayerAtCanvasLayersIndex:(NSUInteger)ind
{
	NSUInteger index = ind;
	if (index >= [[canvas layers] count]) {
		index = 0;
	}
	if (index == 0) 
		return;
	BOOL wasActive = [[canvas layers] objectAtIndex:index] == [canvas activeLayer];
	[canvas mergeDownLayer:[[canvas layers] objectAtIndex:index]];
	if(wasActive)
	{
		[self selectRow:index-1];
		[self selectLayer:[[canvas layers] objectAtIndex:index-1]];
	}
	else
	{
		[self selectRow:[canvas indexOfLayer:[canvas activeLayer]]];
		[self selectLayer:[canvas activeLayer]];
	}
}

- (void)mergeDownLayerObject:(PXLayer *) layer
{
	[self mergeDownLayerAtCanvasLayersIndex:[[canvas layers] indexOfObject:layer]];
}

- (void)mergeDown
{
	[self mergeDownLayerAtCanvasLayersIndex:[self invertLayerIndex:[[layersView selectionIndexes] firstIndex]]];
}

- (BOOL)collectionView:(NSCollectionView *)cv 
	 writeItemsAtIndexes:(NSIndexSet *)rows 
					toPasteboard:(NSPasteboard *)pboard
{
	[pboard declareTypes:[NSArray arrayWithObject:PXLayerRowPboardType] owner:self];
	
	[pboard setString:[NSString stringWithFormat:@"%d", [self invertLayerIndex:[rows firstIndex]]] forType:PXLayerRowPboardType];
	return YES;
}

- (NSDragOperation)collectionView:(NSCollectionView *)collectionView 
                     validateDrop:(id < NSDraggingInfo >)info 
                    proposedIndex:(NSInteger *)idxP 
                    dropOperation:(NSCollectionViewDropOperation *)operationP {
	if (![[[info draggingPasteboard] types] containsObject:PXLayerRowPboardType])
	{
		return NSDragOperationNone; 
	}
  
  NSInteger idx = *idxP;
  NSCollectionViewDropOperation operation = *operationP;
  
	
	NSUInteger sourceIdx = [self invertLayerIndex:[[[info draggingPasteboard] stringForType:PXLayerRowPboardType] intValue]];
	if ( idx == sourceIdx + 1 || idx == sourceIdx)
	{
		return NSDragOperationNone;
	}
	
	if (operation == NSCollectionViewDropOn) 
	{ 
		if (idx == sourceIdx - 1)
			return NSDragOperationNone;
    *operationP = NSCollectionViewDropBefore;
	}
	
	return NSDragOperationMove;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView 
            acceptDrop:(id < NSDraggingInfo >)info 
                 index:(NSInteger)idx 
         dropOperation:(NSCollectionViewDropOperation)dropOperation {
	id layer = [[canvas layers] objectAtIndex:[[[info draggingPasteboard] stringForType:PXLayerRowPboardType] intValue]];
	[canvas moveLayer:layer toIndex:[self invertLayerIndex:idx]];
	[self selectRow:[[canvas layers] indexOfObject:layer]];
	return YES;
}

- (NSImage *)collectionView:(NSCollectionView *)collectionView 
draggingImageForItemsAtIndexes:(NSIndexSet *)dragIndexes 
                  withEvent:(NSEvent *)dragEvent 
                     offset:(NSPointPointer)dragImageOffset {
	PXLayerDetailsView *v = (PXLayerDetailsView *)[[collectionView itemAtIndex:[dragIndexes firstIndex]] view];
	
	NSData *viewData = [v dataWithPDFInsideRect:[v bounds]];
	NSImage *viewImage = [[[NSImage alloc] initWithData:viewData] autorelease];
	NSImage *bgImage = [[[NSImage alloc] initWithSize:[v bounds].size] autorelease];
	[bgImage lockFocus];
	[[[NSColor whiteColor] colorWithAlphaComponent:0.66] set];
	NSRectFill([v bounds]);
	[[[NSColor lightGrayColor] colorWithAlphaComponent:0.66] set];
	[[NSBezierPath bezierPathWithRect:[v bounds]] stroke];
	[viewImage compositeToPoint:NSZeroPoint fromRect:[v bounds] operation:NSCompositeSourceOver fraction:0.66];
	[bgImage unlockFocus];
	
	NSPoint locationInView = [v convertPoint:[dragEvent locationInWindow] fromView:nil];
	locationInView.x -= NSWidth([v frame]) / 2;
	locationInView.x *= -1;
	locationInView.y -= NSHeight([v frame]) / 2;
	locationInView.y *= -1;
	*dragImageOffset = locationInView;
	return bgImage;
}

- (void)deleteKeyPressedInCollectionView:(NSCollectionView *)cv
{
	[self removeLayer:self];
}

@end
