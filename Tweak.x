#import <UIKit/UIKit.h>
#import <substrate.h>

// --- Global Variables to store fake IDs ---
static NSString *fakeUUID = @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
static NSString *fakeUDID = @"a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0";

// --- The Menu Interface ---
@interface EnigmaMenu : UIView
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *uuidLabel;
@property (nonatomic, strong) UILabel *udidLabel;
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

- (void)setupUI {
    // 1. The Floating Corner Button (Persists at Top Right)
    UIButton *cornerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cornerBtn.frame = CGRectMake(self.frame.size.width - 65, 60, 50, 50);
    cornerBtn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8];
    cornerBtn.layer.cornerRadius = 25;
    [cornerBtn setTitle:@"Ω" forState:UIControlStateNormal];
    cornerBtn.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    [cornerBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cornerBtn];

    // 2. The Main Menu Container
    self.containerView = [[UIView alloc] initWithFrame:CGRectMake(20, 120, self.frame.size.width - 40, 350)];
    self.containerView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.containerView.layer.cornerRadius = 20;
    self.containerView.layer.borderWidth = 1;
    self.containerView.layer.borderColor = [UIColor grayColor].CGColor;
    self.containerView.hidden = YES; // Start hidden
    [self addSubview:self.containerView];

    // 3. Labels and Buttons for UUID/UDID
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, self.containerView.frame.size.width, 30)];
    titleLabel.text = @"ENIGMA v26.2 JAILED";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor whiteColor];
    [self.containerView addSubview:titleLabel];

    // UUID Section
    self.uuidLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 60, 250, 20)];
    self.uuidLabel.text = [NSString stringWithFormat:@"UUID: %@", [fakeUUID substringToIndex:15]];
    self.uuidLabel.textColor = [UIColor lightGrayColor];
    self.uuidLabel.font = [UIFont systemFontOfSize:10];
    [self.containerView addSubview:self.uuidLabel];

    UIButton *uuidBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    uuidBtn.frame = CGRectMake(15, 85, self.containerView.frame.size.width - 30, 40);
    uuidBtn.backgroundColor = [UIColor systemBlueColor];
    uuidBtn.layer.cornerRadius = 10;
    [uuidBtn setTitle:@"Change UUID" forState:UIControlStateNormal];
    [uuidBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [uuidBtn addTarget:self action:@selector(changeUUID) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:uuidBtn];

    // UDID Section
    self.udidLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 145, 250, 20)];
    self.udidLabel.text = [NSString stringWithFormat:@"UDID: %@", [fakeUDID substringToIndex:15]];
    self.udidLabel.textColor = [UIColor lightGrayColor];
    self.udidLabel.font = [UIFont systemFontOfSize:10];
    [self.containerView addSubview:self.udidLabel];

    UIButton *udidBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    udidBtn.frame = CGRectMake(15, 170, self.containerView.frame.size.width - 30, 40);
    udidBtn.backgroundColor = [UIColor systemIndigoColor];
    udidBtn.layer.cornerRadius = 10;
    [udidBtn setTitle:@"Change UDID" forState:UIControlStateNormal];
    [udidBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [udidBtn addTarget:self action:@selector(changeUDID) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:udidBtn];

    // 4. Close Menu Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(15, 280, self.containerView.frame.size.width - 30, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"Close Menu" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:closeBtn];
}

- (void)toggleMenu {
    self.containerView.hidden = !self.containerView.hidden;
}

- (void)changeUUID {
    fakeUUID = [[NSUUID UUID] UUIDString];
    self.uuidLabel.text = [NSString stringWithFormat:@"UUID: %@", [fakeUUID substringToIndex:15]];
    // Haptic Feedback
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)changeUDID {
    NSString *letters = @"abcdef0123456789";
    NSMutableString *randomString = [NSMutableString stringWithCapacity:40];
    for (int i=0; i<40; i++) {
        [randomString appendFormat: @"%C", [letters characterAtIndex: arc4random_uniform((uint32_t)[letters length])]];
    }
    fakeUDID = randomString;
    self.udidLabel.text = [NSString stringWithFormat:@"UDID: %@", [fakeUDID substringToIndex:15]];
    
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [haptic impactOccurred];
}
@end

// --- HOOKS ---

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:fakeUUID];
}
%end

// Note: MGCopyAnswer is a C-function. 
// In a jailed environment, this hook is less reliable but included for completeness.
extern "C" CFPropertyListRef MGCopyAnswer(CFStringRef property);
static CFPropertyListRef (*old_MGCopyAnswer)(CFStringRef property);

CFPropertyListRef new_MGCopyAnswer(CFStringRef property) {
    if (property && CFStringCompare(property, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo) {
        return (__bridge CFPropertyListRef)fakeUDID;
    }
    return old_MGCopyAnswer(property);
}

// --- Initialization ---
%ctor {
    // Wait for the app to finish loading so we can find the KeyWindow
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
                    if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *window in windowScene.windows) {
                            if (window.isKeyWindow) {
                                keyWindow = window;
                                break;
                            }
                        }
                    }
                }
            } else {
                keyWindow = [UIApplication sharedApplication].keyWindow;
            }

            if (keyWindow) {
                EnigmaMenu *menu = [[EnigmaMenu alloc] initWithFrame:keyWindow.bounds];
                [keyWindow addSubview:menu];
            }
        });
    }];

    // Initialize C-function hooks
    MSHookFunction((void *)MGCopyAnswer, (void *)new_MGCopyAnswer, (void **)&old_MGCopyAnswer);
    %init;
}
