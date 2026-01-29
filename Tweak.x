#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <CoreLocation/CoreLocation.h>

// --- CONFIGURATION ---
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0] // Cyan
#define kUUIDKey @"EnigmaSavedUUID"
#define kUDIDKey @"EnigmaSavedUDID"
#define kLatKey @"EnigmaSavedLat"
#define kLngKey @"EnigmaSavedLng"

// --- GLOBAL STATE ---
static NSString *fakeUUID = nil;
static NSString *fakeUDID = nil;
static char *fakeModel = "iPhone18,1";
static BOOL isNetMonEnabled = NO;
static BOOL isLocSpoofEnabled = NO;
static BOOL isUISelectMode = NO;
static double fakeLat = 25.2048;
static double fakeLng = 55.2708;

// --- PERSISTENCE ---
void loadPrefs() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    fakeUUID = [d stringForKey:kUUIDKey];
    fakeUDID = [d stringForKey:kUDIDKey];
    if (!fakeUUID) fakeUUID = @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
    if (!fakeUDID) fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";
    if ([d objectForKey:kLatKey]) {
        fakeLat = [d doubleForKey:kLatKey];
        fakeLng = [d doubleForKey:kLngKey];
        isLocSpoofEnabled = YES;
    }
}
void savePrefs() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:fakeUUID forKey:kUUIDKey];
    [d setObject:fakeUDID forKey:kUDIDKey];
    [d setDouble:fakeLat forKey:kLatKey];
    [d setDouble:fakeLng forKey:kLngKey];
    [d synchronize];
}

// --- NETWORK LOGGER ---
@interface EnigmaNetLogger : NSURLProtocol @end
@implementation EnigmaNetLogger
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    if (!isNetMonEnabled) return NO;
    if ([NSURLProtocol propertyForKey:@"EnigmaHandled" inRequest:r]) return NO;
    return YES;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"EnigmaHandled" inRequest:newReq];
    NSString *log = [NSString stringWithFormat:@"[%@] %@", newReq.HTTPMethod ?: @"GET", newReq.URL.path];
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

// --- MAIN MENU ---
@interface EnigmaMenu : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIVisualEffectView *blurPanel;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UISegmentedControl *tabs;

// Views
@property (nonatomic, strong) UIView *identityView;
@property (nonatomic, strong) UIView *inspectorView;
@property (nonatomic, strong) UIView *libraryView;
@property (nonatomic, strong) UIView *terminalView;
@property (nonatomic, strong) UIView *editorView;

// Identity Elements
@property (nonatomic, strong) UILabel *idInfoLabel;
@property (nonatomic, strong) UITextField *latField;
@property (nonatomic, strong) UITextField *lngField;

// Inspector & Lib Elements
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UITableView *classTable;
@property (nonatomic, strong) NSMutableArray *allClasses;
@property (nonatomic, strong) NSMutableArray *filteredClasses;
@property (nonatomic, strong) NSMutableArray *loadedLibraries;
@property (nonatomic, strong) UITableView *libraryTable;

// Terminal
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UIButton *netToggleBtn;

// Editor
@property (nonatomic, strong) UIButton *editorToggleBtn;
@property (nonatomic, strong) UILabel *editorInfo;
@property (nonatomic, strong) UIView *selectedHighlight;
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, strong) UITextField *textEditField;
@property (nonatomic, strong) UIButton *setTextBtn;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        [self loadData];
        [self setupUI];
        
        // Tap Gesture for Editor
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGlobalTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLog:) name:@"EnigmaLog" object:nil];
    }
    return self;
}

// 1. CRITICAL: FORCE TOUCH CAPTURE IN SELECT MODE
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    
    // If we hit our own buttons (Menu, Toggle, etc.), let them work
    if ([hit isDescendantOfView:self.blurPanel] || hit == self.floatBtn) return hit;
    
    // If Selection Mode is ON, WE capture the touch (returning self).
    // This allows the Gesture Recognizer to see the tap.
    if (isUISelectMode) return self;
    
    // Otherwise, return nil so the touch passes through to Instagram
    if (hit == self) return nil;
    
    return hit;
}

// 2. CRITICAL: "PEEK-A-BOO" VIEW FINDER
- (void)handleGlobalTap:(UITapGestureRecognizer *)tap {
    if (!isUISelectMode) return;
    
    CGPoint loc = [tap locationInView:self.window];
    
    // A. Hide ourselves so the system ignores us
    self.hidden = YES;
    
    // B. Ask the window what is truly underneath at that point
    UIView *hitView = [self.window hitTest:loc withEvent:nil];
    
    // C. Re-appear immediately
    self.hidden = NO;
    
    // D. Select it
    if (hitView) {
        [self selectTargetView:hitView];
    }
}

- (void)selectTargetView:(UIView *)v {
    self.targetView = v;
    
    // Highlight Box
    if (!self.selectedHighlight) {
        self.selectedHighlight = [[UIView alloc] initWithFrame:CGRectZero];
        self.selectedHighlight.layer.borderColor = [UIColor redColor].CGColor;
        self.selectedHighlight.layer.borderWidth = 3;
        self.selectedHighlight.userInteractionEnabled = NO;
        [self.window addSubview:self.selectedHighlight];
    }
    self.selectedHighlight.frame = [v convertRect:v.bounds toView:nil];
    self.selectedHighlight.hidden = NO;
    
    // Show Info
    NSString *cls = NSStringFromClass([v class]);
    self.editorInfo.text = [NSString stringWithFormat:@"Target: %@", cls];
    
    // Text Editor Logic
    if ([v respondsToSelector:@selector(setText:)]) {
        NSString *txt = [v performSelector:@selector(text)];
        self.textEditField.text = txt ? txt : @"";
        self.textEditField.hidden = NO;
        self.setTextBtn.hidden = NO;
    } else {
        self.textEditField.hidden = YES;
        self.setTextBtn.hidden = YES;
    }
    
    // Turn off selection mode and show menu
    [self toggleEditorMode]; 
    self.blurPanel.hidden = NO;
}

// --- DATA ---
- (void)loadData {
    self.allClasses = [NSMutableArray array];
    const char *mainImage = _dyld_get_image_name(0);
    unsigned int count = 0;
    const char **classes = objc_copyClassNamesForImage(mainImage, &count);
    for (unsigned int i = 0; i < count; i++) [self.allClasses addObject:[NSString stringWithUTF8String:classes[i]]];
    if (classes) free(classes);
    [self.allClasses sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.filteredClasses = [NSMutableArray arrayWithArray:self.allClasses];

    self.loadedLibraries = [NSMutableArray array];
    uint32_t imgCount = _dyld_image_count();
    for (uint32_t i = 0; i < imgCount; i++) {
        NSString *name = [NSString stringWithUTF8String:_dyld_get_image_name(i)];
        [self.loadedLibraries addObject:name.lastPathComponent];
    }
    [self.loadedLibraries sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// --- UI BUILDER ---
- (void)setupUI {
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 70, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
    self.floatBtn.layer.borderWidth = 1.5;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn setTitleColor:THEME_COLOR forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurPanel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurPanel.frame = CGRectMake(20, 160, self.frame.size.width - 40, 500);
    self.blurPanel.layer.cornerRadius = 18;
    self.blurPanel.layer.borderColor = [UIColor grayColor].CGColor;
    self.blurPanel.layer.borderWidth = 1;
    self.blurPanel.clipsToBounds = YES;
    self.blurPanel.hidden = YES;
    [self addSubview:self.blurPanel];
    self.contentView = self.blurPanel.contentView;

    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"ID", @"Class", @"Libs", @"Log", @"Edit"]];
    self.tabs.frame = CGRectMake(10, 10, self.contentView.frame.size.width - 20, 30);
    self.tabs.selectedSegmentIndex = 0;
    self.tabs.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
    self.tabs.selectedSegmentTintColor = THEME_COLOR;
    [self.tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
    [self.tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.tabs];

    [self setupIdentityView];
    [self setupInspectorView];
    [self setupLibraryView];
    [self setupTerminalView];
    [self setupEditorView];
}

// --- TAB SETUPS ---
- (void)setupIdentityView {
    self.identityView = [[UIView alloc] initWithFrame:CGRectMake(0, 50, self.contentView.frame.size.width, 450)];
    [self.contentView addSubview:self.identityView];
    self.idInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, self.identityView.frame.size.width - 40, 80)];
    self.idInfoLabel.numberOfLines = 4;
    self.idInfoLabel.textColor = [UIColor lightGrayColor];
    self.idInfoLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    [self updateIdLabels];
    [self.identityView addSubview:self.idInfoLabel];
    [self makeBtn:@"ROTATE IDENTITY & RESTART" y:90 col:[UIColor systemRedColor] sel:@selector(doReset) parent:self.identityView];
    UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(20, 150, 200, 20)];
    h.text = @"LOCATION SPOOFER"; h.textColor = THEME_COLOR; h.font = [UIFont boldSystemFontOfSize:12];
    [self.identityView addSubview:h];
    self.latField = [self createField:@"Latitude" y:180];
    self.lngField = [self createField:@"Longitude" y:225];
    [self.identityView addSubview:self.latField]; [self.identityView addSubview:self.lngField];
    [self makeBtn:@"TELEPORT NOW" y:280 col:THEME_COLOR sel:@selector(doTeleport) parent:self.identityView];
}

- (void)setupInspectorView {
    self.inspectorView = [[UIView alloc] initWithFrame:self.identityView.frame]; self.inspectorView.hidden = YES;
    [self.contentView addSubview:self.inspectorView];
    self.searchField = [self createField:@"Search Classes..." y:0];
    self.searchField.frame = CGRectMake(15, 0, self.inspectorView.frame.size.width - 30, 35);
    [self.searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inspectorView addSubview:self.searchField];
    self.classTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 45, self.inspectorView.frame.size.width, 380)];
    self.classTable.backgroundColor = [UIColor clearColor];
    self.classTable.delegate = self; self.classTable.dataSource = self;
    [self.inspectorView addSubview:self.classTable];
}

- (void)setupLibraryView {
    self.libraryView = [[UIView alloc] initWithFrame:self.identityView.frame]; self.libraryView.hidden = YES;
    [self.contentView addSubview:self.libraryView];
    self.libraryTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 25, self.libraryView.frame.size.width, 400)];
    self.libraryTable.backgroundColor = [UIColor clearColor];
    self.libraryTable.delegate = self; self.libraryTable.dataSource = self;
    [self.libraryView addSubview:self.libraryTable];
}

- (void)setupTerminalView {
    self.terminalView = [[UIView alloc] initWithFrame:self.identityView.frame]; self.terminalView.hidden = YES;
    [self.contentView addSubview:self.terminalView];
    self.netToggleBtn = [self makeBtn:@"START NETWORK MONITOR" y:0 col:[UIColor colorWithWhite:0.2 alpha:1.0] sel:@selector(toggleNet) parent:self.terminalView];
    [self.netToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    self.consoleView = [[UITextView alloc] initWithFrame:CGRectMake(15, 45, self.terminalView.frame.size.width - 30, 360)];
    self.consoleView.backgroundColor = [UIColor blackColor];
    self.consoleView.textColor = THEME_COLOR;
    self.consoleView.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.consoleView.editable = NO;
    [self.terminalView addSubview:self.consoleView];
}

- (void)setupEditorView {
    self.editorView = [[UIView alloc] initWithFrame:self.identityView.frame]; self.editorView.hidden = YES;
    [self.contentView addSubview:self.editorView];
    self.editorToggleBtn = [self makeBtn:@"ENABLE SELECTION MODE" y:0 col:[UIColor colorWithWhite:0.2 alpha:1.0] sel:@selector(toggleEditorMode) parent:self.editorView];
    [self.editorToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    self.editorInfo = [[UILabel alloc] initWithFrame:CGRectMake(20, 45, self.editorView.frame.size.width - 40, 40)];
    self.editorInfo.numberOfLines = 2; self.editorInfo.textColor = [UIColor lightGrayColor];
    self.editorInfo.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.editorInfo.text = @"Select an item to edit..."; self.editorInfo.textAlignment = NSTextAlignmentCenter;
    [self.editorView addSubview:self.editorInfo];
    self.textEditField = [self createField:@"New Text..." y:95];
    self.textEditField.frame = CGRectMake(20, 95, self.editorView.frame.size.width - 100, 35);
    self.textEditField.backgroundColor = [UIColor whiteColor]; self.textEditField.textColor = [UIColor blackColor]; self.textEditField.hidden = YES;
    [self.editorView addSubview:self.textEditField];
    self.setTextBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.setTextBtn.frame = CGRectMake(self.editorView.frame.size.width - 70, 95, 50, 35);
    self.setTextBtn.backgroundColor = THEME_COLOR;
    self.setTextBtn.layer.cornerRadius = 6;
    [self.setTextBtn setTitle:@"SET" forState:UIControlStateNormal];
    [self.setTextBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.setTextBtn addTarget:self action:@selector(doUpdateText) forControlEvents:UIControlEventTouchUpInside];
    self.setTextBtn.hidden = YES;
    [self.editorView addSubview:self.setTextBtn];
    [self makeBtn:@"HIDE VIEW" y:150 col:[UIColor systemOrangeColor] sel:@selector(doHideView) parent:self.editorView];
    [self makeBtn:@"TINT RED" y:200 col:[UIColor systemBlueColor] sel:@selector(doColorView) parent:self.editorView];
    [self makeBtn:@"DELETE OBJECT" y:250 col:[UIColor systemRedColor] sel:@selector(doRemoveView) parent:self.editorView];
}

// --- HELPERS & LOGIC ---
- (UIButton *)makeBtn:(NSString*)t y:(CGFloat)y col:(UIColor*)c sel:(SEL)s parent:(UIView*)p {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, y, p.frame.size.width - 40, 40);
    b.backgroundColor = c; b.layer.cornerRadius = 8;
    [b setTitle:t forState:UIControlStateNormal]; [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:b]; return b;
}
- (UITextField *)createField:(NSString *)place y:(CGFloat)y {
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(20, y, self.identityView.frame.size.width - 40, 35)];
    tf.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0]; tf.textColor = [UIColor whiteColor];
    tf.placeholder = place; tf.layer.cornerRadius = 6; tf.delegate = self; return tf;
}
- (void)toggleMenu { self.blurPanel.hidden = !self.blurPanel.hidden; if(self.blurPanel.hidden) [self endEditing:YES]; }
- (void)tabChanged {
    self.identityView.hidden = (self.tabs.selectedSegmentIndex != 0);
    self.inspectorView.hidden = (self.tabs.selectedSegmentIndex != 1);
    self.libraryView.hidden = (self.tabs.selectedSegmentIndex != 2);
    self.terminalView.hidden = (self.tabs.selectedSegmentIndex != 3);
    self.editorView.hidden = (self.tabs.selectedSegmentIndex != 4);
    [self endEditing:YES];
}
- (void)doReset {
    fakeUUID = [[NSUUID UUID] UUIDString];
    NSString *pool = @"abcdef0123456789"; NSMutableString *s = [NSMutableString stringWithCapacity:40];
    for (int i=0; i<40; i++) [s appendFormat:@"%C", [pool characterAtIndex:arc4random_uniform(16)]];
    fakeUDID = s; savePrefs(); exit(0);
}
- (void)doTeleport { fakeLat = [self.latField.text doubleValue]; fakeLng = [self.lngField.text doubleValue]; isLocSpoofEnabled = YES; savePrefs(); [self updateIdLabels]; }
- (void)updateIdLabels {
    NSString *loc = isLocSpoofEnabled ? [NSString stringWithFormat:@"%0.4f, %0.4f", fakeLat, fakeLng] : @"Real";
    self.idInfoLabel.text = [NSString stringWithFormat:@"UUID: ...%@\nUDID: ...%@\nModel: %s\nLoc: %@", [fakeUUID substringFromIndex:MAX(0, (int)fakeUUID.length-8)], [fakeUDID substringFromIndex:MAX(0, (int)fakeUDID.length-8)], fakeModel, loc];
}
- (void)toggleEditorMode {
    isUISelectMode = !isUISelectMode;
    if (isUISelectMode) {
        [self.editorToggleBtn setTitle:@"SELECTION MODE: ACTIVE" forState:UIControlStateNormal];
        [self.editorToggleBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [self toggleMenu];
    } else {
        [self.editorToggleBtn setTitle:@"ENABLE SELECTION MODE" forState:UIControlStateNormal];
        [self.editorToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        if (self.selectedHighlight) self.selectedHighlight.hidden = YES;
    }
}
- (void)doUpdateText { if (self.targetView && [self.targetView respondsToSelector:@selector(setText:)]) { [self.targetView performSelector:@selector(setText:) withObject:self.textEditField.text]; [self.textEditField resignFirstResponder]; } }
- (void)doHideView { self.targetView.hidden = YES; self.selectedHighlight.hidden = YES; }
- (void)doColorView { self.targetView.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5]; }
- (void)doRemoveView { [self.targetView removeFromSuperview]; self.selectedHighlight.hidden = YES; }
- (void)toggleNet {
    isNetMonEnabled = !isNetMonEnabled;
    if (isNetMonEnabled) { [self.netToggleBtn setTitle:@"STOP MONITOR" forState:UIControlStateNormal]; [self.netToggleBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal]; }
    else { [self.netToggleBtn setTitle:@"START NETWORK MONITOR" forState:UIControlStateNormal]; [self.netToggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal]; }
}
- (void)handleLog:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.consoleView.text = [self.consoleView.text stringByAppendingFormat:@"%@\n", n.object];
        [self.consoleView scrollRangeToVisible:NSMakeRange(self.consoleView.text.length - 1, 1)];
    });
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (t == self.classTable) return self.filteredClasses.count;
    if (t == self.libraryTable) return self.loadedLibraries.count;
    return 0;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.backgroundColor = [UIColor clearColor]; c.textLabel.textColor = [UIColor whiteColor]; c.textLabel.font = [UIFont fontWithName:@"Courier" size:12];
    if (t == self.classTable) c.textLabel.text = self.filteredClasses[p.row];
    if (t == self.libraryTable) {
        c.textLabel.text = self.loadedLibraries[p.row];
        if ([c.textLabel.text containsString:@".dylib"]) c.textLabel.textColor = [UIColor yellowColor];
    }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    if (t == self.classTable) {
        Class c = objc_getClass([self.filteredClasses[p.row] UTF8String]);
        unsigned int count; Method *m = class_copyMethodList(c, &count);
        [self handleLog:[NSNotification notificationWithName:@"L" object:[NSString stringWithFormat:@"\n[*] DUMP: %@", self.filteredClasses[p.row]]]];
        for (int i=0; i<count; i++) [self handleLog:[NSNotification notificationWithName:@"L" object:[NSString stringWithFormat:@" - %@", NSStringFromSelector(method_getName(m[i]))]]];
        free(m); self.tabs.selectedSegmentIndex = 3; [self tabChanged];
    }
    if (t == self.libraryTable) {
        NSString *lib = self.loadedLibraries[p.row];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Module Info" message:[NSString stringWithFormat:@"Module: %@\nLoad Address: Check Debugger", lib] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
    }
}
- (void)searchChanged:(UITextField *)tf {
    if (tf.text.length == 0) self.filteredClasses = [NSMutableArray arrayWithArray:self.allClasses];
    else { NSPredicate *p = [NSPredicate predicateWithFormat:@"SELF contains[c] %@", tf.text]; self.filteredClasses = [NSMutableArray arrayWithArray:[self.allClasses filteredArrayUsingPredicate:p]]; }
    [self.classTable reloadData];
}
@end

// --- HOOKS ---
%hook CLLocationManager
- (CLLocation *)location {
    if (isLocSpoofEnabled) return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(fakeLat, fakeLng) altitude:10 horizontalAccuracy:5 verticalAccuracy:5 timestamp:[NSDate date]];
    return %orig;
}
%end
%hook NSURLSession
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id)d delegateQueue:(NSOperationQueue *)q {
    if (c) {
        c.HTTPShouldUsePipelining = YES;
        NSMutableArray *p = [NSMutableArray arrayWithArray:c.protocolClasses];
        if (![p containsObject:[EnigmaNetLogger class]]) { [p insertObject:[EnigmaNetLogger class] atIndex:0]; c.protocolClasses = p; }
    }
    return %orig;
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c {
    if (c) {
        NSMutableArray *p = [NSMutableArray arrayWithArray:c.protocolClasses];
        if (![p containsObject:[EnigmaNetLogger class]]) { [p insertObject:[EnigmaNetLogger class] atIndex:0]; c.protocolClasses = p; }
    }
    return %orig;
}
%end
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

%ctor {
    loadPrefs();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (!w) for(UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) if(s.activationState==0) for(UIWindow* win in s.windows) if(win.isKeyWindow) w=win;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
        
        void *mg = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (mg) MSHookFunction(mg, (void *)new_MGCopyAnswer, (void **)&old_MGCopyAnswer);
        void *sc = dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (sc) MSHookFunction(sc, (void *)new_sysctlbyname, (void **)&old_sysctlbyname);
    });
    %init;
}
