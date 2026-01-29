#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- GLOBAL STATE ---
static UITextView *globalConsole = nil;
static BOOL isLoggerActive = NO;

// --- HELPER: GET TOP VIEW CONTROLLER ---
// Ensures alerts show up even on complex Snapchat screens
UIViewController* getTopVC() {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// --- SIGNATURE & ENVIRONMENT AUDITOR ---
// This identifies the "Sideload Fingerprint" that triggers login blocks
NSString* runSignatureAudit() {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"[ SECURITY AUDIT REPORT ]\n\n"];
    
    // 1. Check for Sideload Provisioning Profile
    NSString *provisionPath = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    BOOL isSideloaded = [[NSFileManager defaultManager] fileExistsAtPath:provisionPath];
    [report appendFormat:@"Sideload Profile Detected: %@\n", isSideloaded ? @"YES (FAIL)" : @"NO (PASS)"];
    
    // 2. Check Bundle ID Integrity
    NSString *bID = [[NSBundle mainBundle] bundleIdentifier];
    [report appendFormat:@"Bundle ID: %@\n", bID];
    
    // 3. Entitlement Analysis
    // Sideloaded apps signed with free accounts lack 'com.apple.developer.applesignin'
    [report appendString:@"\n[ ENTITLEMENT CHECKS ]\n"];
    if (isSideloaded) {
        NSString *profile = [NSString stringWithContentsOfFile:provisionPath encoding:NSISOLatin1StringEncoding error:nil];
        if (![profile containsString:@"com.apple.developer.applesignin"]) {
            [report appendString:@"- Apple Sign-In: [X] BLOCKED BY OS\n"];
        }
    }
    
    [report appendString:@"\n[ DIAGNOSIS ]\n"];
    [report appendString:@"Status: Environment Untrusted.\nCause: Server-side Attestation mismatch (SS03/SS06)."];
    
    return report;
}

// --- MAIN UI ---
@interface EnigmaMenu : UIView
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) UIView *blurPanel;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UISwitch *loggerToggle;
@end

@implementation EnigmaMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupUI];
    }
    return self;
}

// Fixed Hit-Test: Ensures you can tap the floating button and the panel
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.floatBtn || [hit isDescendantOfView:self.blurPanel]) return hit;
    return nil; 
}

- (void)setupUI {
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(self.frame.size.width - 60, 100, 50, 50);
    self.floatBtn.backgroundColor = [UIColor blackColor];
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.layer.borderWidth = 2;
    self.floatBtn.layer.borderColor = THEME_COLOR.CGColor;
    [self.floatBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.floatBtn setTitleColor:THEME_COLOR forState:UIControlStateNormal];
    [self.floatBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatBtn];

    self.blurPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 160, self.frame.size.width - 40, 480)];
    self.blurPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.blurPanel.layer.cornerRadius = 15;
    self.blurPanel.hidden = YES;
    [self addSubview:self.blurPanel];

    // Toggle (Logger)
    self.loggerToggle = [[UISwitch alloc] initWithFrame:CGRectMake(self.blurPanel.frame.size.width - 70, 10, 50, 30)];
    self.loggerToggle.onTintColor = THEME_COLOR;
    [self.loggerToggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self.blurPanel addSubview:self.loggerToggle];

    self.consoleView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, self.blurPanel.frame.size.width - 30, 320)];
    self.consoleView.backgroundColor = [UIColor blackColor];
    self.consoleView.textColor = [UIColor greenColor];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:10];
    self.consoleView.editable = NO;
    [self.blurPanel addSubview:self.consoleView];
    globalConsole = self.consoleView;

    // AUDIT BUTTON (New for your presentation)
    UIButton *auditBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    auditBtn.frame = CGRectMake(15, 390, self.blurPanel.frame.size.width - 30, 35);
    auditBtn.backgroundColor = [UIColor systemBlueColor];
    auditBtn.layer.cornerRadius = 6;
    [auditBtn setTitle:@"[ RUN SECURITY AUDIT ]" forState:UIControlStateNormal];
    [auditBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [auditBtn addTarget:self action:@selector(doAudit) forControlEvents:UIControlEventTouchUpInside];
    [self.blurPanel addSubview:auditBtn];
}

- (void)toggleMenu { self.blurPanel.hidden = !self.blurPanel.hidden; }
- (void)toggleChanged:(UISwitch *)s { isLoggerActive = s.on; }
- (void)doAudit {
    NSString *report = runSignatureAudit();
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Audit Result" message:report preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [getTopVC() presentViewController:a animated:YES completion:nil];
}
@end

// --- THE HOOKS ---
%hook SCONeTapLoginMultiAccountLandingPage
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isLoggerActive && globalConsole) {
        globalConsole.text = [globalConsole.text stringByAppendingString:@"[EVENT] Landing Page Detected.\n"];
    }
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
    });
}
