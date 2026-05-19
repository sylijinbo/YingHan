#import <Cocoa/Cocoa.h>

@class HorizontalCandidateWindowController;

@protocol HorizontalCandidateWindowControllerDelegate <NSObject>

- (void)horizontalCandidateWindow:(HorizontalCandidateWindowController *)window didSelectCandidateAtLine:(NSInteger)line;
- (void)horizontalCandidateWindow:(HorizontalCandidateWindowController *)window didRequestPageOffset:(NSInteger)offset;

@end

@interface HorizontalCandidateWindowController : NSWindowController

@property(nonatomic, weak) id<HorizontalCandidateWindowControllerDelegate> delegate;
@property(nonatomic, readonly) CGFloat candidateWindowWidth;
@property(nonatomic, readonly) CGFloat candidateWindowHeight;

+ (HorizontalCandidateWindowController *)sharedController;

- (void)showCandidates:(NSArray<NSString *> *)candidates
            pageStart:(NSInteger)pageStart
          selectedLine:(NSInteger)selectedLine
        hasPreviousPage:(BOOL)hasPreviousPage
            hasNextPage:(BOOL)hasNextPage
              topLeftAt:(NSPoint)topLeftPoint;
- (NSInteger)visibleCandidateCountForCandidates:(NSArray<NSString *> *)candidates pageStart:(NSInteger)pageStart;
- (void)hideWindow;
- (BOOL)isVisible;

@end
