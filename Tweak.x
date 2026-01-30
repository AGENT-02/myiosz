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
static BOOL isAntiBanEnabled = YES;
static BOOL isSSLBypassEnabled = NO; // Controlled by Switch #3
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- TELEGRAM UTILS ---
void sendText(NSString *text) {
    NSString *str = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                     TG_TOKEN, TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:str] completionHandler:nil] resume];
}

// --- LAYER 1: THE PROXY HIDER (Crucial for "Cut Connection") ---
// Instagram checks if you have a Proxy set. If yes, it kills the connection.
// We lie and say "No Proxy is running".

%hookf(CFDictionaryRef, CFNetworkCopySystemProxySettings) {
    if (isSSLBypassEnabled) {
        // Return an empty dictionary (No Proxy Configured)
        return (__bridge_retained CFDictionaryRef)@{@"HTTPEnable": @NO, @"HTTPSEnable": @NO};
    }
    return %orig;
}

// --- LAYER 2: THE "RESULT CODE" FIX (The Missing Link) ---
// Even if we say "YES" in Evaluate, the app checks the "Result Code" separately.
// We must force it to kSecTrustResultProceed (Safe).

%hookf(OSStatus, SecTrustGetTrustResult, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) {
            *result = kSecTrustResultProceed; // "Proceed, this is safe."
        }
        return errSecSuccess;
    }
    return %orig;
}

// --- LAYER 3: SYSTEM TRUST EVALUATION (The Standard Hook) ---

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) *result = kSecTrustResultProceed;
        return errSecSuccess;
    }
    return %orig;
}

%hookf(bool, SecTrustEvaluateWithError, SecTrustRef trust, CFErrorRef *error) {
    if (isSSLBypassEnabled) {
        if (error) *error = nil; // Delete the error
        return YES; // Force Success
    }
    return %orig;
}

// --- LAYER 4: PREVENT CUSTOM ANCHORS ---
// Prevents the app from saying "Only trust THESE 3 specific Meta certs".
// We disable the ability to set custom anchors.

%hookf(OSStatus, SecTrustSetAnchorCertificates, SecTrustRef trust, CFArrayRef anchorCertificates) {
    if (isSSLBypassEnabled) {
        return errSecSuccess; // Pretend we did it, but ignore the restrictive list.
    }
    return %orig;
}

%hookf(OSStatus, SecTrustSetAnchorCertificatesOnly, SecTrustRef trust, Boolean anchorCertificatesOnly) {
    if (isSSLBypassEnabled) {
        // Force it to look at System Root CAs (which includes our Sniffer Cert)
        return %orig(trust, false); 
    }
    return %orig;
}

// --- LAYER 5: APP-SPECIFIC CLASSES (The High Level) ---

// A. FBSSLPinningVerifier (Meta Shared)
%hook FBSSLPinningVerifier
- (void)checkPinning:(id)arg1 { if (isSSLBypassEnabled) return; %orig; }
- (void)checkPinning:(id)arg1 host:(id)arg2 { if (isSSLBypassEnabled) return; %orig; }
- (id)init { return %orig; }
%end

// B. IGSecurityPolicy (Instagram HTTP)
%hook IGSecurityPolicy
- (bool)validateServerTrust:(id)arg1 domain:(id)arg2 { return isSSLBypassEnabled ? YES : %orig; }
- (bool)validateServerTrust:(id)arg1 { return isSSLBypassEnabled ? YES : %orig; }
%end

// C. SRSecurityPolicy (WebSockets/Live/Chat)
%hook SRSecurityPolicy
- (BOOL)evaluateServerTrust:(id)arg1 forDomain:(id)arg2 { return isSSLBypassEnabled ? YES : %orig; }
- (BOOL)certificateChainValidationEnabled { return isSSLBypassEnabled ? NO : %orig; }
%end

// --- ANTI-BAN (Telemetry Blocker) ---
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

// --- UI: PIANO MENU ---
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

    // Menu Items
    [self addRow:0 t:@"زر التصوير السري" s:@"..." tag:1];
    [self addRow:65 t:@"مانع الإعلانات" s:@"..." tag:2];
    
    // THE MASTER SWITCH
    [self addRow:130 t:@"تخطي الحماية (SSL Bypass)" s:@"System + Socket + Proxy Hider" tag:3];
    
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

%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUDID]; }
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[PianoMenu alloc] initWithFrame:w.bounds]];
    });
}
