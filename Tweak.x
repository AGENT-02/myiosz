#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- TELEGRAM ENGINE (SURVIVAL MODE) ---
void sendToTelegram(NSString *text) {
    // Request background time to survive the app crash
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TG_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    
    // Telegram has a 4096 character limit, so we truncate if needed
    if (text.length > 4000) {
        text = [text substringToIndex:4000];
        text = [text stringByAppendingString:@"\n[TRUNCATED DUE TO SIZE]"];
    }

    NSString *body = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                     TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        // End the background task once sent
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }] resume];
}

// --- CLASS DUMPER ---
void dumpAndSendClasses() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    
    NSMutableString *dump = [NSMutableString stringWithFormat:@"🚨 PANIC DUMP (%u Classes) 🚨\n\n", count];
    
    // We prioritize classes starting with 'SC' (Snapchat) to get the useful ones first
    int found = 0;
    for (int i = 0; i < count; i++) {
        const char *cname = class_getName(classes[i]);
        NSString *name = [NSString stringWithUTF8String:cname];
        
        // Filter: Only grab relevant classes to save time/bandwidth
        if ([name hasPrefix:@"SC"] || [name hasPrefix:@"LS"] || [name containsString:@"Login"]) {
            [dump appendFormat:@"%@\n", name];
            found++;
            
            // Limit to ~100 classes per message to ensure speed
            if (found >= 100) break; 
        }
    }
    free(classes);
    
    if (found == 0) [dump appendString:@"[!] No 'SC' classes found (System libraries only?)."];
    
    sendToTelegram(dump);
}

// --- MENU UI ---
@interface EnigmaMenu : UIView
@property (nonatomic, strong) UIButton *floatBtn;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 1. EXECUTE IMMEDIATELY (No delays, no waiting)
        dumpAndSendClasses();
        
        // 2. Setup UI
        self.userInteractionEnabled = YES;
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 100, 50, 50);
        self.floatBtn.backgroundColor = [UIColor blackColor];
        self.floatBtn.layer.cornerRadius = 25;
        self.floatBtn.layer.borderWidth = 2;
        self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
        [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
        [self addSubview:self.floatBtn];
    }
    return self;
}
@end

// --- INJECTOR ---
%ctor {
    // We hook the Window creation to inject as early as possible without breaking the launch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
    });
}
