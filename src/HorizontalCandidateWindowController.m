#import "HorizontalCandidateWindowController.h"
#import "NSScreen+PointConversion.h"

static const CGFloat kCandidateWindowHeight = 32.0;
static const CGFloat kCandidateWindowMinWidth = 120.0;
static const CGFloat kCandidateWindowMaxWidth = 780.0;
static const CGFloat kCandidateWindowHorizontalPadding = 5.0;
static const CGFloat kCandidateWindowArrowWidth = 22.0;
static const CGFloat kSelectionKeyFontSize = 14.0;
static const CGFloat kCandidateFontSize = 18.0;
static const CGFloat kCandidatePreferredMaxWidth = 240.0;
static const CGFloat kCandidateCellSpacing = 2.0;
static const CGFloat kCandidateCellExtraWidth = 10.0;
static const NSInteger kCandidateWindowMaxVisibleCandidates = 9;

@interface HorizontalCandidateView : NSView

@property(nonatomic, weak) HorizontalCandidateWindowController *controller;
@property(nonatomic, copy) NSArray<NSString *> *candidates;
@property(nonatomic) NSInteger selectedLine;
@property(nonatomic) BOOL hasPreviousPage;
@property(nonatomic) BOOL hasNextPage;
@property(nonatomic, strong) NSMutableArray<NSValue *> *candidateFrames;
@property(nonatomic) NSRect previousPageFrame;
@property(nonatomic) NSRect nextPageFrame;

- (NSArray<NSNumber *> *)cellWidthsForAvailableWidth:(CGFloat)availableWidth candidateAttributes:(NSDictionary *)candidateAttrs numberAttributes:(NSDictionary *)numberAttrs;

@end

@interface HorizontalCandidateWindowController ()

@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) HorizontalCandidateView *candidateView;
@property(nonatomic) CGFloat candidateWindowWidth;
@property(nonatomic) CGFloat candidateWindowHeight;

@end

@implementation HorizontalCandidateView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _candidates = @[];
        _candidateFrames = [NSMutableArray array];
        _selectedLine = 0;
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    [[NSColor colorWithCalibratedRed:0.10 green:0.08 blue:0.12 alpha:0.98] setFill];
    NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.8, 0.8) xRadius:8 yRadius:8];
    [backgroundPath fill];

    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.9] setStroke];
    backgroundPath.lineWidth = 1.0;
    [backgroundPath stroke];

    [self.candidateFrames removeAllObjects];

    CGFloat x = kCandidateWindowHorizontalPadding;
    CGFloat availableWidth = NSWidth(bounds) - kCandidateWindowArrowWidth - kCandidateWindowHorizontalPadding * 2;

    NSDictionary *numberAttrs = @{
        NSFontAttributeName : [NSFont boldSystemFontOfSize:kSelectionKeyFontSize],
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.66 alpha:1.0],
    };
    NSDictionary *selectedNumberAttrs = @{
        NSFontAttributeName : [NSFont boldSystemFontOfSize:kSelectionKeyFontSize],
        NSForegroundColorAttributeName : [NSColor whiteColor],
    };
    NSDictionary *candidateAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:kCandidateFontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.88 alpha:1.0],
    };
    NSDictionary *selectedCandidateAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:kCandidateFontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : [NSColor whiteColor],
    };
    NSMutableParagraphStyle *candidateParagraph = [[NSMutableParagraphStyle alloc] init];
    candidateParagraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *candidateDrawingAttrs = [candidateAttrs mutableCopy];
    candidateDrawingAttrs[NSParagraphStyleAttributeName] = candidateParagraph;
    NSMutableDictionary *selectedCandidateDrawingAttrs = [selectedCandidateAttrs mutableCopy];
    selectedCandidateDrawingAttrs[NSParagraphStyleAttributeName] = candidateParagraph;
    NSMutableParagraphStyle *cellParagraph = [[NSMutableParagraphStyle alloc] init];
    cellParagraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSArray<NSNumber *> *cellWidths = [self cellWidthsForAvailableWidth:availableWidth
                                                     candidateAttributes:candidateAttrs
                                                        numberAttributes:numberAttrs];

    for (NSInteger i = 0; i < (NSInteger)self.candidates.count; i++) {
        NSString *number = [NSString stringWithFormat:@"%ld", (long)i + 1];
        NSString *candidate = self.candidates[i];
        CGFloat cellWidth = i < (NSInteger)cellWidths.count ? [cellWidths[i] doubleValue] : 36.0;

        if (x + cellWidth > NSWidth(bounds) - kCandidateWindowArrowWidth - 6.0) {
            cellWidth = NSWidth(bounds) - kCandidateWindowArrowWidth - 6.0 - x;
        }

        NSRect cellFrame = NSMakeRect(x, 4.0, MAX(28.0, cellWidth), NSHeight(bounds) - 8.0);
        [self.candidateFrames addObject:[NSValue valueWithRect:cellFrame]];

        BOOL selected = i == self.selectedLine;
        if (selected) {
            [[NSColor colorWithCalibratedRed:0.00 green:0.38 blue:0.86 alpha:1.0] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:cellFrame xRadius:6 yRadius:6] fill];
        }

        NSDictionary *currentNumberAttrs = selected ? selectedNumberAttrs : numberAttrs;
        NSDictionary *currentCandidateAttrs = selected ? selectedCandidateDrawingAttrs : candidateDrawingAttrs;
        NSMutableAttributedString *cellText =
            [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ %@", number, candidate]];
        [cellText addAttributes:currentNumberAttrs range:NSMakeRange(0, number.length)];
        [cellText addAttributes:currentCandidateAttrs range:NSMakeRange(number.length + 1, candidate.length)];
        [cellText addAttribute:NSParagraphStyleAttributeName value:cellParagraph range:NSMakeRange(0, cellText.length)];
        [cellText drawInRect:NSMakeRect(NSMinX(cellFrame) + 5.0, NSMinY(cellFrame) + 1.0, NSWidth(cellFrame) - 6.0,
                                        NSHeight(cellFrame) - 2.0)];

        x = NSMaxX(cellFrame) + kCandidateCellSpacing;
    }

    CGFloat arrowX = NSWidth(bounds) - kCandidateWindowArrowWidth;
    self.previousPageFrame = NSMakeRect(arrowX, 0.0, kCandidateWindowArrowWidth, NSHeight(bounds) / 2.0);
    self.nextPageFrame = NSMakeRect(arrowX, NSHeight(bounds) / 2.0, kCandidateWindowArrowWidth, NSHeight(bounds) / 2.0);
    [self drawChevronInRect:self.previousPageFrame pointingUp:YES enabled:self.hasPreviousPage];
    [self drawChevronInRect:self.nextPageFrame pointingUp:NO enabled:self.hasNextPage];
}

- (void)drawChevronInRect:(NSRect)rect pointingUp:(BOOL)pointingUp enabled:(BOOL)enabled {
    NSColor *color = enabled ? [NSColor colorWithCalibratedRed:1.00 green:0.42 blue:0.12 alpha:1.0]
                             : [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
    [color setStroke];

    CGFloat centerX = NSMidX(rect);
    CGFloat centerY = NSMidY(rect);
    CGFloat halfWidth = 5.0;
    CGFloat halfHeight = 3.5;
    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = 2.5;
    path.lineCapStyle = NSRoundLineCapStyle;
    path.lineJoinStyle = NSRoundLineJoinStyle;

    if (pointingUp) {
        [path moveToPoint:NSMakePoint(centerX - halfWidth, centerY + halfHeight)];
        [path lineToPoint:NSMakePoint(centerX, centerY - halfHeight)];
        [path lineToPoint:NSMakePoint(centerX + halfWidth, centerY + halfHeight)];
    } else {
        [path moveToPoint:NSMakePoint(centerX - halfWidth, centerY - halfHeight)];
        [path lineToPoint:NSMakePoint(centerX, centerY + halfHeight)];
        [path lineToPoint:NSMakePoint(centerX + halfWidth, centerY - halfHeight)];
    }
    [path stroke];
}

- (NSArray<NSNumber *> *)cellWidthsForAvailableWidth:(CGFloat)availableWidth candidateAttributes:(NSDictionary *)candidateAttrs numberAttributes:(NSDictionary *)numberAttrs {
    if (self.candidates.count == 0) {
        return @[];
    }

    NSMutableArray<NSNumber *> *desiredWidths = [NSMutableArray arrayWithCapacity:self.candidates.count];
    CGFloat totalDesiredWidth = 0.0;
    CGFloat totalSpacing = kCandidateCellSpacing * MAX(0, (NSInteger)self.candidates.count - 1);
    CGFloat usableWidth = MAX(0.0, availableWidth - totalSpacing);

    for (NSInteger i = 0; i < (NSInteger)self.candidates.count; i++) {
        NSString *number = [NSString stringWithFormat:@"%ld", (long)i + 1];
        NSString *candidate = self.candidates[i];
        CGFloat desiredWidth = [number sizeWithAttributes:numberAttrs].width + [@" " sizeWithAttributes:candidateAttrs].width +
                               [candidate sizeWithAttributes:candidateAttrs].width + kCandidateCellExtraWidth;
        desiredWidth = MAX(30.0, desiredWidth);
        desiredWidth = MIN(kCandidatePreferredMaxWidth, desiredWidth);
        [desiredWidths addObject:@(desiredWidth)];
        totalDesiredWidth += desiredWidth;
    }

    if (totalDesiredWidth <= usableWidth) {
        return desiredWidths;
    }

    CGFloat minimumWidth = usableWidth / self.candidates.count;
    minimumWidth = MAX(30.0, MIN(46.0, minimumWidth));
    CGFloat shrinkableWidth = 0.0;
    for (NSNumber *widthNumber in desiredWidths) {
        CGFloat width = widthNumber.doubleValue;
        if (width > minimumWidth) {
            shrinkableWidth += width - minimumWidth;
        }
    }

    CGFloat excessWidth = totalDesiredWidth - usableWidth;
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:desiredWidths.count];
    for (NSNumber *widthNumber in desiredWidths) {
        CGFloat width = widthNumber.doubleValue;
        if (shrinkableWidth > 0.0 && width > minimumWidth) {
            CGFloat shrink = excessWidth * ((width - minimumWidth) / shrinkableWidth);
            width -= shrink;
        }
        [result addObject:@(MAX(minimumWidth, width))];
    }
    return result;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    if (NSPointInRect(point, self.previousPageFrame)) {
        if (self.hasPreviousPage) {
            [self.controller.delegate horizontalCandidateWindow:self.controller didRequestPageOffset:-1];
        }
        return;
    }

    if (NSPointInRect(point, self.nextPageFrame)) {
        if (self.hasNextPage) {
            [self.controller.delegate horizontalCandidateWindow:self.controller didRequestPageOffset:1];
        }
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)self.candidateFrames.count; i++) {
        if (NSPointInRect(point, [self.candidateFrames[i] rectValue])) {
            [self.controller.delegate horizontalCandidateWindow:self.controller didSelectCandidateAtLine:i];
            return;
        }
    }
}

@end

@implementation HorizontalCandidateWindowController

+ (HorizontalCandidateWindowController *)sharedController {
    static HorizontalCandidateWindowController *sharedController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[HorizontalCandidateWindowController alloc] init];
    });
    return sharedController;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, kCandidateWindowMinWidth, kCandidateWindowHeight);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.level = CGShieldingWindowLevel() + 1;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.releasedWhenClosed = NO;

    self = [super initWithWindow:panel];
    if (self) {
        _panel = panel;
        _candidateWindowWidth = kCandidateWindowMinWidth;
        _candidateWindowHeight = kCandidateWindowHeight;
        _candidateView = [[HorizontalCandidateView alloc] initWithFrame:frame];
        _candidateView.controller = self;
        panel.contentView = _candidateView;
    }
    return self;
}

- (void)showCandidates:(NSArray<NSString *> *)candidates
            pageStart:(NSInteger)pageStart
          selectedLine:(NSInteger)selectedLine
        hasPreviousPage:(BOOL)hasPreviousPage
            hasNextPage:(BOOL)hasNextPage
              topLeftAt:(NSPoint)topLeftPoint {
    CGFloat width = [self widthForCandidates:candidates];
    self.candidateWindowWidth = width;
    self.candidateWindowHeight = kCandidateWindowHeight;

    self.candidateView.candidates = candidates ?: @[];
    self.candidateView.selectedLine = selectedLine;
    self.candidateView.hasPreviousPage = hasPreviousPage;
    self.candidateView.hasNextPage = hasNextPage;

    NSRect frame = NSMakeRect(topLeftPoint.x, topLeftPoint.y - kCandidateWindowHeight, width, kCandidateWindowHeight);
    NSScreen *screen = [NSScreen currentScreenForMouseLocation];
    if (screen) {
        NSRect visibleFrame = screen.visibleFrame;
        if (NSMaxX(frame) > NSMaxX(visibleFrame) - 8.0) {
            frame.origin.x = NSMaxX(visibleFrame) - NSWidth(frame) - 8.0;
        }
        if (NSMinX(frame) < NSMinX(visibleFrame) + 8.0) {
            frame.origin.x = NSMinX(visibleFrame) + 8.0;
        }
        if (NSMinY(frame) < NSMinY(visibleFrame) + 8.0) {
            frame.origin.y = topLeftPoint.y + 6.0;
        }
        if (NSMaxY(frame) > NSMaxY(visibleFrame) - 8.0) {
            frame.origin.y = NSMaxY(visibleFrame) - NSHeight(frame) - 8.0;
        }
    }
    [self.panel setFrame:frame display:NO];
    [self.candidateView setFrame:NSMakeRect(0, 0, width, kCandidateWindowHeight)];
    [self.candidateView setNeedsDisplay:YES];
    [self.panel orderFront:nil];
}

- (void)hideWindow {
    [self.panel orderOut:nil];
}

- (BOOL)isVisible {
    return self.panel.isVisible;
}

- (CGFloat)widthForCandidates:(NSArray<NSString *> *)candidates {
    NSDictionary *numberAttrs = @{
        NSFontAttributeName : [NSFont boldSystemFontOfSize:kSelectionKeyFontSize],
    };
    NSDictionary *candidateAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:kCandidateFontSize weight:NSFontWeightSemibold],
    };
    CGFloat width = kCandidateWindowHorizontalPadding * 2 + kCandidateWindowArrowWidth;
    for (NSInteger i = 0; i < (NSInteger)candidates.count; i++) {
        NSString *number = [NSString stringWithFormat:@"%ld", (long)i + 1];
        NSString *candidate = candidates[i];
        CGFloat cellWidth = [number sizeWithAttributes:numberAttrs].width + [@" " sizeWithAttributes:candidateAttrs].width +
                            [candidate sizeWithAttributes:candidateAttrs].width + kCandidateCellExtraWidth;
        width += MIN(kCandidatePreferredMaxWidth, MAX(30.0, cellWidth));
        if (i + 1 < (NSInteger)candidates.count) {
            width += kCandidateCellSpacing;
        }
    }
    if (width < kCandidateWindowMinWidth) {
        return kCandidateWindowMinWidth;
    }
    CGFloat screenLimitedMaxWidth = kCandidateWindowMaxWidth;
    NSScreen *screen = [NSScreen currentScreenForMouseLocation];
    if (screen) {
        screenLimitedMaxWidth = MIN(screenLimitedMaxWidth, NSWidth(screen.visibleFrame) - 32.0);
    }
    if (width > screenLimitedMaxWidth) {
        return screenLimitedMaxWidth;
    }
    return width;
}

- (NSInteger)visibleCandidateCountForCandidates:(NSArray<NSString *> *)candidates pageStart:(NSInteger)pageStart {
    if (candidates.count == 0 || pageStart < 0 || pageStart >= (NSInteger)candidates.count) {
        return 0;
    }

    NSDictionary *numberAttrs = @{
        NSFontAttributeName : [NSFont boldSystemFontOfSize:kSelectionKeyFontSize],
    };
    NSDictionary *candidateAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:kCandidateFontSize weight:NSFontWeightSemibold],
    };
    CGFloat maxWidth = kCandidateWindowMaxWidth;
    NSScreen *screen = [NSScreen currentScreenForMouseLocation];
    if (screen) {
        maxWidth = MIN(maxWidth, NSWidth(screen.visibleFrame) - 32.0);
    }
    CGFloat usedWidth = kCandidateWindowHorizontalPadding * 2 + kCandidateWindowArrowWidth;
    NSInteger count = 0;
    for (NSInteger i = pageStart; i < (NSInteger)candidates.count && count < kCandidateWindowMaxVisibleCandidates; i++) {
        NSString *number = [NSString stringWithFormat:@"%ld", (long)count + 1];
        NSString *candidate = candidates[i];
        CGFloat cellWidth = [number sizeWithAttributes:numberAttrs].width + [@" " sizeWithAttributes:candidateAttrs].width +
                            [candidate sizeWithAttributes:candidateAttrs].width + kCandidateCellExtraWidth;
        cellWidth = MIN(kCandidatePreferredMaxWidth, MAX(30.0, cellWidth));
        CGFloat nextWidth = usedWidth + (count > 0 ? kCandidateCellSpacing : 0.0) + cellWidth;
        if (count > 0 && nextWidth > maxWidth) {
            break;
        }
        usedWidth = nextWidth;
        count++;
    }
    return MAX(1, count);
}

@end
