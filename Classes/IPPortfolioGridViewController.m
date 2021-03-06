//
//  IPPortfolioGridViewController.m
//  ipad-portfolio
//
//  Created by Brian Dewey on 4/23/11.
//  Copyright 2011 Brian Dewey. 
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <QuartzCore/QuartzCore.h>
#import "UIImage+Border.h"
#import "UIImage+Resize.h"
#import "IPPortfolio.h"
#import "IPPortfolioGridViewController.h"
#import "IPSetGridViewController.h"
#import "BDGridCell.h"
#import "IPPasteboardObject.h"
#import "BDImagePickerController.h"
#import "IPAlert.h"
#import "NSString+TestHelper.h"
#import "IPUserDefaults.h"
#import "BDCustomAlert.h"
#import "IPPhotoOptimizationManager.h"
#import "IPPhoto.h"

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//  This is a BDGridCell subclass that visualizes an IPSet.
//

@interface IPSetCell : BDGridCell {

}

//
//  This is the set associated with this cell.
//

@property (nonatomic, retain) IPSet *currentSet;

@end

@implementation IPSetCell

@synthesize currentSet = currentSet_;

////////////////////////////////////////////////////////////////////////////////
//
//  Dealloc. Note we set |currentSet| to nil, to both release it and remove the
//  observers.
//

- (void)dealloc {

  self.currentSet = nil;
  [super dealloc];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Gets the composite image for the set -- a stack of the first five images of
//  the set.
//

- (UIImage *)compositeImage {
  
  //
  //  Bail out if there's nothing to composite.
  //
  
  if ([self.currentSet countOfPages] == 0) {
    
    return [UIImage imageNamed:@"Portfolio-72.png"];
  }
  
  UIView *compositeView = [[[UIView alloc] initWithFrame:self.bounds] autorelease];
  
  //
  //  Build a thumbnail from 5 images.
  //
  
  for (int i = 0; i < 5; i++) {
    
    if (i >= [self.currentSet countOfPages]) {
      break;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    IPPage *page = [self.currentSet objectInPagesAtIndex:i];
    IPPhoto *photo = [page objectInPhotosAtIndex:0];
    UIImage *bordered = [photo.thumbnail imageWithBorderWidth:1.0 andColor:[[UIColor lightGrayColor] CGColor]];
    UIImageView *photoView = [[[UIImageView alloc] initWithImage:bordered] autorelease];
    CGAffineTransform transform = CGAffineTransformMakeRotation(i * 0.15);
    CGRect postTransformViewSize = CGRectApplyAffineTransform(photoView.frame, transform);
    CGFloat heightScale = compositeView.bounds.size.height / postTransformViewSize.size.height;
    CGFloat widthScale  = compositeView.bounds.size.width  / postTransformViewSize.size.width;
    CGFloat finalScale = MIN(heightScale, widthScale);
    transform = CGAffineTransformScale(transform, finalScale, finalScale);
    photoView.center = compositeView.center;
    photoView.transform = transform;
    photoView.contentMode = UIViewContentModeScaleAspectFit;
    [compositeView addSubview:photoView];
    [compositeView sendSubviewToBack:photoView];
    [pool drain];
  }
  
  UIGraphicsBeginImageContextWithOptions(compositeView.frame.size, NO, 0);
  [compositeView.layer renderInContext:UIGraphicsGetCurrentContext()];
  UIImage *compositeImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();

  return compositeImage;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Does the compositing on a background thread, then calls a completion
//  routine with the composite image on the main thread.
//

- (void)compositeAsyncWithCompletion:(void(^)(UIImage *compositeImage))completion {
  
  completion = [completion copy];
  dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_async(defaultQueue, ^(void) {
    UIImage *composite = [[self compositeImage] retain];
    dispatch_async(dispatch_get_main_queue(), ^(void) {
      completion(composite);
      [completion release];
      [composite release];
    });
  });
}

////////////////////////////////////////////////////////////////////////////////
//
//  Updates the thumbnail for this cell.
//

- (void)updateThumbnail {
  
  [self compositeAsyncWithCompletion:^(UIImage *compositeImage) {
    
    self.image = compositeImage;
//    self.alpha = 0.0;
//    self.image = compositeImage;
//    [UIView animateWithDuration:kIPAnimationViewAppearFast animations:^(void) {
//      self.alpha = 1.0;
//    }];
  }];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Update the caption/image for the cell. Watch for changes to the set
//  thumbnail image.
//

- (void)setCurrentSet:(IPSet *)currentSet {

  [self.currentSet removeObserver:self forKeyPath:kIPSetTitle];
  [self.currentSet removeObserver:self forKeyPath:kIPSetThumbnailFilename];
  
  [currentSet_ autorelease];
  currentSet_ = [currentSet retain];
  
  if (self.currentSet != nil) {
    
    //
    //  Note that in |dealloc|, we set |currentSet| to nil. We therefore
    //  shouldn't do any of this extra work in the nil case, as |self| is
    //  about to go away. |updateThumbnail| is especially dangerous as it
    //  queues up work on another thread, and |self| will no longer be valid.
    //
    
    [self updateThumbnail];
    
    self.caption = self.currentSet.title;
    [self.currentSet addObserver:self forKeyPath:kIPSetTitle options:0 context:NULL];
    [self.currentSet addObserver:self forKeyPath:kIPSetThumbnailFilename options:0 context:NULL];
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  Watch for significant changes to the underlying set.
//

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  
  [self updateThumbnail];
  self.caption = self.currentSet.title;
}

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@interface IPPortfolioGridViewController() 

- (void)setTitleToPortfolioTitle;
- (void)pushControllerForSet:(IPSet *)set;

@end

@implementation IPPortfolioGridViewController

@synthesize gridView = gridView_;

////////////////////////////////////////////////////////////////////////////////
//
//  Designatied initializer.
//

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {

  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {

  }
  return self;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Deallocator.
//

- (void)dealloc {

  //
  //  This will both remove observers and release the portfolio.
  //
  
  self.portfolio = nil;
  [gridView_ release];
  [super dealloc];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Free memory.
//

- (void)didReceiveMemoryWarning {

  // Releases the view if it doesn't have a superview.
  [super didReceiveMemoryWarning];
}

#pragma mark - View lifecycle

////////////////////////////////////////////////////////////////////////////////
//
//  Do post-view-loading initialization.
//

- (void)viewDidLoad {

  [super viewDidLoad];

  self.gridView.dataSource = self;
  self.gridView.gridViewDelegate = self;
  if (self.portfolio.fontColor != nil) {

    self.gridView.fontColor = self.portfolio.fontColor;
  }
  self.gridView.font = self.portfolio.textFont;
  [self setTitleToPortfolioTitle];
  self.navigationController.navigationBar.translucent = YES;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Clean up when the view is unloaded. Release any retained subviews.
//

- (void)viewDidUnload {

  [super viewDidUnload];
  
  self.gridView = nil;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Always do a fade-in transition, to help from popping in from the stack.
//

- (void)viewDidAppear:(BOOL)animated {
  
  [super viewDidAppear:animated];
  self.gridView.topContentPadding = self.navigationController.navigationBar.frame.size.height;
  self.gridView.alpha = 0;
  [UIView animateWithDuration:0.2 animations:^(void) {
    self.gridView.alpha = 1;
  }];
  
  //
  //  See if we should ask the user to rate the application.
  //
  
  NSDate *lastTimeAsked = [self.userDefaults lastTimeAskedToRate];
  if ([lastTimeAsked timeIntervalSince1970] < 10) {
    
    lastTimeAsked = [NSDate date];
    self.userDefaults.lastTimeAskedToRate = lastTimeAsked;
  }
  NSTimeInterval timeSinceLastAsk = [[NSDate date] timeIntervalSinceDate:lastTimeAsked];
  if (([self.userDefaults lastRatedVersion] < kAppRatingVersion) &&
      (timeSinceLastAsk >= kMinIntervalBetweenAsks) &&
      (self.userDefaults.numberOfTimesAskedToRate < kMaxAsksPerVersion)) {
    
    //
    //  The user should have a chance to rate the app.
    //
    
    self.userDefaults.lastTimeAskedToRate = [NSDate date];
    self.userDefaults.numberOfTimesAskedToRate += 1;
    
    [BDCustomAlert showWithTitle:@"Rate Pholio" 
                         message:@"5 star ratings help fund updates. Rate now?" 
                     cancelTitle:@"Maybe later" 
                     cancelBlock:nil 
                      otherTitle:@"Rate now" 
                      otherBlock:^(void) {
                        
                        self.userDefaults.lastRatedVersion = kAppRatingVersion;
                        self.userDefaults.numberOfTimesAskedToRate = 0;
                        NSURL *url = [NSURL URLWithString:APP_URL];
                        [[UIApplication sharedApplication] openURL:url];
                      }
     ];
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  We support all interface orientations.
//

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {

  return YES;
}

#pragma mark -
#pragma mark Properties

////////////////////////////////////////////////////////////////////////////////
//
//  Sets the view title to the portfolio title.
//

- (void)setTitleToPortfolioTitle {
  
  if ((self.portfolio.title != nil) && ![@"" isEqualToString:self.portfolio.title]) {
    self.titleTextField.text = self.portfolio.title;
  } else {
    self.titleTextField.text = kProductName;
  }
  _GTMDevLog(@"%s -- titleTextField is %@", 
             __PRETTY_FUNCTION__,
             self.titleTextField.text);
}

////////////////////////////////////////////////////////////////////////////////
//
//  Sets the portfolio -- refresh the grid.
//

- (void)setPortfolio:(IPPortfolio *)portfolio {
  
  //
  //  Stop looking for changes to the background image.
  //
  
  [self.portfolio removeObserver:self 
                      forKeyPath:kIPPortfolioBackgroundImageName];
  [self.portfolio removeObserver:self forKeyPath:kIPPortfolioFontColor];
  [super setPortfolio:portfolio];
  
  [self setTitleToPortfolioTitle];
  if (self.portfolio.fontColor != nil) {

    self.gridView.fontColor = self.portfolio.fontColor;
  }
  self.gridView.font = self.portfolio.textFont;
  self.titleTextField.font = self.portfolio.titleFont;
  if (self.portfolio.navigationColor != nil) {
    
    self.navigationController.navigationBar.tintColor = self.portfolio.navigationColor;
    self.navigationController.navigationBar.translucent = YES;
  }

  _GTMDevLog(@"%s -- looking at a portfolio with %d set(s)",
             __PRETTY_FUNCTION__,
             [self.portfolio countOfSets]);
  _GTMDevLog(@"%s -- portfolio background image is %@",
             __PRETTY_FUNCTION__,
             self.portfolio.backgroundImageName);
  [self setBackgroundImageName:self.portfolio.backgroundImageName];
  
  //
  //  Look for further changes to the background image.
  //
  
  [self.portfolio addObserver:self 
                   forKeyPath:kIPPortfolioBackgroundImageName 
                      options:0 
                      context:NULL];
  [self.portfolio addObserver:self 
                   forKeyPath:kIPPortfolioFontColor 
                      options:0 
                      context:NULL];
  [self.gridView setNeedsLayout];
}

////////////////////////////////////////////////////////////////////////////////
//
//  When the background image changes, update our view.
//

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {

  [self setBackgroundImageName:self.portfolio.backgroundImageName];
  self.gridView.fontColor = self.portfolio.fontColor;
}

#pragma mark - Actions

////////////////////////////////////////////////////////////////////////////////
//
//  Look for found pictures, async.
//

- (void)lookForFoundPictures {
  
  _GTMDevLog(@"%s", __PRETTY_FUNCTION__);
  [self.portfolio lookForFoundPicturesAsyncWithCompletion:^(IPSet *foundSet) {
    
    _GTMDevLog(@"%s -- in completion routine. foundSet = %@",
               __PRETTY_FUNCTION__,
               [foundSet description]);
    if (foundSet != nil) {
      
      NSUInteger insertionIndex = [self.portfolio countOfSets];
      __block NSUInteger currentIndex = 0;
      IPSet *optimizedSet = [[[IPSet alloc] init] autorelease];
      optimizedSet.title = foundSet.title;
      [self.portfolio insertObject:optimizedSet inSetsAtIndex:insertionIndex];
      IPSetCell *cell = (IPSetCell *)[self.gridView insertCellAtIndex:insertionIndex];

      for (IPPage *page in foundSet.pages) {
        
        [[IPPhotoOptimizationManager sharedManager] asyncOptimizePage:page withCompletion:^(void) {
          
          [optimizedSet insertObject:page inPagesAtIndex:currentIndex];
          [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
          [cell updateThumbnail];
          currentIndex++;
        }];
      }
    }
  }];
}

#pragma mark - IPSettingsControllerDelegate

////////////////////////////////////////////////////////////////////////////////
//
//  Set the text color.
//

- (void)ipSettingsSetGridTextColor:(UIColor *)gridTextColor {
  
  [super ipSettingsSetGridTextColor:gridTextColor];
  self.gridView.fontColor = self.portfolio.fontColor;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Set the text font.
//

- (void)ipSettingsDidSetTextFontFamily:(NSString *)fontFamily {
  
  [super ipSettingsDidSetTextFontFamily:fontFamily];
  self.gridView.font = self.portfolio.textFont;
}

#pragma mark -
#pragma mark BDGridViewDataSource

////////////////////////////////////////////////////////////////////////////////
//
//  Return the cell size.
//

- (CGSize)gridViewSizeOfCell:(BDGridView *)gridView {
  
  return CGSizeMake(kGridCellSize, kGridCellSize);
}

////////////////////////////////////////////////////////////////////////////////
//
//  Return the number of sets in the portfolio.
//

- (NSUInteger)gridViewCountOfCells:(BDGridView *)gridView {
  
  return [self.portfolio countOfSets];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Get a cell for a set in the portfolio.
//

- (BDGridCell *)gridView:(BDGridView *)gridView cellForIndex:(NSUInteger)index {
  
  CGSize defaultSize = [self gridViewSizeOfCell:gridView];
  CGRect frame = CGRectMake(0, 0, defaultSize.width, defaultSize.height);
  IPSetCell *cell = (IPSetCell *)[gridView dequeueCell];
  if (cell == nil) {
    
    cell = [[[IPSetCell alloc] initWithFrame:frame] autorelease];
    cell.contentInset = UIEdgeInsetsMake(10, 10, 10, 10);
  }
  
  cell.frame = frame;
  cell.currentSet = [self.portfolio objectInSetsAtIndex:index];
  
  return cell;
}

#pragma mark -
#pragma mark BDGridViewDelegate

////////////////////////////////////////////////////////////////////////////////
//
//  Helper routine to push the navigation controller for a specific set.
//

- (void)pushControllerForSet:(IPSet *)set {
  
  IPSetGridViewController *setController = [[[IPSetGridViewController alloc] initWithNibName:@"IPSetGridViewController" bundle:nil] autorelease];
  setController.backButtonText = self.titleTextField.text;
  setController.currentSet = set;
  [self.navigationController pushViewController:setController animated:NO];
}

////////////////////////////////////////////////////////////////////////////////
//
//  The user tapped a set. Navigate to it.
//

- (void)gridView:(BDGridView *)gridView didTapCell:(BDGridCell *)cell {
  
  NSUInteger index = cell.index;
  IPSet *nextSet = [self.portfolio objectInSetsAtIndex:index];
  [self pushControllerForSet:nextSet];
}

////////////////////////////////////////////////////////////////////////////////
//
//  The user wants to rearrange sets.
//

- (void)gridView:(BDGridView *)gridView didMoveItemFromIndex:(NSUInteger)initialIndex 
         toIndex:(NSUInteger)finalIndex {
  
  IPSet *set = [[[self.portfolio objectInSetsAtIndex:initialIndex] retain] autorelease];
  [self.portfolio removeObjectFromSetsAtIndex:initialIndex];
  [self.portfolio insertObject:set inSetsAtIndex:finalIndex];
  [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Helper. Asynchronously creates |IPPage| objects for each image in |images|.
//  For each page, calls back to |progress| on the main thread. At the end of
//  everything, calls back to |completion| on the main thread.
//

- (void)asyncLoadImages:(NSArray *)assets
           pageProgress:(void(^)(IPPage *nextPage, NSUInteger count))progress 
             completion:(void(^)())completion {
  
  progress = [progress copy];
  completion = [completion copy];
  
  dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_async(defaultQueue, ^(void) {
    
    NSConditionLock *workersDone = [[[NSConditionLock alloc] initWithCondition:[assets count]] autorelease];

    for (id<BDSelectableAsset> asset in assets) {
      
      [asset imageAsyncWithCompletion:^(NSString *filename, NSString *uti) {
        
        if (filename == nil) {
          
          //
          //  There was at least one case where we couldn't get an image.
          //
          
          [workersDone lock];
          [workersDone unlockWithCondition:[workersDone condition] - 1];
          return;
        }
        
        IPPhoto *photo = [[IPPhoto alloc] init];
        photo.filename = filename;
        photo.title = [asset title];
        
        [[IPPhotoOptimizationManager sharedManager] asyncOptimizePhoto:photo withCompletion:^(void) {

          IPPage *page = [IPPage pageWithPhoto:photo];
          [photo release];
          [workersDone lock];
          progress(page, [assets count] - [workersDone condition]);
          [workersDone unlockWithCondition:[workersDone condition] - 1];
        }];
      }];
    }
    
    [workersDone lockWhenCondition:0];
    dispatch_async(dispatch_get_main_queue(), ^(void) {
      
      completion();
      [progress release];
      [completion release];
    });
    [workersDone unlockWithCondition:0];
  });
}

////////////////////////////////////////////////////////////////////////////////
//
//  Add a new set.
//
//  I can't decide if this is beautiful, or an abomination of blocks.
//

- (void)gridView:(BDGridView *)gridView didInsertAtPoint:(NSUInteger)insertionPoint 
        fromRect:(CGRect)rect {
  
  self.popoverController = [BDImagePickerController presentPopoverFromRect:rect
                                                                    inView:gridView 
                                                               onSelection:
                            ^(NSArray *assets) {
                              
                              IPSet *set = [[[IPSet alloc] init] autorelease];
                              set.title = kNewGalleryName;
                              [self.portfolio insertObject:set inSetsAtIndex:insertionPoint];
                              IPSetCell *cell = (IPSetCell *)[gridView insertCellAtIndex:insertionPoint];
                              [self asyncLoadImages:assets pageProgress:^(IPPage *nextPage, NSUInteger count) {
                                
                                [set.pages addObject:nextPage];
                                [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
                                [cell updateThumbnail];
                              } completion:^ {
                               
                                [cell updateThumbnail];
                                [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
                              }];
                            }];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Insert photos into an existing set.
//

- (void)gridView:(BDGridView *)gridView didInsertIntoCell :(BDGridCell *)cell {
  
  IPSetCell *setCell = (IPSetCell *)cell;
  self.popoverController = [BDImagePickerController presentPopoverFromRect:cell.frame 
                                                                    inView:gridView 
                                                               onSelection:
                            ^(NSArray *assets) {
                              
                              [self asyncLoadImages:assets pageProgress:^(IPPage *nextPage, NSUInteger count) {
                                
                                [setCell.currentSet insertObject:nextPage inPagesAtIndex:[setCell.currentSet countOfPages]];
                                
                              } completion:^ {
                                
                                //
                                //  NOTHING
                                //
                                
                              }];
                            }];
}

////////////////////////////////////////////////////////////////////////////////
//
//  Copy a set.
//

- (void)gridView:(BDGridView *)gridView didCopy:(NSSet *)indexes {
  
  _GTMDevAssert([indexes count] == 1, @"Only know how to copy single sets");
  NSUInteger index = [[indexes anyObject] unsignedIntegerValue];
  IPPasteboardObject *pasteboardObject = [[[IPPasteboardObject alloc] init] autorelease];
  pasteboardObject.modelObject = [self.portfolio objectInSetsAtIndex:index];
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:pasteboardObject];
  if (data) {
    
    [[UIPasteboard generalPasteboard] setData:data forPasteboardType:kIPPasteboardObjectUTI];
    
  } else {
    
    [self.alertManager showErrorMessage:kErrorCopyFailed];
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  Cut a set.
//

- (void)gridView:(BDGridView *)gridView didCut:(NSSet *)indexes {
  
  _GTMDevAssert([indexes count] == 1, @"Only know how to cut single sets");
  NSUInteger index = [[indexes anyObject] unsignedIntegerValue];
  IPPasteboardObject *pasteboardObject = [[[IPPasteboardObject alloc] init] autorelease];
  IPSet *set = [self.portfolio objectInSetsAtIndex:index];
  pasteboardObject.modelObject = set;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:pasteboardObject];
  if (data) {
    
    [set deletePhotoFiles];
    [[UIPasteboard generalPasteboard] setData:data forPasteboardType:kIPPasteboardObjectUTI];
    [self.portfolio removeObjectFromSetsAtIndex:index];
    [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
    [gridView deleteCellAtIndex:index];
    
  } else {
    
    [self.alertManager showErrorMessage:kErrorCutFailed];
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  Can we paste?
//

- (BOOL)gridViewCanPaste:(BDGridView *)gridView {
  
  NSArray *types = [NSArray arrayWithObject:kIPPasteboardObjectUTI];
  return [[UIPasteboard generalPasteboard] containsPasteboardTypes:types] ||
    ([[UIPasteboard generalPasteboard] image] != nil);
}

////////////////////////////////////////////////////////////////////////////////
//
//  Helper routine for pasting: Returns a set object from the contents of the 
//  pasteboard.
//

- (IPSet *)setFromPasteboard {
  
  NSData *data = [[UIPasteboard generalPasteboard] dataForPasteboardType:kIPPasteboardObjectUTI];
  IPPasteboardObject *pasteboardObject = [NSKeyedUnarchiver unarchiveObjectWithData:data];
  IPSet *set = nil;
  if ([pasteboardObject.modelObject isKindOfClass:[IPSet class]]) {
    
    set = (IPSet *)pasteboardObject.modelObject;
    
  } else if ([pasteboardObject.modelObject isKindOfClass:[IPPage class]]) {
    
    IPPage *page = (IPPage *)pasteboardObject.modelObject;
    set = [IPSet setWithPages:page, nil];
    
  } else if ([[UIPasteboard generalPasteboard] image] != nil) {
    
    UIImage *image = [[UIPasteboard generalPasteboard] image];
    IPPage *page = [IPPage pageWithImage:image];
    set = [IPSet setWithPages:page, nil];
  }
  return set;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Do a paste.
//

- (void)gridView:(BDGridView *)gridView didPasteAtPoint:(NSUInteger)insertionPoint {
  
  IPSet *unoptimizedSet = [self setFromPasteboard];
  if (unoptimizedSet != nil) {

    IPSet *optimizedSet = [[[IPSet alloc] init] autorelease];
    optimizedSet.title = unoptimizedSet.title;
    
    //
    //  Put the empty, optimized set in the model & UI.
    //
    
    [self.portfolio insertObject:optimizedSet inSetsAtIndex:insertionPoint];
    [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
    [gridView insertCellAtIndex:insertionPoint];
    
    //
    //  Optimize each page from the unoptimized set and stick it in the
    //  optimized set.
    //
    
    __block NSUInteger currentSetIndex = 0;
    for (IPPage *page in unoptimizedSet.pages) {
      
      [[IPPhotoOptimizationManager sharedManager] asyncOptimizePage:page withCompletion:^(void) {
        
        [optimizedSet insertObject:page inPagesAtIndex:currentSetIndex];
        currentSetIndex++;
      }];
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  Do a paste into an existing cell.
//

- (void)gridView:(BDGridView *)gridView didPasteIntoCell:(BDGridCell *)cell {
  
  IPSet *set = [self setFromPasteboard];
  if (set != nil) {
    
    IPSetCell *setCell = (IPSetCell *)cell;
    IPSet *targetSet = setCell.currentSet;
    __block NSUInteger currentIndex = [targetSet countOfPages];
    
    for (IPPage *page in set.pages) {
      
      [[IPPhotoOptimizationManager sharedManager] asyncOptimizePage:page withCompletion:^(void) {
        
        [targetSet insertObject:page inPagesAtIndex:currentIndex];
        currentIndex++;
      }];
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
//
//  Delete.
//

- (void)gridView:(BDGridView *)gridView didDelete:(NSSet *)indexes {

  _GTMDevAssert([indexes count] == 1, @"Only know how to delete single portfolios");
  NSUInteger index = [[indexes anyObject] unsignedIntegerValue];
  IPSet *set = [self.portfolio objectInSetsAtIndex:index];
  CGRect frame = [self.gridView frameForCellAtIndex:index];
  
  NSString *alertText;
  if ([set.title length] > 0) {
    
    alertText = [NSString stringWithFormat:kConfirmDelete, set.title];
    
  } else {
    
    alertText = kConfirmDeleteSetNoTitle;
  }
  [self.alertManager confirmWithDescription:alertText
                                  andButtonTitle:kDeleteString
                                        fromRect:frame 
                                          inView:self.gridView 
                                   performAction:
   ^(void) {
     [set deletePhotoFiles];
     [self.portfolio removeObjectFromSetsAtIndex:index];
     [self.gridView deleteCellAtIndex:index];
     [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
  }];
}

#pragma mark - UITextFieldDelegate

////////////////////////////////////////////////////////////////////////////////
//
//  Save changes to the portfolio title.
//

- (void)textFieldDidEndEditing:(UITextField *)textField {
  
  self.portfolio.title = textField.text;
  [self.portfolio savePortfolioToPath:[IPPortfolio defaultPortfolioPath]];
}

@end
