#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>

// --- CONFIGURATION ---
#define kUUIDKey @"EnigmaSavedUUID"
#define kUDIDKey @"EnigmaSavedUDID"
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0] // Cyan

// --- GLOBAL STATE ---
static NSString *fakeUUID = nil;
static NSString *fakeUDID = nil;
static char *fakeModel = "iPhone18,1"; // iOS 26.2 Standard
static BOOL isNetMonEnabled = NO;

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
    if (!isNetMonEnabled) return NO;
    if ([NSURLProtocol propertyForKey:@"EnigmaHandled" inRequest:r]) return NO;
    if (![r.URL.scheme hasPrefix:@"http"]) return NO;
    return YES;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"EnigmaHandled" inRequest:newReq];
    
    // Log to UI
    NSString *log = [NSString stringWithFormat:@"[%@] %@", newReq.HTTPMethod, newReq.URL.absoluteString];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"EnigmaLog" object:log];
    
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

// --- MAIN UI CLASS ---
@interface EnigmaMenu : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
// Core UI
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIVisualEffectView *blurPanel;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UISegmentedControl *tabs;

// Tab 1: Identity
@property (nonatomic, strong) UIView *identityView;
@property (nonatomic, strong) UILabel *idInfoLabel;

// Tab 2: Inspector
@property (nonatomic, strong) UIView *inspectorView;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UITableView *classTable;
@property (nonatomic, strong) NSMutableArray *allClasses;
@property (nonatomic, strong) NSMutableArray *filteredClasses;

// Tab 3: Terminal
@property (nonatomic, strong) UIView *terminalView;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UIButton *netToggleBtn;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES; // Allow touches
        self.backgroundColor = [UIColor clearColor]; // Make background invisible
        [self loadClasses];
        [self setupUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLog:) name:@"EnigmaLog" object:nil];
    }
    return self;
}

// --- CRITICAL FIX: ALLOW TOUCHES THROUGH ---
// This method allows you to click Instagram buttons when the menu is closed
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // If the touch hit "self" (the empty full-screen view), return nil so it passes to Instagram
    if (hitView == self) return nil;
    
    // Otherwise, it hit a button or the menu panel, so we keep the touch
    return hitView;
}

- (void)loadClasses {
    self.allClasses = [NSMutableArray array];
    const char *mainImage = _dyld_get_image_name(0);
    unsigned int count = 0;
    const char **classes = objc_copyClassNamesForImage(mainImage, &count);
    for (unsigned int i = 0; i < count; i++) {
        [self.allClasses addObject:[NSString stringWithUTF8String:classes[i]]];
    }
    if (classes) free(classes);
    [self.allClasses sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.filteredClasses = [NSMutableArray arrayWithArray:self.allClasses];
}

- (void)setupUI {
    // 1. Floating Button
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 70, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderWidth = 1.5;
    self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn setTitleColor:THEME_COLOR forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    // 2. Main Panel
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurPanel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurPanel.frame = CGRectMake(20, 160, self.frame.size.width - 40, 450);
    self.blurPanel.layer.cornerRadius = 18;
    self.blurPanel.layer.borderColor = [UIColor grayColor].CGColor;
    self.blurPanel.layer.borderWidth = 1;
    self.blurPanel.clipsToBounds = YES;
    self.blurPanel.hidden = YES;
    [self addSubview:self.blurPanel];

    self.contentView = self.blurPanel.contentView;

    // 3. Tabs
    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"Identity", @"Inspector", @"Terminal"]];
    self.tabs.frame = CGRectMake(15, 15, self.contentView.frame.size.width - 30, 35);
    self.tabs.selectedSegmentIndex = 0;
    self.tabs.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
    self.tabs.selectedSegmentTintColor = THEME_COLOR;
    [self.tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
    [self.tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.tabs];

    // 4. Setup Views
    [self setupIdentityView];
    [self setupInspectorView];
    [self setupTerminalView];
}

// --- TAB 1: IDENTITY SETUP ---
- (void)setupIdentityView {
    self.identityView = [[UIView alloc] initWithFrame:CGRectMake(0, 60, self.contentView.frame.size.width, 390)];
    [self.contentView addSubview:self.identityView];

    self.idInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, self.identityView.frame.size.width - 40, 100)];
    self.idInfoLabel.numberOfLines = 5;
    self.idInfoLabel.textColor = [UIColor lightGrayColor];
    self.idInfoLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self updateIdLabels];
    [self.identityView addSubview:self.idInfoLabel];

    UIButton *btnReset = [UIButton buttonWithType:UIButtonTypeSystem];
    btnReset.frame = CGRectMake(20, 140, self.identityView.frame.size.width - 40, 45);
    btnReset.backgroundColor = [UIColor systemRedColor];
    btnReset.layer.cornerRadius = 10;
    [btnReset setTitle:@"ROTATE IDENTITY & RESTART" forState:UIControlStateNormal];
    [btnReset setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btnReset addTarget:self action:@selector(doReset) forControlEvents:UIControlEventTouchUpInside];
    [self.identityView addSubview:btnReset];
}

// --- TAB 2: INSPECTOR SETUP ---
- (void)setupInspectorView {
    self.inspectorView = [[UIView alloc] initWithFrame:self.identityView.frame];
    self.inspectorView.hidden = YES;
    [self.contentView addSubview:self.inspectorView];

    self.searchField = [[UITextField alloc] initWithFrame:CGRectMake(15, 0, self.inspectorView.frame.size.width - 30, 35)];
    self.searchField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.searchField.textColor = [UIColor whiteColor];
    self.searchField.layer.cornerRadius = 8;
    self.searchField.placeholder = @" Search Classes...";
    self.searchField.delegate = self;
    [self.searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inspectorView addSubview:self.searchField];

    self.classTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 45, self.inspectorView.frame.size.width, 345)];
    self.classTable.backgroundColor = [UIColor clearColor];
    self.classTable.delegate = self;
    self.classTable.dataSource = self;
    [self.inspectorView addSubview:self.classTable];
}

// --- TAB 3: TERMINAL SETUP ---
- (void)setupTerminalView {
    self.terminalView = [[UIView alloc] initWithFrame:self.identityView.frame];
    self.terminalView.hidden = YES;
    [self.contentView addSubview:self.terminalView];

    self.netToggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.netToggleBtn.frame = CGRectMake(15, 0, self.terminalView.frame.size.width - 30, 35);
    self.netToggleBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.netToggleBtn.layer.cornerRadius = 8;
    [self.netToggleBtn setTitle:@"START NETWORK MONITOR" forState:UIControlStateNormal];
    [self.netToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [self.netToggleBtn addTarget:self action:@selector(toggleNet) forControlEvents:UIControlEventTouchUpInside];
    [self.terminalView addSubview:self.netToggleBtn];

    self.consoleView = [[UITextView alloc] initWithFrame:CGRectMake(15, 45, self.terminalView.frame.size.width - 30, 335)];
    self.consoleView.backgroundColor = [UIColor blackColor];
    self.consoleView.textColor = THEME_COLOR;
    self.consoleView.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.consoleView.editable = NO;
    self.consoleView.text = @"[SYSTEM] Ready.\n";
    [self.terminalView addSubview:self.consoleView];
}

// --- UI LOGIC ---
- (void)toggleMenu {
    self.blurPanel.hidden = !self.blurPanel.hidden;
    if (self.blurPanel.hidden) [self.searchField resignFirstResponder];
}

- (void)tabChanged {
    self.identityView.hidden = (self.tabs.selectedSegmentIndex != 0);
    self.inspectorView.hidden = (self.tabs.selectedSegmentIndex != 1);
    self.terminalView.hidden = (self.tabs.selectedSegmentIndex != 2);
    [self.searchField resignFirstResponder];
}

- (void)updateIdLabels {
    self.idInfoLabel.text = [NSString stringWithFormat:@"UUID: ...%@\nUDID: ...%@\nModel: %s\nStatus: Active",
        [fakeUUID substringFromIndex:MAX(0, (int)fakeUUID.length-12)],
        [fakeUDID substringFromIndex:MAX(0, (int)fakeUDID.length-12)],
        fakeModel];
}

- (void)doReset {
    fakeUUID = [[NSUUID UUID] UUIDString];
    NSString *pool = @"abcdef0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:40];
    for (int i=0; i<40; i++) [s appendFormat:@"%C", [pool characterAtIndex:arc4random_uniform(16)]];
    fakeUDID = s;
    savePrefs();
    exit(0);
}

// --- INSPECTOR LOGIC ---
- (void)searchChanged:(UITextField *)tf {
    if (tf.text.length == 0) {
        self.filteredClasses = [NSMutableArray arrayWithArray:self.allClasses];
    } else {
        NSPredicate *p = [NSPredicate predicateWithFormat:@"SELF contains[c] %@", tf.text];
        self.filteredClasses = [NSMutableArray arrayWithArray:[self.allClasses filteredArrayUsingPredicate:p]];
    }
    [self.classTable reloadData];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.filteredClasses.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.backgroundColor = [UIColor clearColor];
    c.textLabel.textColor = [UIColor whiteColor];
    c.textLabel.font = [UIFont fontWithName:@"Courier" size:12];
    c.textLabel.text = self.filteredClasses[p.row];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [self dumpClass:self.filteredClasses[p.row]];
    self.tabs.selectedSegmentIndex = 2; // Jump to terminal
    [self tabChanged];
}

// --- TERMINAL LOGIC ---
- (void)log:(NSString *)txt {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.consoleView.text = [self.consoleView.text stringByAppendingFormat:@"%@\n", txt];
        [self.consoleView scrollRangeToVisible:NSMakeRange(self.consoleView.text.length - 1, 1)];
    });
}
- (void)handleLog:(NSNotification *)n { [self log:n.object]; }

- (void)dumpClass:(NSString *)name {
    [self log:[NSString stringWithFormat:@"\n[*] DUMPING: %@", name]];
    Class c = objc_getClass([name UTF8String]);
    if (!c) { [self log:@"[!] Class not found"]; return; }
    unsigned int count;
    Method *m = class_copyMethodList(c, &count);
    for (int i=0; i<count; i++) {
        [self log:[NSString stringWithFormat:@" - %@", NSStringFromSelector(method_getName(m[i]))]];
    }
    free(m);
}

- (void)toggleNet {
    isNetMonEnabled = !isNetMonEnabled;
    if (isNetMonEnabled) {
        [self.netToggleBtn setTitle:@"STOP MONITOR" forState:UIControlStateNormal];
        [self.netToggleBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [self log:@"[*] Monitor STARTED."];
    } else {
        [self.netToggleBtn setTitle:@"START NETWORK MONITOR" forState:UIControlStateNormal];
        [self.netToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [self log:@"[*] Monitor STOPPED."];
    }
}
@end

// --- HOOKS ---

// Aggressive Network Hook
%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSArray *orig = %orig;
    if (![orig containsObject:[EnigmaNetLogger class]]) {
        NSMutableArray *new = [NSMutableArray arrayWithObject:[EnigmaNetLogger class]];
        [new addObjectsFromArray:orig];
        return new;
    }
    return orig;
}
%end

// Identity Hooks
%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUUID]; }
%end

static CFPropertyListRef (*old_MGCopyAnswer)(CFStringRef);
CFPropertyListRef new_MGCopyAnswer(CFStringRef p) {
    if (CFStringCompare(p, CFSTR("UniqueDeviceID"), 0) == 0) return (__bridge CFPropertyListRef)fakeUDID;
    return old_MGCopyAnswer(p);
}

static int (*old_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
int new_sysctlbyname(const char *n, void *o, size_t *ol, void *np, size_t nl) {
    if (strcmp(n, "hw.machine") == 0 && o) {
        size_t l = strlen(fakeModel) + 1;
        if (*ol >= l) { memcpy(o, fakeModel, l); *ol = l; }
        return 0;
    }
    return old_sysctlbyname(n, o, ol, np, nl);
}

// --- CONSTRUCTOR ---
%ctor {
    loadPrefs();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
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
            
            void *sc = dlsym(RTLD_DEFAULT, "sysctlbyname");
            if (sc) MSHookFunction(sc, (void *)new_sysctlbyname, (void **)&old_sysctlbyname);
        } @catch (NSException *e) {}
    });
    %init;
}
