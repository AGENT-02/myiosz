#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- STATE VARIABLES ---
static BOOL isSSLBypassEnabled = NO; // Controlled by Switch #3
static BOOL isAntiBanEnabled = YES;  // Controlled by Switch #4
static NSString *fakeUDID = nil;

// --- TELEGRAM HELPER ---
void sendText(NSString *text) {
    @try {
        NSString *escapedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", TG_TOKEN, TG_CHAT_ID, escapedText];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:nil] resume];
    } @catch (NSException *e) { NSLog(@"[Enigma] Send Error: %@", e); }
}

// =========================================================
// SECTION 1: THE "DEVELOPER MODE" BYPASS (Internal Class)
// =========================================================
// This uses the class YOU found to force the app into "Debug Mode"
[cite_start]// where it accepts any certificate[cite: 1].

%hook IGNetworkSSLPinningIgnorer

// Force the app to say "Do NOT validate certificates"
- (BOOL)shouldValidateCertificate:(id)arg1 {
    if (isSSLBypassEnabled) return NO;
    return %orig;
}

// The "Magic" method that accepts the proxy's certificate
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if (isSSLBypassEnabled) {
        // Create a credential from the server's trust (accepting Egern/Reqable)
        NSURLCredential *credential = [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust];
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        }
        return;
    }
    %orig;
}
%end

// =========================================================
// SECTION 2: THE SECURITY POLICY OVERRIDE
// =========================================================
[cite_start]// We apply the same logic to the main security policy class[cite: 2].

%hook IGSecurityPolicy

- (BOOL)shouldValidateCertificate:(id)arg1 {
    return isSSLBypassEnabled ? NO : %orig;
}

- (bool)validateServerTrust:(id)arg1 domain:(id)arg2 { 
    return isSSLBypassEnabled ? YES : %orig; 
}

- (bool)validateServerTrust:(id)arg1 { 
    return isSSLBypassEnabled ? YES : %orig; 
}

%end

// =========================================================
// SECTION 3: SYSTEM PROXY HIDER (Prevents "No Connection")
// =========================================================
// This makes the app think you are NOT using a proxy, preventing it
[cite_start]// from cutting the connection when it detects Egern/Reqable[cite: 2].

%hookf(CFDictionaryRef, CFNetworkCopySystemProxySettings) {
    if (isSSLBypassEnabled) {
        // Return Empty Dictionary = "No Proxy Configured"
        return (__bridge_retained CFDictionaryRef)@{};
    }
    return %orig;
}

// Force System Trust to "Proceed"
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}

// The Modern Check
%hookf(bool, SecTrustEvaluateWithError, SecTrustRef trust, CFErrorRef *error) {
    if (isSSLBypassEnabled) {
        if (error) *error = nil;
        return YES;
    }
    return %orig;
}

// =========================================================
// SECTION 4: ANTI-BAN (Telemetry Blocker)
// =========================================================
[cite_start]// Silently drops analytics requests[cite: 2].

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completion {
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        if ([url containsString:@"report"] || [url containsString:@"analytics"] || 
            [url containsString:@"logging"] || [url containsString:@"graph.facebook"]) {
            
            // Silently fail the request
            if (completion) {
                void (^handler)(NSData*, NSURLResponse*, NSError*) = completion;
                handler(nil, nil, [NSError errorWithDomain:@"Blocked" code:403 userInfo:nil]);
            }
            return nil; 
        }
    }
    return %orig;
}
%end

// =========================================================
// SECTION 5: UI MENU (Fixed Switch Error)
// =========================================================

@interface PianoMenu : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIScrollView *scroll;
@end

@implementation PianoMenu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.userInteractionEnabled = YES; [self setupUI]; }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.floatBtn || [hit isDescendantOfView:self.panel]) return hit;
    return nil;
}
- (void)setupUI {
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 150, 45, 45);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 22.5;
    self.floatBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    self.floatBtn.layer.borderWidth = 1;
    [self.floatBtn setTitle:@"🎹" forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake((self.frame.size.width - 320)/2, 100, 320, 520)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    self.panel.layer.cornerRadius = 15;
    self.panel.layer.borderColor = [UIColor cyanColor].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.hidden = YES;
    [self addSubview:self.panel];
    
    // Add Scroll View
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 60, 320, 450)];
    [self.panel addSubview:self.scroll];

    [self addRow:0 t:@"مانع الإعلانات" tag:2];
    [self addRow:65 t:@"تخطي الحماية (Developer Mode)" tag:3];
    [self addRow:130 t:@"حماية كلاود (Anti-Ban)" tag:4];
}
- (void)addRow:(CGFloat)y t:(NSString*)t tag:(int)tag {
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(10, y, 300, 55)];
    r.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    r.layer.cornerRadius = 10;
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(15, 12, 50, 30)];
    sw.onTintColor = [UIColor cyanColor];
    sw.tag = tag;
    if (tag==4) sw.on = YES;
    [sw addTarget:self action:@selector(sw:) forControlEvents:UIControlEventValueChanged];
    [r addSubview:sw];
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(70, 18, 220, 20)];
    tl.text = t; tl.textColor = [UIColor whiteColor]; tl.textAlignment = NSTextAlignmentRight; 
    [r addSubview:tl];
    [self.scroll addSubview:r];
}
- (void)toggle { self.panel.hidden = !self.panel.hidden; }

// --- FIXED METHOD: Added Braces to Case 3 ---
- (void)sw:(UISwitch*)s { 
    switch (s.tag) {
        case 3: { // <--- Added Brace
            isSSLBypassEnabled = s.on;
            sendText(s.on ? @"🔓 SSL Bypass ENABLED. RESTART APP!" : @"🔒 SSL Bypass DISABLED");
            break;
        } // <--- Added Brace
        case 4:
            isAntiBanEnabled = s.on;
            break;
    }
}
@end

%ctor {
    // 1. Initialize UDID
    if (!fakeUDID) fakeUDID = [[NSUUID UUID] UUIDString];

    // 2. UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[PianoMenu alloc] initWithFrame:w.bounds]];
    });
}
