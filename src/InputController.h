#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

#import "AnnotationWinController.h"
#import "ConversionEngine.h"
#import "HorizontalCandidateWindowController.h"

typedef NS_ENUM(NSUInteger, YingHanInputMode) {
    YingHanInputModeEnglish,
    YingHanInputModePinyin,
    YingHanInputModeChinese,
};

@interface InputController : IMKInputController {
    NSMutableString *_composedBuffer;
    NSMutableString *_originalBuffer;
    NSInteger _insertionIndex;
    NSInteger _currentCandidateIndex;
    NSInteger _horizontalPageStartIndex;
    NSInteger _horizontalSelectedLine;
    NSMutableArray *_candidates;
    YingHanInputMode _inputMode;
    id _currentClient;
    NSUInteger _lastModifiers[2];
    NSEventType _lastEventTypes[2];
    AnnotationWinController *_annotationWin;
    HorizontalCandidateWindowController *_horizontalCandidateWin;
    NSMutableArray<NSString *> *_recentWords;
}

- (NSMutableString *)composedBuffer;
- (void)setComposedBuffer:(NSString *)string;
- (NSMutableString *)originalBuffer;
- (void)originalBufferAppend:(NSString *)string client:(id)sender;
- (void)setOriginalBuffer:(NSString *)string;
- (NSString *)recentContext;
- (void)recordCommittedWord:(NSString *)word;
- (void)resetContext;

@end
