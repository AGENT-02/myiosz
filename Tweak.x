#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h> // Required for "Dump" features

// --- CONFIG ---
static BOOL isMenuOpen = NO;

// --- UI COMPONENTS ---
@interface EnigmaOverlay : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UIButton *cornerBtn;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UITextView *terminalView; // The "Black Screen"
@property (nonatomic, strong) UITextField *inputField;  // Search bar
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
    // 1. Toggle Button
    self.cornerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cornerBtn.frame = CGRectMake(self.frame.size.width - 60, 80, 50, 50);
    self.cornerBtn.backgroundColor = [UIColor blackColor];
    self.cornerBtn.layer.cornerRadius = 25;
    self.cornerBtn.layer.borderColor = [UIColor greenColor].CGColor;
    self.cornerBtn.layer.borderWidth = 2;
    [self.cornerBtn setTitle:@"TERMINAL" forState:UIControlStateNormal];
    self.cornerBtn.titleLabel.font = [UIFont systemFontOfSize:8];
    [self.cornerBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.cornerBtn];

    // 2. The Menu (Terminal Style)
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 140, self.frame.size.width - 40, 400)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    self.menuView.layer.cornerRadius = 15;
    self.menuView.layer.borderColor = [UIColor greenColor].CGColor;
    self.menuView.layer.borderWidth = 1;
    self.menuView.hidden = YES;
    [self addSubview:self.menuView];

    // 3. Input Field (Class Name Search)
    self.inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 15, self.menuView.frame.size.width - 110, 35)];
    self.inputField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.inputField.textColor = [UIColor whiteColor];
    self.inputField.placeholder = @" Enter Class (e.g. UIDevice)";
    self.inputField.layer.cornerRadius = 8;
    self.inputField.delegate = self;
    [self.menuView addSubview:self.inputField];

    // 4. Dump Button
    UIButton *dumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    dumpBtn.frame = CGRectMake(self.menuView.frame.size.width - 85, 15, 70, 35);
    dumpBtn.backgroundColor = [UIColor greenColor];
    dumpBtn.layer.cornerRadius = 8;
    [dumpBtn setTitle:@"DUMP" forState:UIControlStateNormal];
    [dumpBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [dumpBtn addTarget:self action:@selector(runDump) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:dumpBtn];

    // 5. Terminal Output View (Scrolling logs)
    self.terminalView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, self.menuView.frame.size.width - 30, 325)];
    self.terminalView.backgroundColor = [UIColor blackColor];
    self.terminalView.textColor = [UIColor greenColor];
    self.terminalView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.terminalView.editable = NO;
    self.terminalView.text = @"[Enigma Shell v1.0] Ready...\nWaiting for input...\n";
    [self.menuView addSubview:self.terminalView];
}

- (void)toggleMenu {
    self.menuView.hidden = !self.menuView.hidden;
    if (!self.menuView.hidden) {
        [self.terminalView becomeFirstResponder]; // Little trick to focus
    } else {
        [self.inputField resignFirstResponder];
    }
}

// --- THE CORE DUMP LOGIC ---
// This uses Objective-C Runtime to inspect memory
- (void)runDump {
    [self.inputField resignFirstResponder];
    NSString *className = self.inputField.text;
    if (className.length == 0) return;

    [self logToTerminal:[NSString stringWithFormat:@"\n[*] Targeting Class: %@...", className]];

    Class targetClass = objc_getClass([className UTF8String]);
    if (!targetClass) {
        [self logToTerminal:@"[!] Error: Class not found in memory."];
        return;
    }

    // 1. Get Method List
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);

    [self logToTerminal:[NSString stringWithFormat:@"[+] Found %d methods:\n", methodCount]];

    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        SEL methodSelector = method_getName(method);
        NSString *methodName = NSStringFromSelector(methodSelector);
        
        // Print to our "Terminal"
        [self logToTerminal:[NSString stringWithFormat:@"   - %@", methodName]];
    }

    free(methods);
    [self logToTerminal:@"\n[✓] Dump Complete."];
}

- (void)logToTerminal:(NSString *)text {
    self.terminalView.text = [self.terminalView.text stringByAppendingFormat:@"%@\n", text];
    // Auto-scroll to bottom
    if(self.terminalView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.terminalView.text.length - 1, 1);
        [self.terminalView scrollRangeToVisible:bottom];
    }
}

// Close keyboard on Return
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}
@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (w) [w addSubview:[[EnigmaOverlay alloc] initWithFrame:w.bounds]];
    });
    %init;
}
