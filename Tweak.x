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
static BOOL isSSLBypassEnabled = NO; // Controlled by Switch #3
static BOOL isAntiBanEnabled = YES;
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- TELEGRAM HELPER ---
void sendText(NSString *text) {
    NSString *str = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                     TG_TOKEN, TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:str] completionHandler:nil] resume];
}

// =========================================================
//  SECTION 1: THE "INTERNET" BYPASS (BORINGSSL / FBLIGER)
//  This hooks the C-level SSL functions used by Instagram's
//  custom network stack (Tigon/Proxygen).
// =========================================================

// Definition of the verify callback: always return 1 (OK)
int CustomVerifyCallback(int ok, void *ctx) {
    return 1; // 1 = Success, 0 = Fail
}

// Function Pointers for Original Methods
void (*orig_SSL_set_verify)(void *ssl, int mode, void *callback);
void (*orig_SSL_CTX_set_verify)(void *ctx, int mode, void *callback);
void (*orig_SSL_set_custom_verify)(void *ssl, int mode, void *callback);
void (*orig_SSL_CTX_set_custom_verify)(void *ctx, int mode, void *callback);

// Hook: SSL_set_verify
// We force mode = 0 (SSL_VERIFY_NONE) and use our "Always True" callback.
void hook_SSL_set_verify(void *ssl, int mode, void *callback) {
    if (isSSLBypassEnabled) {
        orig_SSL_set_verify(ssl, 0, (void*)CustomVerifyCallback); 
    } else {
        orig_SSL_set_verify(ssl, mode, callback);
    }
}

// Hook: SSL_CTX_set_verify (The Context Global Setting)
void hook_SSL_CTX_set_verify(void *ctx, int mode, void *callback) {
    if (isSSLBypassEnabled) {
        orig_SSL_CTX_set_verify(ctx, 0, (void*)CustomVerifyCallback);
    } else {
        orig_SSL_CTX_set_verify(ctx, mode, callback);
    }
}

// Hook: SSL_set_custom_verify (Often used by Meta to override defaults)
void hook_SSL_set_custom_verify(void *ssl, int mode, void *callback) {
    if (isSSLBypassEnabled) {
        // Force NONE (0) and Success Callback
        orig_SSL_set_custom_verify(ssl, 0, (void*)CustomVerifyCallback);
    } else {
        orig_SSL_set_custom_verify(ssl, mode, callback);
    }
}

// Function to find and hook symbols dynamically
void HookBoringSSL() {
    // Try to find symbols in the main binary or loaded dylibs
    void *ssl_set_verify_ptr = dlsym(RTLD_DEFAULT, "SSL_set_verify");
    void *ssl_ctx_set_verify_ptr = dlsym(RTLD_DEFAULT, "SSL_CTX_set_verify");
    void *ssl_set_custom_verify_ptr = dlsym(RTLD_DEFAULT, "SSL_set_custom_verify");

    if (ssl_set_verify_ptr) {
        MSHookFunction(ssl_set_verify_ptr, (void *)hook_SSL_set_verify, (void **)&orig_SSL_set_verify);
        // NSLog(@"[ENIGMA] Hooked SSL_set_verify");
    }
    if (ssl_ctx_set_verify_ptr) {
        MSHookFunction(ssl_ctx_set_verify_ptr, (void *)hook_SSL_CTX_set_verify, (void **)&orig_SSL_CTX_set_verify);
        // NSLog(@"[ENIGMA] Hooked SSL_CTX_set_verify");
    }
    if (ssl_set_custom_verify_ptr) {
        MSHookFunction(ssl_set_custom_verify_ptr, (void *)hook_SSL_set_custom_verify, (void **)&orig_SSL_set_custom_verify);
        // NSLog(@"[ENIGMA] Hooked SSL_set_custom_verify");
    }
}


// =========================================================
//  SECTION 2: SYSTEM LEVEL BYPASS (SecTrust)
//  Handles standard validation and Proxy Checks
// =========================================================

// 1. Force Proxy Settings to "Empty" (Hides Egern/Reqable)
%hookf(CFDictionaryRef, CFNetworkCopySystemProxySettings) {
    if (isSSLBypassEnabled) {
        return (__bridge_retained CFDictionaryRef)@{(id)kCFNetworkProxiesHTTPEnable: @NO};
    }
    return %orig;
}

// 2. Force Trust Evaluation to "Proceed"
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}

%hookf(bool, SecTrustEvaluateWithError, SecTrustRef trust, CFErrorRef *error) {
    if (isSSLBypassEnabled) {
        if (error) *error = nil;
        return YES;
    }
    return %orig;
}

%hookf(OSStatus, SecTrustGetTrustResult, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}


// =========================================================
//  SECTION 3: APP LEVEL BYPASS (Objective-C Wrappers)
// =========================================================

%hook FBSSLPinningVerifier
- (void)checkPinning:(id)arg1 { if (isSSLBypassEnabled) return; %orig; }
- (void)checkPinning:(id)arg1 host:(id)arg2 { if (isSSLBypassEnabled) return; %orig; }
- (id)init { return %orig; }
%end

%hook IGSecurityPolicy
- (bool)validateServerTrust:(id)arg1 domain:(id)arg2 { return isSSLBypassEnabled ? YES : %orig; }
- (bool)validateServerTrust:(id)arg1 { return isSSLBypassEnabled ? YES : %orig; }
%end

// WebSocket / Live / Chat Bypass
%hook SRSecurityPolicy
- (BOOL)evaluateServerTrust:(id)arg1 forDomain:(id)arg2 { return isSSLBypassEnabled ? YES : %orig; }
- (BOOL)certificateChainValidationEnabled { return isSSLBypassEnabled ? NO : %orig; }
%end


// =========================================================
//  SECTION 4: MENU & UTILS
// =========================================================

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completion {
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        if ([url containsString:@"report"] || [url containsString:@"analytics"] || 
            [url containsString:@"logging"] || [url containsString:@"graph.facebook"]) {
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

%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUDID]; }
%end

// --- PIANO MENU IMPLEMENTATION ---
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

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, 320, 30)];
    lbl.text = @"بيانو";
    lbl.textColor = [UIColor cyanColor];
    lbl.font = [UIFont boldSystemFontOfSize:22];
    lbl.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:lbl];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 60, 320, 450)];
    [self.panel addSubview:self.scroll];

    [self addRow:0 t:@"زر التصوير السري" s:@"..." tag:1];
    [self addRow:65 t:@"مانع الإعلانات" s:@"..." tag:2];
    [self addRow:130 t:@"تخطي الحماية (System+BoringSSL)" s:@"تخطي FBLiger & Tigon" tag:3];
    [self addRow:195 t:@"حماية كلاود (Anti-Ban)" s:@"..." tag:4];
}
- (void)addRow:(CGFloat)y t:(NSString*)t s:(NSString*)s tag:(int)tag {
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(10, y, 300, 55)];
    r.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    r.layer.cornerRadius = 10;
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(15, 12, 50, 30)];
    sw.onTintColor = [UIColor cyanColor];
    sw.tag = tag;
    if (tag==4) sw.on = YES;
    [sw addTarget:self action:@selector(sw:) forControlEvents:UIControlEventValueChanged];
    [r addSubview:sw];
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(70, 8, 220, 20)];
    tl.text = t; tl.textColor = [UIColor whiteColor]; tl.textAlignment = NSTextAlignmentRight; tl.font = [UIFont boldSystemFontOfSize:14];
    [r addSubview:tl];
    [self.scroll addSubview:r];
}
- (void)toggle { self.panel.hidden = !self.panel.hidden; }
- (void)sw:(UISwitch*)s { 
    if (s.tag==3) {
        isSSLBypassEnabled = s.on;
        sendText(s.on ? @"🔓 SSL Bypass ENABLED. RESTART APP!" : @"🔒 SSL Bypass DISABLED");
    }
    if (s.tag==4) isAntiBanEnabled = s.on;
}
@end

%ctor {
    // 1. Initialize BoringSSL Hooks (The "Internet" Method)
    HookBoringSSL();

    // 2. Initialize Menu
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[PianoMenu alloc] initWithFrame:w.bounds]];
    });
}
