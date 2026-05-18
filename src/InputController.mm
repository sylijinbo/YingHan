#import <AppKit/NSSpellChecker.h>
#import <CoreServices/CoreServices.h>

#import "InputApplicationDelegate.h"
#import "InputController.h"
#import "NSScreen+PointConversion.h"

extern IMKCandidates *sharedCandidates;
extern NSUserDefaults *preference;
extern ConversionEngine *engine;

#define MAX_RECENT_WORDS 4

typedef NSInteger KeyCode;
static const KeyCode KEY_RETURN = 36, KEY_SPACE = 49, KEY_DELETE = 51, KEY_ESC = 53, KEY_ARROW_DOWN = 125, KEY_ARROW_UP = 126,
                     KEY_ARROW_LEFT = 123, KEY_ARROW_RIGHT = 124, KEY_LEFT_SHIFT = 56, KEY_RIGHT_SHIFT = 60, KEY_LEFT_COMMAND = 55,
                     KEY_RIGHT_COMMAND = 54;
static const KeyCode KEY_1 = 18, KEY_2 = 19, KEY_3 = 20, KEY_4 = 21, KEY_5 = 23, KEY_6 = 22, KEY_7 = 26, KEY_8 = 28, KEY_9 = 25;
static const KeyCode KEY_KEYPAD_1 = 83, KEY_KEYPAD_2 = 84, KEY_KEYPAD_3 = 85, KEY_KEYPAD_4 = 86, KEY_KEYPAD_5 = 87,
                     KEY_KEYPAD_6 = 88, KEY_KEYPAD_7 = 89, KEY_KEYPAD_8 = 91, KEY_KEYPAD_9 = 92;

@interface InputController ()

- (void)showIMEPreferences:(id)sender;
- (void)clickAbout:(NSMenuItem *)sender;
- (BOOL)isConfiguredShiftModeSwitchKey:(KeyCode)keyCode;
- (BOOL)isConfiguredCommandPinyinSwitchKey:(KeyCode)keyCode;
- (void)switchToChineseMode:(id)sender;
- (void)toggleEnglishPinyinMode:(id)sender;
- (BOOL)handleCandidateKeyEvent:(NSEvent *)event client:(id)sender;
- (BOOL)moveVisibleCandidateHighlightByOffset:(NSInteger)offset;
- (BOOL)pageVisibleCandidatesByOffset:(NSInteger)offset;
- (NSInteger)currentVisibleCandidateLine;
- (void)reloadCandidatePanelForCurrentInput;
- (NSArray *)visibleCandidatesForPageStartIndex:(NSInteger)pageStartIndex;
- (void)showHorizontalCandidatePageStartingAt:(NSInteger)pageStartIndex selectedLine:(NSInteger)selectedLine;
- (BOOL)syncCurrentCandidateIndexWithIMKSelection;
- (void)syncCurrentCandidateIndexWithCandidateString:(NSString *)candidate;
- (void)resetCandidateSelection;
- (void)prepareCandidatePanelForDisplay;
- (NSInteger)clampedCurrentCandidateIndex;
- (void)updateComposedCandidateAtAbsoluteIndex:(NSInteger)candidateIndex;
- (void)selectCandidateAtAbsoluteIndex:(NSInteger)candidateIndex;
- (NSString *)candidateForSelectionKeyIndex:(NSInteger)selectionKeyIndex;
- (NSString *)fallbackCandidateForSelectionKeyIndex:(NSInteger)selectionKeyIndex;
- (NSInteger)selectionKeyIndexForEvent:(NSEvent *)event;

@end

@implementation InputController

- (NSUInteger)recognizedEvents:(id)sender {
    return NSEventMaskKeyDown | NSEventMaskFlagsChanged;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    NSUInteger modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    bool handled = NO;
    switch (event.type) {
    case NSEventTypeFlagsChanged:
        // NSLog(@"YingHan event modifierFlags %lu, event keyCode: %@", (unsigned long)[event modifierFlags], [event keyCode]);

        if (_lastEventTypes[1] == NSEventTypeFlagsChanged && _lastModifiers[1] == modifiers) {
            return YES;
        }

        // Configured Command key: always switch to Chinese mode.
        if (modifiers == 0 && _lastEventTypes[1] == NSEventTypeFlagsChanged &&
            [self isConfiguredCommandPinyinSwitchKey:event.keyCode]) {
            [self switchToChineseMode:sender];
        }

        if (modifiers == 0 && _lastEventTypes[1] == NSEventTypeFlagsChanged && _lastModifiers[1] == NSEventModifierFlagShift &&
            [self isConfiguredShiftModeSwitchKey:event.keyCode] && !(_lastModifiers[0] & NSEventModifierFlagShift)) {
            [self toggleEnglishPinyinMode:sender];
        }
        break;
    case NSEventTypeKeyDown:
        // Let system and app shortcuts such as Command+C/V pass through before
        // treating their letter key as pinyin input.
        if (modifiers & NSEventModifierFlagCommand)
            break;

        if (modifiers & NSEventModifierFlagOption) {
            return false;
        }

        if (modifiers & NSEventModifierFlagControl) {
            return false;
        }

        if ([self handleCandidateKeyEvent:event client:sender]) {
            handled = YES;
            break;
        }

        if ([sharedCandidates isVisible] && (event.keyCode == KEY_ARROW_UP || event.keyCode == KEY_ARROW_DOWN)) {
            handled = NO;
            break;
        }

        if (_inputMode == YingHanInputModeEnglish) {
            break;
        }

        if (_inputMode == YingHanInputModeChinese && [self isPinyinChar:event]) {
            handled = [self onPinyinKeyEvent:event client:sender];
            break;
        }

        handled = [self onKeyEvent:event client:sender];
        break;
    default:
        break;
    }

    _lastModifiers[0] = _lastModifiers[1];
    _lastEventTypes[0] = _lastEventTypes[1];
    _lastModifiers[1] = modifiers;
    _lastEventTypes[1] = event.type;
    return handled;
}

- (BOOL)isConfiguredShiftModeSwitchKey:(KeyCode)keyCode {
    return keyCode == KEY_LEFT_SHIFT || keyCode == KEY_RIGHT_SHIFT;
}

- (BOOL)isConfiguredCommandPinyinSwitchKey:(KeyCode)keyCode {
    return keyCode == KEY_LEFT_COMMAND || keyCode == KEY_RIGHT_COMMAND;
}

- (void)switchToChineseMode:(id)sender {
    NSString *bufferedText = [self originalBuffer];
    if (bufferedText && bufferedText.length > 0) {
        [self cancelComposition];
        [self commitCompositionWithoutSpace:sender];
    }

    _inputMode = YingHanInputModeChinese;
    [self resetContext];
}

- (void)toggleEnglishPinyinMode:(id)sender {
    NSString *bufferedText = [self originalBuffer];
    BOOL hasBufferedText = bufferedText && bufferedText.length > 0;

    if (_inputMode == YingHanInputModeEnglish) {
        if (hasBufferedText) {
            [self cancelComposition];
            [self commitCompositionWithoutSpace:sender];
        }
        _inputMode = YingHanInputModePinyin;
    } else {
        if (hasBufferedText) {
            [self cancelComposition];
            [self commitCompositionWithoutSpace:sender];
        }
        _inputMode = YingHanInputModeEnglish;
    }

    [self resetContext];
}

- (BOOL)isPinyinChar:(NSEvent *)event {
    NSString *characters = event.characters;
    if (!characters || characters.length == 0)
        return NO;
    char ch = [characters characterAtIndex:0];
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

- (BOOL)onPinyinKeyEvent:(NSEvent *)event client:(id)sender {
    _currentClient = sender;
    NSInteger keyCode = event.keyCode;
    NSString *characters = event.characters;

    NSString *bufferedText = [self originalBuffer];
    bool hasBufferedText = bufferedText && bufferedText.length > 0;

    if (keyCode == KEY_DELETE) {
        if (hasBufferedText) {
            return [self deleteBackward:sender];
        }
        return NO;
    }

    if (keyCode == KEY_SPACE) {
        if (hasBufferedText) {
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_RETURN) {
        if (hasBufferedText) {
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_ESC) {
        [self cancelComposition];
        [self reset];
        [self resetContext];
        return YES;
    }

    char ch = [characters characterAtIndex:0];
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        [self originalBufferAppend:characters client:sender];
        [self resetCandidateSelection];
        [self reloadCandidatePanelForCurrentInput];
        return YES;
    }

    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:ch]) {
        if (hasBufferedText && [sharedCandidates isVisible]) {
            int pressedNumber = characters.intValue;
            NSString *candidate = [self candidateForSelectionKeyIndex:pressedNumber - 1];
            if (!candidate) {
                return YES;
            }
            [self cancelComposition];
            [self setComposedBuffer:candidate];
            [self setOriginalBuffer:candidate];
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
    }

    return NO;
}

- (BOOL)onKeyEvent:(NSEvent *)event client:(id)sender {
    _currentClient = sender;
    NSInteger keyCode = event.keyCode;
    NSString *characters = event.characters;

    NSString *bufferedText = [self originalBuffer];
    bool hasBufferedText = bufferedText && bufferedText.length > 0;

    if (keyCode == KEY_DELETE) {
        if (hasBufferedText) {
            return [self deleteBackward:sender];
        }

        return NO;
    }

    if (keyCode == KEY_SPACE) {
        if (hasBufferedText) {
            [self commitComposition:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_RETURN) {
        if (hasBufferedText) {
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_ESC) {
        [self cancelComposition];
        [sender insertText:@""];
        [self reset];
        [self resetContext];
        return YES;
    }

    char ch = [characters characterAtIndex:0];
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        [self originalBufferAppend:characters client:sender];
        [self resetCandidateSelection];
        [self reloadCandidatePanelForCurrentInput];
        return YES;
    }

    if ([self isMojaveAndLaterSystem]) {
        if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:ch]) {
            if (!hasBufferedText) {
                [self appendToComposedBuffer:characters];
                [self commitCompositionWithoutSpace:sender];
                return YES;
            }
        }
    }

    if ([[NSCharacterSet punctuationCharacterSet] characterIsMember:ch] || [[NSCharacterSet symbolCharacterSet] characterIsMember:ch]) {
        if (hasBufferedText) {
            [self appendToComposedBuffer:characters];
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
    }

    return NO;
}

- (BOOL)handleCandidateKeyEvent:(NSEvent *)event client:(id)sender {
    if (![sharedCandidates isVisible]) {
        return NO;
    }

    NSString *bufferedText = [self originalBuffer];
    if (!bufferedText || bufferedText.length == 0) {
        return NO;
    }

    _currentClient = sender;
    NSInteger keyCode = event.keyCode;

    if ([sharedCandidates panelType] == kIMKSingleRowSteppingCandidatePanel) {
        if (keyCode == KEY_ARROW_LEFT) {
            return [self moveVisibleCandidateHighlightByOffset:-1];
        }

        if (keyCode == KEY_ARROW_RIGHT) {
            return [self moveVisibleCandidateHighlightByOffset:1];
        }

        if (keyCode == KEY_ARROW_UP) {
            return [self pageVisibleCandidatesByOffset:-1];
        }

        if (keyCode == KEY_ARROW_DOWN) {
            return [self pageVisibleCandidatesByOffset:1];
        }
    }

    if (keyCode == KEY_ARROW_UP || keyCode == KEY_ARROW_DOWN) {
        return NO;
    }

    NSInteger selectionKeyIndex = [self selectionKeyIndexForEvent:event];
    if (selectionKeyIndex == NSNotFound) {
        return NO;
    }

    NSString *candidate = [self candidateForSelectionKeyIndex:selectionKeyIndex];
    if (!candidate) {
        return YES;
    }

    [self cancelComposition];
    [self setComposedBuffer:candidate];
    [self setOriginalBuffer:candidate];
    if (_inputMode == YingHanInputModeChinese) {
        [self commitCompositionWithoutSpace:sender];
    } else {
        [self commitComposition:sender];
    }
    return YES;
}

- (BOOL)moveVisibleCandidateHighlightByOffset:(NSInteger)offset {
    if (![sharedCandidates isVisible] || _candidates.count == 0) {
        return NO;
    }
    if (offset == 0) {
        return YES;
    }

    if ([sharedCandidates panelType] == kIMKSingleRowSteppingCandidatePanel) {
        NSArray *visibleCandidates = [self visibleCandidatesForPageStartIndex:_horizontalPageStartIndex];
        if (visibleCandidates.count == 0) {
            return YES;
        }

        NSInteger selectedLine = _horizontalSelectedLine + (offset > 0 ? 1 : -1);
        if (selectedLine < 0) {
            selectedLine = 0;
        } else if (selectedLine >= (NSInteger)visibleCandidates.count) {
            selectedLine = visibleCandidates.count - 1;
        }

        [self showHorizontalCandidatePageStartingAt:_horizontalPageStartIndex selectedLine:selectedLine];
        return YES;
    }

    if (offset > 0)
        [sharedCandidates moveRight:self];
    else
        [sharedCandidates moveLeft:self];

    NSAttributedString *candidateString = [sharedCandidates selectedCandidateString];
    if (candidateString.string.length > 0)
        [self candidateSelectionChanged:candidateString];
    return YES;
}

- (BOOL)pageVisibleCandidatesByOffset:(NSInteger)offset {
    if (![sharedCandidates isVisible] || _candidates.count == 0) {
        return NO;
    }

    if ([sharedCandidates panelType] == kIMKSingleRowSteppingCandidatePanel) {
        NSInteger pageStartIndex = _horizontalPageStartIndex + (offset > 0 ? 9 : -9);
        if (pageStartIndex < 0) {
            pageStartIndex = 0;
        } else if (pageStartIndex >= (NSInteger)_candidates.count) {
            pageStartIndex = ((NSInteger)(_candidates.count - 1) / 9) * 9;
        }

        [self showHorizontalCandidatePageStartingAt:pageStartIndex selectedLine:_horizontalSelectedLine];
        return YES;
    }

    if (offset > 0)
        [sharedCandidates pageDown:self];
    else
        [sharedCandidates pageUp:self];

    NSAttributedString *candidateString = [sharedCandidates selectedCandidateString];
    if (candidateString.string.length > 0)
        [self candidateSelectionChanged:candidateString];
    return YES;
}

- (NSInteger)currentVisibleCandidateLine {
    NSAttributedString *selectedCandidate = [sharedCandidates selectedCandidateString];
    if (selectedCandidate.string.length > 0) {
        NSInteger selectedIdentifier = [sharedCandidates candidateStringIdentifier:selectedCandidate.string];
        NSInteger selectedLine = [sharedCandidates lineNumberForCandidateWithIdentifier:selectedIdentifier];
        if (selectedLine != NSNotFound) {
            if (selectedLine < 0) {
                return 0;
            }
            if (selectedLine > 8) {
                return 8;
            }
            return selectedLine;
        }
    }

    NSInteger currentIndex = _currentCandidateIndex;
    if (currentIndex < 1) {
        currentIndex = 1;
    } else if (currentIndex > (NSInteger)_candidates.count) {
        currentIndex = _candidates.count;
    }
    return (currentIndex - 1) % 9;
}

- (void)reloadCandidatePanelForCurrentInput {
    [self prepareCandidatePanelForDisplay];

    if ([sharedCandidates panelType] == kIMKSingleRowSteppingCandidatePanel) {
        [self candidates:self];
        [self showHorizontalCandidatePageStartingAt:0 selectedLine:0];
        [sharedCandidates show:kIMKLocateCandidatesBelowHint];
        return;
    }

    [sharedCandidates updateCandidates];
    [sharedCandidates show:kIMKLocateCandidatesBelowHint];
}

- (NSArray *)visibleCandidatesForPageStartIndex:(NSInteger)pageStartIndex {
    if (_candidates.count == 0) {
        return @[];
    }

    if (pageStartIndex < 0) {
        pageStartIndex = 0;
    } else if (pageStartIndex >= (NSInteger)_candidates.count) {
        pageStartIndex = ((NSInteger)(_candidates.count - 1) / 9) * 9;
    }

    NSInteger candidateCount = MIN(9, (NSInteger)_candidates.count - pageStartIndex);
    return [_candidates subarrayWithRange:NSMakeRange(pageStartIndex, candidateCount)];
}

- (void)showHorizontalCandidatePageStartingAt:(NSInteger)pageStartIndex selectedLine:(NSInteger)selectedLine {
    NSArray *visibleCandidates = [self visibleCandidatesForPageStartIndex:pageStartIndex];
    if (visibleCandidates.count == 0) {
        [sharedCandidates setCandidateData:@[]];
        _horizontalPageStartIndex = 0;
        _horizontalSelectedLine = 0;
        return;
    }

    if (pageStartIndex < 0) {
        pageStartIndex = 0;
    } else if (pageStartIndex >= (NSInteger)_candidates.count) {
        pageStartIndex = ((NSInteger)(_candidates.count - 1) / 9) * 9;
    }

    [sharedCandidates setCandidateData:visibleCandidates];
    [sharedCandidates clearSelection];

    NSString *firstCandidate = visibleCandidates[0];
    NSInteger firstCandidateIdentifier = [sharedCandidates candidateStringIdentifier:firstCandidate];
    [sharedCandidates selectCandidateWithIdentifier:firstCandidateIdentifier];

    if (selectedLine < 0) {
        selectedLine = 0;
    } else if (selectedLine >= (NSInteger)visibleCandidates.count) {
        selectedLine = visibleCandidates.count - 1;
    }

    _horizontalPageStartIndex = pageStartIndex;
    _horizontalSelectedLine = selectedLine;

    NSInteger candidateIndex = pageStartIndex + selectedLine + 1;
    [self updateComposedCandidateAtAbsoluteIndex:candidateIndex];

    for (NSInteger i = 0; i < selectedLine; i++) {
        [sharedCandidates moveRight:self];
    }
}

- (BOOL)syncCurrentCandidateIndexWithIMKSelection {
    NSAttributedString *selectedCandidate = [sharedCandidates selectedCandidateString];
    if (selectedCandidate.string.length == 0) {
        return NO;
    }

    NSUInteger candidateIndex = [_candidates indexOfObject:selectedCandidate.string];
    if (candidateIndex == NSNotFound) {
        return NO;
    }

    _currentCandidateIndex = candidateIndex + 1;
    return YES;
}

- (void)syncCurrentCandidateIndexWithCandidateString:(NSString *)candidate {
    if (!candidate || candidate.length == 0) {
        return;
    }

    NSUInteger candidateIndex = [_candidates indexOfObject:candidate];
    if (candidateIndex != NSNotFound) {
        _currentCandidateIndex = candidateIndex + 1;
    }
}

- (void)resetCandidateSelection {
    _currentCandidateIndex = 1;
    _horizontalPageStartIndex = 0;
    _horizontalSelectedLine = 0;
    [sharedCandidates clearSelection];
}

- (void)prepareCandidatePanelForDisplay {
    [sharedCandidates setAttributes:@{
        IMKCandidatesSendServerKeyEventFirst : @YES,
    }];
}

- (NSInteger)clampedCurrentCandidateIndex {
    NSInteger currentIndex = _currentCandidateIndex;
    if (currentIndex < 1) {
        currentIndex = 1;
    } else if (currentIndex > (NSInteger)_candidates.count) {
        currentIndex = _candidates.count;
    }
    _currentCandidateIndex = currentIndex;
    return currentIndex;
}

- (void)updateComposedCandidateAtAbsoluteIndex:(NSInteger)candidateIndex {
    if (candidateIndex < 1 || candidateIndex > (NSInteger)_candidates.count) {
        return;
    }

    NSString *candidate = _candidates[candidateIndex - 1];
    _currentCandidateIndex = candidateIndex;
    [self candidateSelectionChanged:[[NSAttributedString alloc] initWithString:candidate]];
}

- (void)selectCandidateAtAbsoluteIndex:(NSInteger)candidateIndex {
    if (candidateIndex < 1 || candidateIndex > (NSInteger)_candidates.count) {
        return;
    }

    NSString *candidate = _candidates[candidateIndex - 1];
    NSInteger candidateIdentifier = [sharedCandidates candidateStringIdentifier:candidate];
    [sharedCandidates selectCandidateWithIdentifier:candidateIdentifier];
    _currentCandidateIndex = candidateIndex;
    [self candidateSelectionChanged:[[NSAttributedString alloc] initWithString:candidate]];
}

- (NSString *)candidateForSelectionKeyIndex:(NSInteger)selectionKeyIndex {
    if (selectionKeyIndex < 0 || selectionKeyIndex >= 9) {
        return nil;
    }

    if ([sharedCandidates panelType] == kIMKSingleRowSteppingCandidatePanel) {
        NSArray *visibleCandidates = [self visibleCandidatesForPageStartIndex:_horizontalPageStartIndex];
        if (selectionKeyIndex >= (NSInteger)visibleCandidates.count) {
            return nil;
        }

        NSString *candidate = visibleCandidates[selectionKeyIndex];
        _horizontalSelectedLine = selectionKeyIndex;
        [self syncCurrentCandidateIndexWithCandidateString:candidate];
        return candidate;
    }

    NSInteger candidateIdentifier = [sharedCandidates candidateIdentifierAtLineNumber:selectionKeyIndex];
    if (candidateIdentifier != NSNotFound && [sharedCandidates selectCandidateWithIdentifier:candidateIdentifier]) {
        NSAttributedString *candidateString = [sharedCandidates selectedCandidateString];
        if (candidateString.string.length > 0) {
            [self syncCurrentCandidateIndexWithCandidateString:candidateString.string];
            return candidateString.string;
        }
    }

    return [self fallbackCandidateForSelectionKeyIndex:selectionKeyIndex];
}

- (NSString *)fallbackCandidateForSelectionKeyIndex:(NSInteger)selectionKeyIndex {
    if (_candidates.count == 0) {
        return nil;
    }

    NSInteger currentIndex = _currentCandidateIndex;
    if (currentIndex < 1) {
        currentIndex = 1;
    } else if (currentIndex > (NSInteger)_candidates.count) {
        currentIndex = _candidates.count;
    }

    NSInteger pageStartIndex = ((currentIndex - 1) / 9) * 9;
    NSInteger candidateIndex = pageStartIndex + selectionKeyIndex;
    if (candidateIndex < 0 || candidateIndex >= (NSInteger)_candidates.count) {
        return nil;
    }

    return _candidates[candidateIndex];
}

- (NSInteger)selectionKeyIndexForEvent:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers;
    if (!characters || characters.length == 0) {
        characters = event.characters;
    }

    if (characters.length > 0) {
        unichar ch = [characters characterAtIndex:0];
        if (ch >= '1' && ch <= '9') {
            return ch - '1';
        }
    }

    switch (event.keyCode) {
    case KEY_1:
    case KEY_KEYPAD_1:
        return 0;
    case KEY_2:
    case KEY_KEYPAD_2:
        return 1;
    case KEY_3:
    case KEY_KEYPAD_3:
        return 2;
    case KEY_4:
    case KEY_KEYPAD_4:
        return 3;
    case KEY_5:
    case KEY_KEYPAD_5:
        return 4;
    case KEY_6:
    case KEY_KEYPAD_6:
        return 5;
    case KEY_7:
    case KEY_KEYPAD_7:
        return 6;
    case KEY_8:
    case KEY_KEYPAD_8:
        return 7;
    case KEY_9:
    case KEY_KEYPAD_9:
        return 8;
    default:
        return NSNotFound;
    }
}

- (BOOL)isMojaveAndLaterSystem {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    return (version.majorVersion == 10 && version.minorVersion > 13) || version.majorVersion > 10;
}

- (BOOL)deleteBackward:(id)sender {
    NSMutableString *originalText = [self originalBuffer];

    if (_insertionIndex > 0) {
        --_insertionIndex;

        NSString *convertedString = [originalText substringToIndex:originalText.length - 1];

        [self setComposedBuffer:convertedString];
        [self setOriginalBuffer:convertedString];

        [self showPreeditString:convertedString];

        if (convertedString && convertedString.length > 0) {
            [self resetCandidateSelection];
            [self reloadCandidatePanelForCurrentInput];
        } else {
            [self reset];
        }
        return YES;
    }
    return NO;
}

- (void)commitComposition:(id)sender {
    NSString *text = [self composedBuffer];

    if (text == nil || text.length == 0) {
        text = [self originalBuffer];
    }

    [self recordCommittedWord:text];

    BOOL commitWordWithSpace = [preference boolForKey:@"commitWordWithSpace"];

    if (_inputMode != YingHanInputModeChinese && commitWordWithSpace && text.length > 0) {
        char firstChar = [text characterAtIndex:0];
        char lastChar = [text characterAtIndex:text.length - 1];
        if (![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:firstChar] && lastChar != '\'') {
            text = [NSString stringWithFormat:@"%@ ", text];
        }
    }

    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];

    [self reset];
}

- (void)commitCompositionWithoutSpace:(id)sender {
    NSString *text = [self composedBuffer];

    if (text == nil || text.length == 0) {
        text = [self originalBuffer];
    }

    [self recordCommittedWord:text];

    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];

    [self reset];
}

- (void)reset {
    [self setComposedBuffer:@""];
    [self setOriginalBuffer:@""];
    _insertionIndex = 0;
    _currentCandidateIndex = 1;
    _horizontalPageStartIndex = 0;
    _horizontalSelectedLine = 0;
    [sharedCandidates clearSelection];
    [sharedCandidates hide];
    _candidates = [[NSMutableArray alloc] init];
    [sharedCandidates setCandidateData:@[]];
    [_annotationWin setAnnotation:@""];
    [_annotationWin hideWindow];
}

- (void)resetContext {
    [_recentWords removeAllObjects];
}

- (NSString *)recentContext {
    if (_recentWords.count == 0)
        return nil;
    return [_recentWords componentsJoinedByString:@" "];
}

- (void)recordCommittedWord:(NSString *)word {
    if (!word || word.length == 0)
        return;
    // Only record alphabetic words
    NSString *trimmed = [word stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]];
    if (trimmed.length == 0)
        return;

    // Check if word is purely alphabetic
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSInteger i = 0; i < (NSInteger)trimmed.length; i++) {
        if (![letters characterIsMember:[trimmed characterAtIndex:i]])
            return;
    }

    [_recentWords addObject:trimmed.lowercaseString];
    while (_recentWords.count > MAX_RECENT_WORDS) {
        [_recentWords removeObjectAtIndex:0];
    }
}

- (NSMutableString *)composedBuffer {
    if (_composedBuffer == nil) {
        _composedBuffer = [[NSMutableString alloc] init];
    }
    return _composedBuffer;
}

- (void)setComposedBuffer:(NSString *)string {
    NSMutableString *buffer = [self composedBuffer];
    [buffer setString:string];
}

- (NSMutableString *)originalBuffer {
    if (_originalBuffer == nil) {
        _originalBuffer = [[NSMutableString alloc] init];
    }
    return _originalBuffer;
}

- (void)setOriginalBuffer:(NSString *)input {
    NSMutableString *buffer = [self originalBuffer];
    [buffer setString:input];
}

- (void)showPreeditString:(NSString *)input {
    NSDictionary *attrs = [self markForStyle:kTSMHiliteSelectedRawText atRange:NSMakeRange(0, input.length)];
    NSAttributedString *attrString;

    NSString *originalBuff = [NSString stringWithString:[self originalBuffer]];
    if ([input.lowercaseString hasPrefix:originalBuff.lowercaseString]) {
        attrString = [[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@%@", originalBuff, [input substringFromIndex:originalBuff.length]]
                attributes:attrs];
    } else {
        attrString = [[NSAttributedString alloc] initWithString:input attributes:attrs];
    }

    [_currentClient setMarkedText:attrString
                   selectionRange:NSMakeRange(input.length, 0)
                 replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}

- (void)originalBufferAppend:(NSString *)input client:(id)sender {
    NSMutableString *buffer = [self originalBuffer];
    [buffer appendString:input];
    _insertionIndex++;
    [self showPreeditString:buffer];
}

- (void)appendToComposedBuffer:(NSString *)input {
    NSMutableString *buffer = [self composedBuffer];
    [buffer appendString:input];
}

- (NSArray *)candidates:(id)sender {
    NSString *originalInput = [self originalBuffer];

    if (_inputMode == YingHanInputModeChinese) {
        NSArray *hanziList = [engine fetchHanZiByPinyinWithPrefix:originalInput];
        if (hanziList.count == 0) {
            _candidates = [NSMutableArray arrayWithArray:@[ originalInput ]];
            return @[ originalInput ];
        }
        _candidates = [NSMutableArray arrayWithArray:hanziList];
        return hanziList;
    }

    NSArray *candidateList = [engine getCandidates:originalInput];

    // Blend n-gram predictions based on recent context
    BOOL enableNextWordPrediction = [preference boolForKey:@"enableNextWordPrediction"];
    NSString *ctx = [self recentContext];
    if (enableNextWordPrediction && ctx && originalInput.length > 0) {
        NSArray *predictions = [engine predictNextWordsForContext:ctx prefixFilter:originalInput maxResults:5];
        if (predictions.count > 0) {
            NSMutableArray *blended = [NSMutableArray arrayWithArray:predictions];
            for (NSString *word in candidateList) {
                if (![blended containsObject:word]) {
                    [blended addObject:word];
                }
            }
            _candidates = [NSMutableArray arrayWithArray:blended];
            return blended;
        }
    }

    _candidates = [NSMutableArray arrayWithArray:candidateList];
    return candidateList;
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
    [self syncCurrentCandidateIndexWithCandidateString:candidateString.string];

    [self _updateComposedBuffer:candidateString];

    NSString *originalInput = [self originalBuffer];
    [self showPreeditString:originalInput.length > 0 ? originalInput : candidateString.string];

    _insertionIndex = originalInput.length > 0 ? originalInput.length : candidateString.length;

    BOOL showTranslation = [preference boolForKey:@"showTranslation"];
    if (showTranslation) {
        [self showAnnotation:candidateString];
    }
}

- (void)candidateSelected:(NSAttributedString *)candidateString {
    [self _updateComposedBuffer:candidateString];

    [self commitComposition:_currentClient];
}

- (void)_updateComposedBuffer:(NSAttributedString *)candidateString {
    [self setComposedBuffer:candidateString.string];
}

- (void)activateServer:(id)sender {
    [sender overrideKeyboardWithKeyboardNamed:@"com.apple.keylayout.US"];

    if (_annotationWin == nil) {
        _annotationWin = [AnnotationWinController sharedController];
    }

    _currentCandidateIndex = 1;
    _horizontalPageStartIndex = 0;
    _horizontalSelectedLine = 0;
    _candidates = [[NSMutableArray alloc] init];
    _recentWords = [[NSMutableArray alloc] init];
}

- (void)deactivateServer:(id)sender {
    [self reset];
    [self resetContext];
}

- (NSMenu *)menu {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [NSApp.delegate performSelector:NSSelectorFromString(@"menu")];
#pragma clang diagnostic pop
}

- (void)showIMEPreferences:(id)sender {
    [self openUrl:@"http://127.0.0.1:62718/index.html"];
}

- (void)clickAbout:(NSMenuItem *)sender {
    [self openUrl:@"https://github.com/sylijinbo/YingHan"];
}

- (void)openUrl:(NSString *)url {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];

    NSURL *targetURL = [NSURL URLWithString:url];
    if (@available(macOS 10.15, *)) {
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration new];
        configuration.promptsUserIfNeeded = YES;
        configuration.createsNewApplicationInstance = NO;

        [ws openURL:targetURL
                configuration:configuration
            completionHandler:^(NSRunningApplication *_Nullable app, NSError *_Nullable error) {
                if (error) {
                    NSLog(@"Failed to open URL: %@", error.localizedDescription);
                }
            }];
    } else {
        [ws openURL:targetURL];
    }
}

- (void)showAnnotation:(NSAttributedString *)candidateString {
    NSString *annotation = [engine getAnnotation:candidateString.string];
    if (annotation && annotation.length > 0) {
        [_annotationWin setAnnotation:annotation];
        [_annotationWin showWindow:[self calculatePositionOfTranslationWindow]];
    } else {
        [_annotationWin hideWindow];
    }
}

- (NSPoint)calculatePositionOfTranslationWindow {
    // Mac Cocoa ui default coordinate system: left-bottom, origin: (x:0, y:0) ↑→
    // see https://developer.apple.com/library/archive/documentation/General/Conceptual/Devpedia-CocoaApp/CoordinateSystem.html
    // see https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html
    // Notice: there is a System bug: candidateFrame.origin always be (0,0), so we can't depending on the origin point.
    NSRect candidateFrame = [sharedCandidates candidateFrame];

    // line-box of current input text: (width:1, height:17)
    NSRect lineRect;
    [_currentClient attributesForCharacterIndex:0 lineHeightRectangle:&lineRect];
    NSPoint cursorPoint = NSMakePoint(NSMinX(lineRect), NSMinY(lineRect));
    NSPoint positionPoint = NSMakePoint(NSMinX(lineRect), NSMinY(lineRect));
    positionPoint.x = positionPoint.x + candidateFrame.size.width;
    NSScreen *currentScreen = [NSScreen currentScreenForMouseLocation];
    NSPoint currentPoint = [currentScreen convertPointToScreenCoordinates:cursorPoint];
    NSRect rect = currentScreen.frame;
    int screenWidth = (int)rect.size.width;
    int marginToCandidateFrame = 20;
    int annotationWindowWidth = _annotationWin.width + marginToCandidateFrame;
    int lineHeight = lineRect.size.height; // 17px

    if (screenWidth - currentPoint.x >= candidateFrame.size.width) {
        // safe distance to display candidateFrame at current cursor's left-side.
        if (screenWidth - currentPoint.x < candidateFrame.size.width + annotationWindowWidth) {
            positionPoint.x = positionPoint.x - candidateFrame.size.width - annotationWindowWidth;
        }
    } else {
        // assume candidateFrame will display at current cursor's right-side.
        positionPoint.x = screenWidth - candidateFrame.size.width - annotationWindowWidth;
    }
    if (currentPoint.y >= candidateFrame.size.height) {
        positionPoint.y = positionPoint.y - 8; // Both 8 and 3 are magic numbers to adjust the position
    } else {
        positionPoint.y = positionPoint.y + candidateFrame.size.height + lineHeight + 3;
    }

    return positionPoint;
}

@end
