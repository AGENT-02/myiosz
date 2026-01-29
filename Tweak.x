#import <UIKit/UIKit.h>
#import <substrate.h>

// Static storage for the spoofed identifiers
static NSString *fakeUUID = @"770E8400-E29B-41D4-A716-446655440000";
static NSString *fakeUDID = @"9999999999999999999999999999999999999999";

@interface EnigmaOverlay : UIView
@property (nonatomic, strong) UIButton *cornerBtn;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UILabel *infoLabel;
@end

@implementation EnigmaOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        // This ensures the overlay doesn't block touches to the app unless interacting with our UI
        self.backgroundColor = [UIColor clearColor];
        [self setupUI];
    }
    return self;
}

// Ensure touches pass through the clear areas of the overlay to the app underneath
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}

- (void)setupUI {
    // 1. Persistent Corner Button (Ω)
    self.cornerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cornerBtn.frame = CGRectMake(self.frame.size.width - 60, 50, 50, 50);
    self.cornerBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.cornerBtn.layer.cornerRadius = 25;
    self.cornerBtn.layer.borderWidth = 1;
    self.cornerBtn.layer.borderColor = [UIColor systemBlueColor].CGColor;
    [self.cornerBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.cornerBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.cornerBtn];

    // 2. The Jailed Menu
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(30, 110, self.frame.size.width - 60, 320)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
    self.menuView.layer.cornerRadius = 20;
    self.menuView.hidden = YES;
    [self addSubview:self.menuView];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, self.menuView.frame.size.width, 30)];
    title.text = @"ENIGMA JAILED 26.2";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor systemBlueColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.menuView addSubview:title];

    // Status Label
    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, self.menuView.frame.size.width - 40, 60)];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.textColor = [UIColor whiteColor];
    self.infoLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    [self updateLabels];
    [self.menuView addSubview:self.infoLabel];

    // Action Buttons
    UIButton *btnUUID = [self createBtn:CGRectMake(20, 120, self.menuView.frame.size.width - 40, 45) title:@"Rotate UUID" color:[UIColor systemBlueColor]];
    [btnUUID addTarget:self action:@selector(doUUID) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:btnUUID];

    UIButton *btnUDID = [self createBtn:CGRectMake(20, 175, self.menuView.frame.size.width - 40, 45) title:@"Rotate UDID" color:[UIColor systemIndigoColor]];
    [btnUDID addTarget:self action:@selector(doUDID) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:btnUDID];

    UIButton *btnClose = [self createBtn:CGRectMake(20, 250, self.menuView.frame.size.width - 40, 45) title:@"Close Menu" color:[UIColor systemRedColor]];
    [btnClose addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:btnClose];
}

- (UIButton *)createBtn:(CGRect)frame title:(NSString *)title color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 10;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    return btn;
}

- (void)updateLabels {
    self.infoLabel.text = [NSString stringWithFormat:@"CURRENT IDENTITY:\nUUID: %@\nUDID: %@", 
                           [fakeUUID substringToIndex:12], [fakeUDID substringToIndex:12]];
}

- (void)toggleMenu {
    self.menuView.hidden = !self.menuView.hidden;
}

- (void)doUUID {
    fakeUUID = [[NSUUID UUID] UUIDString];
    [self updateLabels];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)doUDID {
    NSString *pool = @"abcdef0123456789";
    NSMutableString *res = [NSMutableString stringWithCapacity:40];
    for (int i=0; i<40; i++) [res appendFormat:@"%C", [pool characterAtIndex:arc4random_uniform(16)]];
    fakeUDID = res;
    [self updateLabels];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];
}
@end

// --- THE HOOKS ---

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:fakeUUID];
}
%end

// Jailed UDID Hooking
extern "C" CFPropertyListRef MGCopyAnswer(CFStringRef property);
static CFPropertyListRef (*old_MGCopyAnswer)(CFStringRef property);

CFPropertyListRef new_MGCopyAnswer(CFStringRef property) {
    if (property && CFStringCompare(property, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo) {
        return (__bridge CFPropertyListRef)fakeUDID;
    }
    return old_MGCopyAnswer(property);
}

// --- INITIALIZATION ---

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWin = nil;
            // Modern iOS 26.2 Window Retrieval
            for (UIWindowScene* scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) if (w.isKeyWindow) { keyWin = w; break; }
                }
            }
            if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
            
            if (keyWin) {
                EnigmaOverlay *overlay = [[EnigmaOverlay alloc] initWithFrame:keyWin.bounds];
                [keyWin addSubview:overlay];
            }
        });
    }];
    
    MSHookFunction((void *)MGCopyAnswer, (void *)new_MGCopyAnswer, (void **)&old_MGCopyAnswer);
    %init;
}
