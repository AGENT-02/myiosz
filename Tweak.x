#import <UIKit/UIKit.h>
#import <substrate.h>

// --- FIX: Declare C Functions at the VERY TOP ---
// This prevents the "expected identifier" error
#ifdef __cplusplus
extern "C" {
#endif
    CFPropertyListRef MGCopyAnswer(CFStringRef property);
#ifdef __cplusplus
}
#endif

// --- Variables ---
static NSString *fakeUUID = @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- UI Components ---
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
        self.backgroundColor = [UIColor clearColor];
        [self setupUI];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}

- (void)setupUI {
    self.cornerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cornerBtn.frame = CGRectMake(self.frame.size.width - 65, 60, 50, 50);
    self.cornerBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    self.cornerBtn.layer.cornerRadius = 25;
    self.cornerBtn.layer.borderWidth = 1;
    self.cornerBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    [self.cornerBtn setTitle:@"Ω" forState:UIControlStateNormal];
    [self.cornerBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.cornerBtn];

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(25, 120, self.frame.size.width - 50, 340)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    self.menuView.layer.cornerRadius = 18;
    self.menuView.layer.borderWidth = 1;
    self.menuView.layer.borderColor = [UIColor darkGrayColor].CGColor;
    self.menuView.hidden = YES;
    [self addSubview:self.menuView];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, self.menuView.frame.size.width, 25)];
    t.text = @"ENIGMA iOS 26.2";
    t.textAlignment = NSTextAlignmentCenter;
    t.textColor = [UIColor cyanColor];
    t.font = [UIFont boldSystemFontOfSize:16];
    [self.menuView addSubview:t];

    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, self.menuView.frame.size.width - 40, 50)];
    self.infoLabel.numberOfLines = 2;
    self.infoLabel.textColor = [UIColor whiteColor];
    self.infoLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    [self updateLabels];
    [self.menuView addSubview:self.infoLabel];

    [self makeBtn:@"Rotate UUID" y:110 col:[UIColor systemBlueColor] sel:@selector(doUUID)];
    [self makeBtn:@"Rotate UDID" y:165 col:[UIColor systemIndigoColor] sel:@selector(doUDID)];
    [self makeBtn:@"Close Menu" y:240 col:[UIColor systemRedColor] sel:@selector(toggleMenu)];
}

- (void)makeBtn:(NSString*)txt y:(CGFloat)y col:(UIColor*)col sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, y, self.menuView.frame.size.width - 40, 45);
    b.backgroundColor = col;
    b.layer.cornerRadius = 12;
    [b setTitle:txt forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:b];
}

- (void)toggleMenu {
    self.menuView.hidden = !self.menuView.hidden;
}

- (void)updateLabels {
    self.infoLabel.text = [NSString stringWithFormat:@"UUID: ...%@\nUDID: ...%@", 
        [fakeUUID substringFromIndex:MAX(0, (int)fakeUUID.length-12)], 
        [fakeUDID substringFromIndex:MAX(0, (int)fakeUDID.length-12)]];
}

- (void)doUUID {
    fakeUUID = [[NSUUID UUID] UUIDString];
    [self updateLabels];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)doUDID {
    NSString *pool = @"abcdef0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:40];
    for (int i=0; i<40; i++) [s appendFormat:@"%C", [pool characterAtIndex:arc4random_uniform(16)]];
    fakeUDID = s;
    [self updateLabels];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];
}
@end

// --- HOOKS ---
%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:fakeUUID];
}
%end

// Function pointer for the original MGCopyAnswer
static CFPropertyListRef (*old_MGCopyAnswer)(CFStringRef property);

// Our replacement function
CFPropertyListRef new_MGCopyAnswer(CFStringRef property) {
    if (property && CFStringCompare(property, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo) {
        return (__bridge CFPropertyListRef)fakeUDID;
    }
    return old_MGCopyAnswer(property);
}

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *w = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) {
                    if (s.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *win in s.windows) if (win.isKeyWindow) { w = win; break; }
                    }
                }
            }
            // Fallback for older method (deprecation warning is now suppressed via Makefile)
            if (!w) w = [UIApplication sharedApplication].keyWindow;
            
            if (w) [w addSubview:[[EnigmaOverlay alloc] initWithFrame:w.bounds]];
        });
    }];
    
    // Hooking the C function
    MSHookFunction((void *)MGCopyAnswer, (void *)new_MGCopyAnswer, (void **)&old_MGCopyAnswer);
    
    %init;
}
