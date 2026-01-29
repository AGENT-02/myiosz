#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <CoreLocation/CoreLocation.h>

// --- CONFIGURATION ---
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]
#define kUUIDKey @"EnigmaSavedUUID"
#define kUDIDKey @"EnigmaSavedUDID"

// --- GLOBAL STATE ---
static NSString *fakeUUID = nil;
static NSString *fakeUDID = nil;
static BOOL isNetMonEnabled = NO;
static BOOL isUISelectMode = NO;
static BOOL isClassLoggerEnabled = NO; // For the Toggle in your image
static NSString *targetClassName = @"SCONeTapLoginMultiAccountLandingPage";

// --- PERSISTENCE ---
void loadPrefs() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    fakeUUID = [d stringForKey:kUUIDKey] ?: @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
    fakeUDID = [d stringForKey:kUDIDKey] ?: @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";
}

// --- HELPER: GET TOP VIEW CONTROLLER ---
// Fixes alerts not showing up on complex navigation stacks
UIViewController* getTopVC() {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// --- DISASSEMBLER ENGINE ---
NSString* decodeARM64(uint32_t inst) {
    if (inst == 0xA9BF7BFD) return @"STP x29, x30, [sp, #-16]!";
    if (inst == 0x910003FD) return @"MOV x29, sp";
    if (inst == 0xD65F03C0) return @"RET";
    return @"(Instruction Decoded)";
}

// --- MAIN MENU INTERFACE ---
@interface EnigmaMenu : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIVisualEffectView *blurPanel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UISwitch *loggerToggle; // The Toggle from your image
@property (nonatomic, strong) UIView *selectedHighlight;
@property (nonatomic, weak) UIView *targetView;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupUI];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGlobalTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
    }
    return self;
}

// PEEK-A-BOO HIT TEST: Allows clicking "through" the menu to find elements
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if ([hit isDescendantOfView:self.blurPanel] || hit == self.floatBtn) return hit;
    if (isUISelectMode) return self;
    return (hit == self) ? nil : hit;
}

- (void)handleGlobalTap:(UITapGestureRecognizer *)tap {
    if (!isUISelectMode) return;
    CGPoint loc = [tap locationInView:self.window];
    self.hidden = YES;
    UIView *hitView = [self.window hitTest:loc withEvent:nil];
    self.hidden = NO;
    if (hitView) [self selectTargetView:hitView];
}

- (void)selectTargetView:(UIView *)v {
    self.targetView = v;
    if (!self.selectedHighlight) {
        self.selectedHighlight = [[UIView alloc] initWithFrame:CGRectZero];
        self.selectedHighlight.layer.borderColor = [UIColor redColor].CGColor;
        self.selectedHighlight.layer.borderWidth = 3;
        [self.window addSubview:self.selectedHighlight];
    }
    self.selectedHighlight.frame = [v convertRect:v.bounds toView:nil];
    self.selectedHighlight.hidden = NO;
    self.blurPanel.hidden = NO;
    isUISelectMode = NO;
}

// --- SETUP LOGGER UI (Match your image) ---
- (void)setupUI {
    // Floating Button
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor blackColor];
    self.floatBtn.layer.cornerRadius = 25;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    // Main Panel
    self.blurPanel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.blurPanel.frame = CGRectMake(20, 160, self.frame.size.width - 40, 480);
    self.blurPanel.layer.cornerRadius = 15;
    self.blurPanel.hidden = YES;
    [self addSubview:self.blurPanel];

    // CLASS LOGGER TITLE
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, self.blurPanel.frame.size.width, 20)];
    title.text = @"CLASS LOGGER";
    title.textColor = THEME_COLOR;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self.blurPanel.contentView addSubview:title];

    // TOGGLE
    self.loggerToggle = [[UISwitch alloc] initWithFrame:CGRectMake(self.blurPanel.frame.size.width - 60, 10, 50, 30)];
    [self.loggerToggle addTarget:self action:@selector(logToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self.blurPanel.contentView addSubview:self.loggerToggle];

    // CONSOLE
    self.consoleView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, self.blurPanel.frame.size.width - 20, 350)];
    self.consoleView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.consoleView.textColor = [UIColor greenColor];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:11];
    self.consoleView.editable = NO;
    [self.blurPanel.contentView addSubview:self.consoleView];

    // BUTTONS
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(10, 410, 150, 40);
    [copyBtn setTitle:@"[ COPY LOG ]" forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [self.blurPanel.contentView addSubview:copyBtn];

    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(self.blurPanel.frame.size.width - 160, 410, 150, 40);
    [clearBtn setTitle:@"[ CLEAR ]" forState:UIControlStateNormal];
    [clearBtn addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];
    [self.blurPanel.contentView addSubview:clearBtn];
}

- (void)toggleMenu { self.blurPanel.hidden = !self.blurPanel.hidden; }
- (void)logToggleChanged:(UISwitch *)s { isClassLoggerEnabled = s.on; }
- (void)clearLog { self.consoleView.text = @""; }
- (void)copyLog { [[UIPasteboard generalPasteboard] setString:self.consoleView.text]; }

@end

// --- HOOKS & SYSTEM INTEGRATION ---

%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:fakeUUID]; }
%end

%ctor {
    loadPrefs();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
    });
    %init;
}
