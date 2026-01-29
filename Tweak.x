#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>

// --- CONFIG ---
#define kUUIDKey @"EnigmaSavedUUID"
#define kUDIDKey @"EnigmaSavedUDID"
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- STATE ---
static NSString *fakeUUID = nil;
static NSString *fakeUDID = nil;
static char *fakeModel = "iPhone18,1";
static BOOL isNetMonEnabled = NO; // Default OFF

// --- PERSISTENCE ---
void loadPrefs() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    fakeUUID = [d stringForKey:kUUIDKey];
    fakeUDID = [d stringForKey:kUDIDKey];
    if (!fakeUUID) fakeUUID = @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
    if (!fakeUDID) fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";
}

void savePrefs() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:fakeUUID forKey:kUUIDKey];
    [d setObject:fakeUDID forKey:kUDIDKey];
    [d synchronize];
}

// --- NETWORK LOGGER ENGINE ---
@interface EnigmaNetLogger : NSURLProtocol @end
@implementation EnigmaNetLogger

+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    // 1. If monitor is off, ignore everything
    if (!isNetMonEnabled) return NO;
    
    // 2. Prevent infinite loops (don't handle requests we already tagged)
    if ([NSURLProtocol propertyForKey:@"EnigmaHandled" inRequest:r]) return NO;
    
    // 3. Filter: Only log HTTP/HTTPS
    if (![r.URL.scheme hasPrefix:@"http"]) return NO;
    
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }

- (void)startLoading {
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"EnigmaHandled" inRequest:newReq];
    
    // --- SEND LOG TO UI ---
    NSString *log = [NSString stringWithFormat:@"[%@] %@", newReq.HTTPMethod, newReq.URL.absoluteString];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"EnigmaLog" object:log];
    
    // Pass request to real network engine
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session dataTaskWithRequest:newReq completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) [self.client URLProtocol:self didFailWithError:e];
        else {
            [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:d];
            [self.client URLProtocolDidFinishLoading:self];
        }
    }] resume];
}
- (void)stopLoading {}
@end

// --- UI IMPLEMENTATION ---
@interface EnigmaMenu : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIVisualEffectView *blurPanel;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UIView *termView;
@property (nonatomic, strong) UITextView *console;
@property (nonatomic, strong) UIButton *netBtn;
// ... (Identity & Inspector props omitted for brevity, they are same as before) ...
@end

@implementation EnigmaMenu
// ... (Standard Init & UI Setup Code from previous response) ...

// (Re-paste the UI setup code here, specifically the Terminal part:)
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLog:) name:@"EnigmaLog" object:nil];
    }
    return self;
}

- (void)setupUI {
    // FLOAT BTN
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 70, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
    self.floatBtn.layer.borderWidth = 1;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    // PANEL
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurPanel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurPanel.frame = CGRectMake(20, 160, self.frame.size.width - 40, 450);
    self.blurPanel.layer.cornerRadius = 18;
    self.blurPanel.hidden = YES;
    self.blurPanel.clipsToBounds = YES;
    [self addSubview:self.blurPanel];
    
    // TERMINAL VIEW
    self.termView = [[UIView alloc] initWithFrame:self.blurPanel.bounds];
    [self.blurPanel.contentView addSubview:self.termView];
    
    self.netBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.netBtn.frame = CGRectMake(15, 60, self.termView.frame.size.width - 30, 40);
    self.netBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    [self.netBtn setTitle:@"START NETWORK MONITOR" forState:UIControlStateNormal];
    [self.netBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [self.netBtn addTarget:self action:@selector(toggleNet) forControlEvents:UIControlEventTouchUpInside];
    [self.termView addSubview:self.netBtn];

    self.console = [[UITextView alloc] initWithFrame:CGRectMake(15, 110, self.termView.frame.size.width - 30, 320)];
    self.console.backgroundColor = [UIColor blackColor];
    self.console.textColor = THEME_COLOR;
    self.console.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.console.editable = NO;
    self.console.text = @"[SYSTEM] Ready.\n";
    [self.termView addSubview:self.console];
}

- (void)toggleMenu { self.blurPanel.hidden = !self.blurPanel.hidden; }

- (void)toggleNet {
    isNetMonEnabled = !isNetMonEnabled;
    if (isNetMonEnabled) {
        [self.netBtn setTitle:@"STOP MONITOR" forState:UIControlStateNormal];
        [self.netBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [self log:@"[*] Monitor ENABLED. Waiting for requests..."];
    } else {
        [self.netBtn setTitle:@"START NETWORK MONITOR" forState:UIControlStateNormal];
        [self.netBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [self log:@"[*] Monitor PAUSED."];
    }
}

- (void)handleLog:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.console.text = [self.console.text stringByAppendingFormat:@"%@\n", n.object];
        if (self.console.text.length > 0) {
            [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length - 1, 1)];
        }
    });
}
- (void)log:(NSString *)t { [self handleLog:[NSNotification notificationWithName:@"L" object:t]]; }
@end

// --- AGGRESSIVE NETWORKING HOOKS ---

// Hook 1: Force our logger class into every Session Configuration
%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSArray *originalProtocols = %orig;
    
    // If we haven't injected yet, add our class to the FRONT of the array
    if (![originalProtocols containsObject:[EnigmaNetLogger class]]) {
        NSMutableArray *newProtocols = [NSMutableArray arrayWithObject:[EnigmaNetLogger class]];
        [newProtocols addObjectsFromArray:originalProtocols];
        return newProtocols;
    }
    
    return originalProtocols;
}

%end

// --- STANDARD SPOOFING HOOKS ---
%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUUID]; }
%end

static CFPropertyListRef (*old_MGCopyAnswer)(CFStringRef);
CFPropertyListRef new_MGCopyAnswer(CFStringRef p) {
    if (CFStringCompare(p, CFSTR("UniqueDeviceID"), 0) == 0) return (__bridge CFPropertyListRef)fakeUDID;
    return old_MGCopyAnswer(p);
}

%ctor {
    loadPrefs();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (!w) {
            for (UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) {
                if (s.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *win in s.windows) if (win.isKeyWindow) { w = win; break; }
                }
            }
        }
        if (w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];

        void *mg = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (mg) MSHookFunction(mg, (void *)new_MGCopyAnswer, (void **)&old_MGCopyAnswer);
    });
    %init;
}
