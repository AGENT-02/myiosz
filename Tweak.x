#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- STATE VARIABLES ---
static BOOL isSSLBypassEnabled = NO;
static BOOL isAntiBanEnabled = YES;
static NSString *fakeUDID = nil;

// --- HELPER ---
void sendText(NSString *text) {
    @try {
        NSString *escapedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", TG_TOKEN, TG_CHAT_ID, escapedText];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:nil] resume];
    } @catch (NSException *e) { NSLog(@"[Enigma] Send Error: %@", e); }
}

// =========================================================
// SECTION 1: C-LEVEL BORINGSSL BYPASS (REQUIRED FOR IG)
// =========================================================
// This hooks the C++ network stack (FBLiger) that ignores Obj-C hooks.

int CustomVerifyCallback(int ok, void *ctx) { return 1; } // Always Success

void (*orig_SSL_set_verify)(void *ssl, int mode, void *callback);
void (*orig_SSL_CTX_set_verify)(void *ctx, int mode, void *callback);
void (*orig_SSL_set_custom_verify)(void *ssl, int mode, void *callback);

void hook_SSL_set_verify(void *ssl, int mode, void *callback) {
    if (isSSLBypassEnabled) orig_SSL_set_verify(ssl, 0, (void*)CustomVerifyCallback);
    else orig_SSL_set_verify(ssl, mode, callback);
}

void hook_SSL_CTX_set_verify(void *ctx, int mode, void *callback) {
    if (isSSLBypassEnabled) orig_SSL_CTX_set_verify(ctx, 0, (void*)CustomVerifyCallback);
    else orig_SSL_CTX_set_verify(ctx, mode, callback);
}

void hook_SSL_set_custom_verify(void *ssl, int mode, void *callback) {
    if (isSSLBypassEnabled) orig_SSL_set_custom_verify(ssl, 0, (void*)CustomVerifyCallback);
    else orig_SSL_set_custom_verify(ssl, mode, callback);
}

void HookBoringSSL() {
    void *p1 = dlsym(RTLD_DEFAULT, "SSL_set_verify");
    void *p2 = dlsym(RTLD_DEFAULT, "SSL_CTX_set_verify");
    void *p3 = dlsym(RTLD_DEFAULT, "SSL_set_custom_verify");
    if(p1) MSHookFunction(p1, (void *)hook_SSL_set_verify, (void **)&orig_SSL_set_verify);
    if(p2) MSHookFunction(p2, (void *)hook_SSL_CTX_set_verify, (void **)&orig_SSL_CTX_set_verify);
    if(p3) MSHookFunction(p3, (void *)hook_SSL_set_custom_verify, (void **)&orig_SSL_set_custom_verify);
}

// =========================================================
// SECTION 2: SYSTEM LEVEL BYPASS (PROXY + TRUST)
// =========================================================

// Fix: Return EMPTY dictionary to fully hide proxy
%hookf(CFDictionaryRef, CFNetworkCopySystemProxySettings) {
    if (isSSLBypassEnabled) return (__bridge_retained CFDictionaryRef)@{};
    return %orig;
}

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}

// Fix: Handle the Result Code check explicitly
%hookf(OSStatus, SecTrustGetTrustResult, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}

// =========================================================
// SECTION 3: APP LEVEL HOOKS (YOUR DISCOVERY)
// =========================================================

%hook IGNetworkSSLPinningIgnorer
- (BOOL)shouldValidateCertificate:(id)cert { return isSSLBypassEnabled ? NO : %orig; }
- (void)URLSession:(NSURLSession *)s didReceiveChallenge:(NSURLAuthenticationChallenge *)c completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completion {
    if (isSSLBypassEnabled && completion) {
        completion(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc] initWithTrust:c.protectionSpace.serverTrust]);
    } else { %orig; }
}
%end

%hook IGSecurityPolicy
- (BOOL)shouldValidateCertificate:(id)cert { return isSSLBypassEnabled ? NO : %orig; }
- (BOOL)validateServerTrust:(id)t domain:(id)d { return isSSLBypassEnabled ? YES : %orig; }
- (BOOL)validateServerTrust:(id)t { return isSSLBypassEnabled ? YES : %orig; }
%end

// =========================================================
// SECTION 4: ANTI-BAN (SILENT BLOCK)
// =========================================================

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completion {
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        if ([url containsString:@"report"] || [url containsString:@"analytics"] || 
            [url containsString:@"logging"] || [url containsString:@"graph.facebook"]) {
            
            // Fix: Don't cancel. Just silence it.
            if (completion) {
                void (^handler)(NSData*, NSURLResponse*, NSError*) = completion;
                // Return nil/error immediately to block the network call silently
                handler(nil, nil, [NSError errorWithDomain:@"Blocked" code:403 userInfo:nil]);
            }
            return nil; 
        }
    }
    return %orig;
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor { return fakeUDID ? [[NSUUID alloc] initWithUUIDString:fakeUDID] : %orig; }
%end

// =========================================================
// SECTION 5: UI MENU
// =========================================================
// Kept simple to avoid UI errors.
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
    [self addRow:65 t:@"تخطي الحماية (BoringSSL)" tag:3];
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

// --- FIXED METHOD: BRACES ADDED TO CASE 3 ---
- (void)sw:(UISwitch*)s { 
    switch (s.tag) {
        case 3: { // Added brace start
            isSSLBypassEnabled = s.on;
            sendText(s.on ? @"🔓 SSL Bypass ENABLED. RESTART APP!" : @"🔒 SSL Bypass DISABLED");
            dispatch_async(dispatch_get_main_queue(), ^{
               // Placeholder for alert if needed
            });
            break;
        } // Added brace end
        case 4:
            isAntiBanEnabled = s.on;
            break;
    }
}
@end

%ctor {
    // 1. Initialize C-Level Hooks Immediately
    HookBoringSSL();

    // 2. Initialize UDID
    if (!fakeUDID) fakeUDID = [[NSUUID UUID] UUIDString];

    // 3. UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[PianoMenu alloc] initWithFrame:w.bounds]];
    });
}
