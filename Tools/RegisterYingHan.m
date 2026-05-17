#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *bundlePath = argc > 1
            ? [NSString stringWithUTF8String:argv[1]]
            : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Input Methods/YingHan.app"];
        NSString *sourceID = @"com.jinboli.inputmethod.yinghan";

        OSStatus registerStatus = TISRegisterInputSource((__bridge CFURLRef)[NSURL fileURLWithPath:bundlePath]);
        printf("TISRegisterInputSource status: %d\n", registerStatus);

        CFArrayRef list = TISCreateInputSourceList(NULL, true);
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex index = 0; index < count; index++) {
            TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, index);
            NSString *currentSourceID = (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
            if ([currentSourceID isEqualToString:sourceID]) {
                printf("Found source: %s\n", [sourceID UTF8String]);
                printf("TISEnableInputSource status: %d\n", TISEnableInputSource(source));
                printf("TISSelectInputSource status: %d\n", TISSelectInputSource(source));
            }
        }
        CFRelease(list);
    }
    return 0;
}
