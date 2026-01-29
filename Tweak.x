#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- GLOBAL LOGGER STATE ---
// We use a static pointer so the Hook can talk to the UI
static UITextView *globalConsole = nil;
static BOOL isLoggerActive = NO;

// --- HELPER: WRITE TO CONSOLE ---
void loggerWrite(NSString *fmt, ...) {
    if (!globalConsole || !isLoggerActive) return;
    
    va_list args;
    va_start(args, fmt);
    NSString *content = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"HH:mm:ss"];
        NSString *ts = [df stringFromDate:[NSDate date]];
        
        globalConsole.text = [globalConsole.text stringByAppendingFormat:@"[%@] %@\n", ts, content];
        [globalConsole scrollRangeToVisible:NSMakeRange(globalConsole.text.length - 1, 1)];
    });
}

// --- MAIN MENU INTERFACE ---
@interface EnigmaMenu : UIView
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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if ([hit isDescendantOfView:self.blurPanel]) return hit;
    return nil; // Pass clicks to Snapchat
}

- (void)setupUI {
    // 1. Floating Button (The "Ω")
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(self.frame.size.width - 60, 100, 50, 50);
    btn.backgroundColor = [UIColor blackColor];
    btn.layer.cornerRadius = 25;
    btn.layer.borderWidth = 2;
    btn.layer.borderColor = THEME_COLOR.CGColor;
    [btn setTitle:@"Ω" forState:UIControlStateNormal];
    [btn setTitleColor:THEME_COLOR forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];

    // 2. The Main Panel (Hidden by default)
    self.blurPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 160, self.frame.size.width - 40, 400)];
    self.blurPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.blurPanel.layer.cornerRadius = 15;
    self.blurPanel.layer.borderColor = [UIColor grayColor].CGColor;
    self.blurPanel.layer.borderWidth = 1;
    self.blurPanel.hidden = YES;
    [self addSubview:self.blurPanel];

    // 3. Logger Header & Toggle (Matches your image)
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 20)];
    title.text = @"CLASS LOGGER";
    title.textColor = THEME_COLOR;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self.blurPanel addSubview:title];

    self.loggerToggle = [[UISwitch alloc] initWithFrame:CGRectMake(self.blurPanel.frame.size.width - 70, 10, 50, 30)];
    self.loggerToggle.onTintColor = THEME_COLOR;
    [self.loggerToggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self.blurPanel addSubview:self.loggerToggle];

    // 4. The Console (Green Text)
    self.consoleView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, self.blurPanel.frame.size.width - 30, 260)];
    self.consoleView.backgroundColor = [UIColor blackColor];
    self.consoleView.textColor = [UIColor greenColor];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:10];
    self.consoleView.editable = NO;
    self.consoleView.text = @"[SYSTEM] Ready. Waiting for class: SCONeTapLoginMultiAccountLandingPage...\n";
    self.consoleView.layer.cornerRadius = 8;
    self.consoleView.layer.borderWidth = 1;
    self.consoleView.layer.borderColor = [UIColor grayColor].CGColor;
    [self.blurPanel addSubview:self.consoleView];
    
    // Link global pointer so hooks can write to it
    globalConsole = self.consoleView;

    // 5. Action Buttons
    UIButton *copyBtn = [self makeBtn:@"[ COPY LOG ]" x:15 y:340];
    [copyBtn addTarget:self action:@selector(doCopy) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *clearBtn = [self makeBtn:@"[ CLEAR ]" x:self.blurPanel.frame.size.width/2 + 5 y:340];
    [clearBtn addTarget:self action:@selector(doClear) forControlEvents:UIControlEventTouchUpInside];
}

- (UIButton *)makeBtn:(NSString *)t x:(CGFloat)x y:(CGFloat)y {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(x, y, self.blurPanel.frame.size.width/2 - 20, 40);
    b.layer.borderWidth = 1;
    b.layer.borderColor = THEME_COLOR.CGColor;
    b.layer.cornerRadius = 6;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.blurPanel addSubview:b];
    return b;
}

- (void)toggleMenu { self.blurPanel.hidden = !self.blurPanel.hidden; }
- (void)toggleChanged:(UISwitch *)s { 
    isLoggerActive = s.on; 
    loggerWrite(isLoggerActive ? @"[*] LOGGER STARTED." : @"[*] LOGGER PAUSED.");
}
- (void)doCopy { [[UIPasteboard generalPasteboard] setString:self.consoleView.text]; }
- (void)doClear { self.consoleView.text = @""; }

@end

// --- THE REAL HOOKS (This is what fixes "logs nothing") ---

// We explicitly hook the class from your screenshot
%hook SCONeTapLoginMultiAccountLandingPage

// 1. Hook View Lifecycle (Logs when the screen appears)
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    loggerWrite(@"[EVENT] viewDidAppear: called");
    loggerWrite(@"[OBJ] SCONeTapLoginMultiAccountLandingPage");
}

- (void)viewDidLoad {
    %orig;
    loggerWrite(@"[EVENT] viewDidLoad: called (Screen Loaded)");
}

// 2. Hook Touch Events (Logs when you tap the screen)
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    UITouch *t = [touches anyObject];
    CGPoint p = [t locationInView:self.view];
    loggerWrite(@"[TOUCH] Tapped at {%.0f, %.0f}", p.x, p.y);
}

// 3. Hook generic interaction (Guessing common Snapchat method names)
// If these exist, they will log. If not, %hook usually ignores them safely in standard configs,
// but to be safe we stick to standard UIViewController methods above.

%end

// --- ENTRY POINT ---
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if(w) [w addSubview:[[EnigmaMenu alloc] initWithFrame:w.bounds]];
    });
}
