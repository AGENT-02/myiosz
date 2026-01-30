#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <dlfcn.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- STATE VARIABLES ---
static BOOL isSSLBypassEnabled = NO;
static BOOL isAntiBanEnabled = YES;
static NSString *fakeUDID = nil;

// --- C-LEVEL FUNCTION POINTERS (for BoringSSL/OpenSSL) ---
static int (*original_SSL_set_verify)(void *ssl, int mode, void *callback) = NULL;
static int (*original_SSL_CTX_set_verify)(void *ctx, int mode, void *callback) = NULL;
static long (*original_SSL_CTX_set_options)(void *ctx, long options) = NULL;
static long (*original_SSL_set_options)(void *ssl, long options) = NULL;

// --- HELPER ---
void sendText(NSString *text) {
    @try {
        NSString *escapedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                               TG_TOKEN, TG_CHAT_ID, escapedText];
        
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request 
                                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"[Piano] Telegram send failed: %@", error.localizedDescription);
            }
        }];
        [task resume];
    } @catch (NSException *exception) {
        NSLog(@"[Piano] sendText exception: %@", exception);
    }
}

// =========================================================
// SECTION 1: C-LEVEL BORINGSSL/OPENSSL HOOKS (CRITICAL!)
// =========================================================
// This is what Instagram's FBLiger/C++ network stack uses

// Hooked SSL_set_verify - Disables certificate verification at SSL level
int hooked_SSL_set_verify(void *ssl, int mode, void *callback) {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 C-Level: SSL_set_verify bypassed (mode=%d)", mode);
        // Set mode to SSL_VERIFY_NONE (0) - don't verify anything
        return original_SSL_set_verify(ssl, 0, NULL);
    }
    return original_SSL_set_verify(ssl, mode, callback);
}

// Hooked SSL_CTX_set_verify - Context-level verification bypass
int hooked_SSL_CTX_set_verify(void *ctx, int mode, void *callback) {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 C-Level: SSL_CTX_set_verify bypassed (mode=%d)", mode);
        return original_SSL_CTX_set_verify(ctx, 0, NULL);
    }
    return original_SSL_CTX_set_verify(ctx, mode, callback);
}

// Hooked SSL_CTX_set_options - Disable strict SSL options
long hooked_SSL_CTX_set_options(void *ctx, long options) {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 C-Level: SSL_CTX_set_options bypassed");
        // Remove strict SSL flags
        options &= ~0x00000004; // SSL_OP_NO_SSLv2
        options &= ~0x02000000; // SSL_OP_NO_SSLv3
    }
    return original_SSL_CTX_set_options(ctx, options);
}

// Hooked SSL_set_options
long hooked_SSL_set_options(void *ssl, long options) {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 C-Level: SSL_set_options bypassed");
    }
    return original_SSL_set_options(ssl, options);
}

// Initialize C-level hooks
void initializeBoringSSLHooks() {
    @autoreleasepool {
        // Try multiple library names (BoringSSL, OpenSSL, libssl)
        NSArray *possibleLibs = @[
            @"libboringssl.dylib",
            @"libssl.dylib", 
            @"libssl.1.0.0.dylib",
            @"libssl.1.1.dylib"
        ];
        
        void *sslHandle = NULL;
        
        // Find which SSL library is loaded
        for (NSString *libName in possibleLibs) {
            sslHandle = dlopen([libName UTF8String], RTLD_LAZY);
            if (sslHandle) {
                NSLog(@"[Piano] ✅ Found SSL library: %@", libName);
                break;
            }
        }
        
        // If no library found by name, try to find it in loaded images
        if (!sslHandle) {
            uint32_t imageCount = _dyld_image_count();
            for (uint32_t i = 0; i < imageCount; i++) {
                const char *imageName = _dyld_get_image_name(i);
                if (imageName && (strstr(imageName, "libssl") || strstr(imageName, "boringssl"))) {
                    sslHandle = dlopen(imageName, RTLD_LAZY | RTLD_NOLOAD);
                    if (sslHandle) {
                        NSLog(@"[Piano] ✅ Found SSL library in images: %s", imageName);
                        break;
                    }
                }
            }
        }
        
        if (sslHandle) {
            // Hook SSL_set_verify
            original_SSL_set_verify = (int (*)(void *, int, void *))dlsym(sslHandle, "SSL_set_verify");
            if (original_SSL_set_verify) {
                MSHookFunction((void *)original_SSL_set_verify, (void *)hooked_SSL_set_verify, (void **)&original_SSL_set_verify);
                NSLog(@"[Piano] ✅ Hooked SSL_set_verify");
            }
            
            // Hook SSL_CTX_set_verify
            original_SSL_CTX_set_verify = (int (*)(void *, int, void *))dlsym(sslHandle, "SSL_CTX_set_verify");
            if (original_SSL_CTX_set_verify) {
                MSHookFunction((void *)original_SSL_CTX_set_verify, (void *)hooked_SSL_CTX_set_verify, (void **)&original_SSL_CTX_set_verify);
                NSLog(@"[Piano] ✅ Hooked SSL_CTX_set_verify");
            }
            
            // Hook SSL_CTX_set_options
            original_SSL_CTX_set_options = (long (*)(void *, long))dlsym(sslHandle, "SSL_CTX_set_options");
            if (original_SSL_CTX_set_options) {
                MSHookFunction((void *)original_SSL_CTX_set_options, (void *)hooked_SSL_CTX_set_options, (void **)&original_SSL_CTX_set_options);
                NSLog(@"[Piano] ✅ Hooked SSL_CTX_set_options");
            }
            
            // Hook SSL_set_options
            original_SSL_set_options = (long (*)(void *, long))dlsym(sslHandle, "SSL_set_options");
            if (original_SSL_set_options) {
                MSHookFunction((void *)original_SSL_set_options, (void *)hooked_SSL_set_options, (void **)&original_SSL_set_options);
                NSLog(@"[Piano] ✅ Hooked SSL_set_options");
            }
        } else {
            NSLog(@"[Piano] ⚠️ Could not find SSL library - C-level hooks not installed");
        }
    }
}

// =========================================================
// SECTION 2: OBJECTIVE-C LEVEL HOOKS (For UIKit/React Native traffic)
// =========================================================

%hook IGNetworkSSLPinningIgnorer

- (BOOL)shouldValidateCertificate:(id)certificate {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 ObjC: IGNetworkSSLPinningIgnorer certificate validation bypassed");
        return NO;
    }
    return %orig;
}

- (void)URLSession:(NSURLSession *)session 
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 ObjC: IGNetworkSSLPinningIgnorer SSL challenge bypassed");
        NSURLCredential *credential = [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust];
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        }
        return;
    }
    %orig;
}

%end

%hook IGSecurityPolicy

- (BOOL)shouldValidateCertificate:(id)certificate {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 ObjC: IGSecurityPolicy certificate validation bypassed");
        return NO;
    }
    return %orig;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 ObjC: IGSecurityPolicy server trust bypassed for domain: %@", domain);
        return YES;
    }
    return %orig;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust {
    if (isSSLBypassEnabled) {
        return YES;
    }
    return %orig;
}

%end

// =========================================================
// SECTION 3: SYSTEM-LEVEL SECURITY BYPASSES
// =========================================================

// FIXED: Return empty dictionary instead of explicit @NO values
%hookf(CFDictionaryRef, CFNetworkCopySystemProxySettings) {
    if (isSSLBypassEnabled) {
        NSLog(@"[Piano] 🔓 Proxy settings bypassed - returning empty dict");
        // Empty dictionary = "No proxy configured"
        return (__bridge_retained CFDictionaryRef)@{};
    }
    return %orig;
}

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *result) {
    if (isSSLBypassEnabled) {
        if (result) {
            *result = kSecTrustResultProceed;
        }
        NSLog(@"[Piano] 🔓 SecTrustEvaluate bypassed");
        return errSecSuccess;
    }
    return %orig;
}

%hookf(bool, SecTrustEvaluateWithError, SecTrustRef trust, CFErrorRef *error) {
    if (isSSLBypassEnabled) {
        if (error) {
            *error = NULL;
        }
        NSLog(@"[Piano] 🔓 SecTrustEvaluateWithError bypassed");
        return true;
    }
    return %orig;
}

// =========================================================
// SECTION 4: ANTI-BAN & PRIVACY PROTECTION (FIXED)
// =========================================================

%hook NSURLSession

// FIXED: Return fake success response instead of canceling
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                             completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        
        NSArray *blockedKeywords = @[@"/report", @"/logging", @"/analytics", 
                                     @"/graphql", @"graph.facebook", @"graph.instagram",
                                     @"/falco", @"/rupload", @"/qe_sync"];
        
        for (NSString *keyword in blockedKeywords) {
            if ([url containsString:keyword]) {
                NSLog(@"[Piano] 🚫 Blocked analytics request: %@", url);
                
                // Create a fake successful response
                NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] 
                    initWithURL:request.URL 
                    statusCode:200 
                    HTTPVersion:@"HTTP/1.1" 
                    headerFields:@{@"Content-Type": @"application/json"}];
                
                // Fake success data
                NSData *fakeData = [@"{\"status\":\"ok\"}" dataUsingEncoding:NSUTF8StringEncoding];
                
                // Call completion handler with fake success
                if (completionHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(fakeData, fakeResponse, nil);
                    });
                }
                
                // Return a dummy task (won't be used since we already called completion)
                return [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:@"about:blank"]];
            }
        }
    }
    
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url 
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    if (isAntiBanEnabled) {
        NSString *urlString = url.absoluteString.lowercaseString;
        
        NSArray *blockedKeywords = @[@"/report", @"/logging", @"/analytics", 
                                     @"/graphql", @"graph.facebook", @"graph.instagram"];
        
        for (NSString *keyword in blockedKeywords) {
            if ([urlString containsString:keyword]) {
                NSLog(@"[Piano] 🚫 Blocked analytics URL: %@", urlString);
                
                NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] 
                    initWithURL:url 
                    statusCode:200 
                    HTTPVersion:@"HTTP/1.1" 
                    headerFields:@{@"Content-Type": @"application/json"}];
                
                NSData *fakeData = [@"{\"status\":\"ok\"}" dataUsingEncoding:NSUTF8StringEncoding];
                
                if (completionHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(fakeData, fakeResponse, nil);
                    });
                }
                
                return [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:@"about:blank"]];
            }
        }
    }
    
    return %orig;
}

%end

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (fakeUDID) {
        return [[NSUUID alloc] initWithUUIDString:fakeUDID];
    }
    return %orig;
}

%end

// =========================================================
// SECTION 5: UI MENU
// =========================================================

@interface PianoMenu : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, assign) CGPoint lastTouchPoint;
@end

@implementation PianoMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupUI];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.floatBtn || [hit isDescendantOfView:self.panel]) {
        return hit;
    }
    return nil;
}

- (void)setupUI {
    CGFloat screenWidth = self.frame.size.width;
    CGFloat screenHeight = self.frame.size.height;
    
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(screenWidth - 70, 150, 50, 50);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    self.floatBtn.layer.borderWidth = 2;
    self.floatBtn.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.floatBtn.layer.shadowOffset = CGSizeMake(0, 0);
    self.floatBtn.layer.shadowRadius = 8;
    self.floatBtn.layer.shadowOpacity = 0.6;
    [self.floatBtn setTitle:@"🎹" forState:UIControlStateNormal];
    self.floatBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.floatBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatBtn addGestureRecognizer:pan];
    
    [self addSubview:self.floatBtn];

    CGFloat panelWidth = MIN(340, screenWidth - 40);
    CGFloat panelHeight = MIN(560, screenHeight - 100);
    
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screenWidth - panelWidth)/2, 
                                                          (screenHeight - panelHeight)/2, 
                                                          panelWidth, 
                                                          panelHeight)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    self.panel.layer.cornerRadius = 20;
    self.panel.layer.borderColor = [UIColor cyanColor].CGColor;
    self.panel.layer.borderWidth = 2;
    self.panel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.panel.layer.shadowOffset = CGSizeMake(0, 4);
    self.panel.layer.shadowRadius = 12;
    self.panel.layer.shadowOpacity = 0.5;
    self.panel.hidden = YES;
    [self addSubview:self.panel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panelWidth, 40)];
    titleLabel.text = @"🎹 بيانو";
    titleLabel.textColor = [UIColor cyanColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:28];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:titleLabel];
    
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, panelWidth, 20)];
    versionLabel.text = @"v3.0 - C-Level Hooks + iOS 26.0";
    versionLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    versionLabel.font = [UIFont systemFontOfSize:11];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:versionLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(panelWidth - 45, 15, 35, 35);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [closeBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:closeBtn];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 95, panelWidth - 20, panelHeight - 105)];
    self.scroll.showsVerticalScrollIndicator = YES;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.panel addSubview:self.scroll];

    [self addRow:0 t:@"تخطي حماية SSL" s:@"BoringSSL C-Level Bypass" tag:3];
    [self addRow:75 t:@"حماية كلاود (Anti-Ban)" s:@"Anti-Tracking Protection" tag:4];
    [self addRow:150 t:@"UDID وهمي" s:@"Randomized UDID" tag:5 info:fakeUDID];
    
    self.scroll.contentSize = CGSizeMake(panelWidth - 20, 250);
}

- (void)addRow:(CGFloat)y t:(NSString*)title s:(NSString*)subtitle tag:(int)tag {
    [self addRow:y t:title s:subtitle tag:tag info:nil];
}

- (void)addRow:(CGFloat)y t:(NSString*)title s:(NSString*)subtitle tag:(int)tag info:(NSString*)info {
    CGFloat rowWidth = self.scroll.frame.size.width;
    
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, rowWidth, 65)];
    row.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    row.layer.cornerRadius = 12;
    row.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    row.layer.borderWidth = 1;
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(15, 17, 51, 31)];
    sw.onTintColor = [UIColor cyanColor];
    sw.tag = tag;
    
    if (tag == 3) sw.on = isSSLBypassEnabled;
    if (tag == 4) sw.on = isAntiBanEnabled;
    if (tag == 5) sw.enabled = NO;
    
    [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(75, 12, rowWidth - 85, 22)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentRight;
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [row addSubview:titleLabel];
    
    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(75, 34, rowWidth - 85, 18)];
    subtitleLabel.text = info ? info : subtitle;
    subtitleLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    subtitleLabel.textAlignment = NSTextAlignmentRight;
    subtitleLabel.font = [UIFont systemFontOfSize:11];
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.adjustsFontSizeToFitWidth = YES;
    subtitleLabel.minimumScaleFactor = 0.7;
    [row addSubview:subtitleLabel];
    
    [self.scroll addSubview:row];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint newCenter = CGPointMake(self.floatBtn.center.x + translation.x, 
                                   self.floatBtn.center.y + translation.y);
    
    CGFloat margin = 25;
    newCenter.x = MAX(margin, MIN(self.frame.size.width - margin, newCenter.x));
    newCenter.y = MAX(margin, MIN(self.frame.size.height - margin, newCenter.y));
    
    self.floatBtn.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self];
}

- (void)toggle {
    self.panel.hidden = !self.panel.hidden;
    
    if (!self.panel.hidden) {
        self.panel.alpha = 0;
        self.panel.transform = CGAffineTransformMakeScale(0.8, 0.8);
        
        [UIView animateWithDuration:0.3 
                              delay:0 
             usingSpringWithDamping:0.7 
              initialSpringVelocity:0.5 
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:^{
            self.panel.alpha = 1;
            self.panel.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)switchToggled:(UISwitch*)sender {
    switch (sender.tag) {
        case 3:
            isSSLBypassEnabled = sender.on;
            NSLog(@"[Piano] SSL Bypass toggled: %d", sender.on);
            sendText(sender.on ? 
                    @"🔓 SSL Bypass ENABLED (C-Level + ObjC)\n⚠️ RESTART APP!" : 
                    @"🔒 SSL Bypass DISABLED");
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:sender.on ? @"⚠️ SSL Bypass ON" : @"✅ SSL Restored"
                                                                              message:sender.on ? @"BoringSSL C-Level hooks active.\nRESTART the app!" : @"SSL validation enabled."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                
                UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                while (rootVC.presentedViewController) {
                    rootVC = rootVC.presentedViewController;
                }
                [rootVC presentViewController:alert animated:YES completion:nil];
            });
            break;
            
        case 4:
            isAntiBanEnabled = sender.on;
            NSLog(@"[Piano] Anti-Ban toggled: %d", sender.on);
            sendText(sender.on ? @"🛡️ Anti-Ban ON" : @"⚠️ Anti-Ban OFF");
            break;
    }
}

@end

// =========================================================
// CONSTRUCTOR
// =========================================================

%ctor {
    @autoreleasepool {
        // Generate random UDID
        if (!fakeUDID) {
            fakeUDID = [[NSUUID UUID] UUIDString];
            NSLog(@"[Piano] Generated UDID: %@", fakeUDID);
        }
        
        // Initialize C-level hooks IMMEDIATELY
        initializeBoringSSLHooks();
        
        // Initialize UI after 3 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), 
                      dispatch_get_main_queue(), ^{
            @try {
                UIWindow *keyWindow = nil;
                
                if (@available(iOS 13.0, *)) {
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            for (UIWindow *window in scene.windows) {
                                if (window.isKeyWindow) {
                                    keyWindow = window;
                                    break;
                                }
                            }
                        }
                    }
                }
                
                if (!keyWindow) {
                    keyWindow = [UIApplication sharedApplication].keyWindow;
                }
                
                if (keyWindow) {
                    PianoMenu *menu = [[PianoMenu alloc] initWithFrame:keyWindow.bounds];
                    [keyWindow addSubview:menu];
                    NSLog(@"[Piano] ✅ Menu ready");
                    sendText(@"🎹 Piano v3.0 Loaded\n✅ C-Level BoringSSL Hooks Active\n📱 iOS 26.0");
                } else {
                    NSLog(@"[Piano] ⚠️ No key window");
                }
            } @catch (NSException *exception) {
                NSLog(@"[Piano] ❌ Init error: %@", exception);
            }
        });
    }
}
