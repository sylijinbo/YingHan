#import "WebServer.h"
#import "ConversionEngine.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerDataResponse.h"
#import <InputMethodKit/InputMethodKit.h>

extern NSUserDefaults *preference;
extern ConversionEngine *engine;
extern IMKCandidates *sharedCandidates;

NSString *TRANSLATION_KEY = @"showTranslation";
NSString *COMMIT_WORD_WITH_SPACE_KEY = @"commitWordWithSpace";
NSString *ENABLE_NEXT_WORD_PREDICTION_KEY = @"enableNextWordPrediction";
NSString *ENABLE_LEFT_SHIFT_MODE_SWITCH_KEY = @"enableLeftShiftModeSwitch";
NSString *ENABLE_RIGHT_SHIFT_MODE_SWITCH_KEY = @"enableRightShiftModeSwitch";
NSString *ENABLE_LEFT_COMMAND_PINYIN_SWITCH_KEY = @"enableLeftCommandPinyinSwitch";
NSString *ENABLE_RIGHT_COMMAND_PINYIN_SWITCH_KEY = @"enableRightCommandPinyinSwitch";
static NSString *const CANDIDATE_PANEL_LAYOUT_KEY = @"candidatePanelLayout";
static NSString *const CANDIDATE_PANEL_LAYOUT_VERTICAL = @"vertical";
static NSString *const CANDIDATE_PANEL_LAYOUT_HORIZONTAL = @"horizontal";

static NSString *NormalizedCandidatePanelLayout(id layoutValue) {
    if ([layoutValue isKindOfClass:[NSString class]] && [layoutValue isEqualToString:CANDIDATE_PANEL_LAYOUT_HORIZONTAL]) {
        return CANDIDATE_PANEL_LAYOUT_HORIZONTAL;
    }
    return CANDIDATE_PANEL_LAYOUT_VERTICAL;
}

static IMKCandidatePanelType CandidatePanelTypeForLayout(NSString *layout) {
    if ([layout isEqualToString:CANDIDATE_PANEL_LAYOUT_HORIZONTAL]) {
        return kIMKSingleRowSteppingCandidatePanel;
    }
    return kIMKSingleColumnScrollingCandidatePanel;
}

static void ApplyCandidatePanelAttributes(void) {
    [sharedCandidates setAttributes:@{
        IMKCandidatesSendServerKeyEventFirst : @YES,
    }];
}

@interface WebServer ()

@property(nonatomic, strong) GCDWebServer *server;

@end

@implementation WebServer

static int port = 62718;

+ (instancetype)sharedServer {
    static WebServer *server = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        server = [[WebServer alloc] init];
    });
    return server;
}

- (void)start {
    if (self.server) {
        return;
    }

    GCDWebServer *webServer = [[GCDWebServer alloc] init];
    [webServer addGETHandlerForBasePath:@"/"
                          directoryPath:[NSString stringWithFormat:@"%@/%@", [NSBundle mainBundle].resourcePath, @"web"]
                          indexFilename:nil
                               cacheAge:3600
                     allowRangeRequests:YES];

    [webServer addHandlerForMethod:@"GET"
                              path:@"/preference"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          return [GCDWebServerDataResponse responseWithJSONObject:@{
                              TRANSLATION_KEY : @([preference boolForKey:TRANSLATION_KEY]),
                              COMMIT_WORD_WITH_SPACE_KEY : @([preference boolForKey:COMMIT_WORD_WITH_SPACE_KEY]),
                              ENABLE_NEXT_WORD_PREDICTION_KEY : @([preference boolForKey:ENABLE_NEXT_WORD_PREDICTION_KEY]),
                              ENABLE_LEFT_SHIFT_MODE_SWITCH_KEY : @([preference boolForKey:ENABLE_LEFT_SHIFT_MODE_SWITCH_KEY]),
                              ENABLE_RIGHT_SHIFT_MODE_SWITCH_KEY : @([preference boolForKey:ENABLE_RIGHT_SHIFT_MODE_SWITCH_KEY]),
                              ENABLE_LEFT_COMMAND_PINYIN_SWITCH_KEY : @([preference boolForKey:ENABLE_LEFT_COMMAND_PINYIN_SWITCH_KEY]),
                              ENABLE_RIGHT_COMMAND_PINYIN_SWITCH_KEY : @([preference boolForKey:ENABLE_RIGHT_COMMAND_PINYIN_SWITCH_KEY]),
                              CANDIDATE_PANEL_LAYOUT_KEY :
                                  NormalizedCandidatePanelLayout([preference stringForKey:CANDIDATE_PANEL_LAYOUT_KEY])
                          }];
                      }];

    [webServer addHandlerForMethod:@"POST"
                              path:@"/preference"
                      requestClass:[GCDWebServerDataRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSDictionary *data = ((GCDWebServerDataRequest *)request).jsonObject;
                          if (![data isKindOfClass:[NSDictionary class]]) {
                              return [GCDWebServerDataResponse responseWithJSONObject:@{@"ok" : @NO, @"error" : @"Invalid JSON"}];
                          }

                          bool showTranslation = [data[TRANSLATION_KEY] boolValue];
                          [preference setBool:showTranslation forKey:TRANSLATION_KEY];

                          bool commitWordWithSpace = [data[COMMIT_WORD_WITH_SPACE_KEY] boolValue];
                          [preference setBool:commitWordWithSpace forKey:COMMIT_WORD_WITH_SPACE_KEY];

                          bool enableNextWordPrediction = [data[ENABLE_NEXT_WORD_PREDICTION_KEY] boolValue];
                          [preference setBool:enableNextWordPrediction forKey:ENABLE_NEXT_WORD_PREDICTION_KEY];

                          bool enableLeftShiftModeSwitch = [data[ENABLE_LEFT_SHIFT_MODE_SWITCH_KEY] boolValue];
                          [preference setBool:enableLeftShiftModeSwitch forKey:ENABLE_LEFT_SHIFT_MODE_SWITCH_KEY];

                          bool enableRightShiftModeSwitch = [data[ENABLE_RIGHT_SHIFT_MODE_SWITCH_KEY] boolValue];
                          [preference setBool:enableRightShiftModeSwitch forKey:ENABLE_RIGHT_SHIFT_MODE_SWITCH_KEY];

                          bool enableLeftCommandPinyinSwitch = [data[ENABLE_LEFT_COMMAND_PINYIN_SWITCH_KEY] boolValue];
                          [preference setBool:enableLeftCommandPinyinSwitch forKey:ENABLE_LEFT_COMMAND_PINYIN_SWITCH_KEY];

                          bool enableRightCommandPinyinSwitch = [data[ENABLE_RIGHT_COMMAND_PINYIN_SWITCH_KEY] boolValue];
                          [preference setBool:enableRightCommandPinyinSwitch forKey:ENABLE_RIGHT_COMMAND_PINYIN_SWITCH_KEY];

                          NSString *candidatePanelLayout = NormalizedCandidatePanelLayout(data[CANDIDATE_PANEL_LAYOUT_KEY]);
                          [preference setObject:candidatePanelLayout forKey:CANDIDATE_PANEL_LAYOUT_KEY];
                          [sharedCandidates setPanelType:CandidatePanelTypeForLayout(candidatePanelLayout)];
                          ApplyCandidatePanelAttributes();

                          NSMutableDictionary *response = [data mutableCopy];
                          response[CANDIDATE_PANEL_LAYOUT_KEY] = candidatePanelLayout;
                          return [GCDWebServerDataResponse responseWithJSONObject:response];
                      }];

    [webServer addHandlerForMethod:@"GET"
                              path:@"/substitutions"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          return [GCDWebServerDataResponse responseWithJSONObject:[engine allSubstitutions]];
                      }];

    [webServer addHandlerForMethod:@"POST"
                              path:@"/substitutions"
                      requestClass:[GCDWebServerDataRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSDictionary *data = ((GCDWebServerDataRequest *)request).jsonObject;
                          NSString *key = data[@"key"];
                          NSString *value = data[@"value"];
                          if (key.length > 0 && value.length > 0) {
                              [engine addSubstitution:key value:value];
                          }
                          return [GCDWebServerDataResponse responseWithJSONObject:[engine allSubstitutions]];
                      }];

    [webServer addHandlerForMethod:@"DELETE"
                         pathRegex:@"/substitutions/(.+)"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSArray *captures = [request attributeForKey:GCDWebServerRequestAttribute_RegexCaptures];
                          NSString *key = captures.firstObject;
                          if (key.length > 0) {
                              [engine removeSubstitution:key];
                          }
                          return [GCDWebServerDataResponse responseWithJSONObject:[engine allSubstitutions]];
                      }];

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[GCDWebServerOption_Port] = @(port);
    options[GCDWebServerOption_BindToLocalhost] = @YES;

    NSError *error = nil;
    if (![webServer startWithOptions:options error:&error]) {
        NSLog(@"[YingHan] Failed to start preference server on port %d: %@", port, error.localizedDescription);
        return;
    }
    self.server = webServer;
}

@end
