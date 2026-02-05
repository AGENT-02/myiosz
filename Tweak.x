#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <substrate.h>

// --- 1. CONFIGURATION ---
#define PITCH_NORMAL 0.0
#define PITCH_GIRL 500.0   // +500 cents
#define PITCH_KID 1000.0   // +1000 cents (Chipmunk)
#define PITCH_MONSTER -1200.0 // -1 Octave (Deep)

// --- 2. GLOBALS ---
// We keep a reference to the active pitch node so the UI can update it instantly
static AVAudioUnitTimePitch *globalPitchShifter = nil;
static BOOL isMenuOpen = NO;

// --- 3. UI HELPER FUNCTIONS ---

// Helper to create the fancy buttons inside the menu
UIButton* createOptionButton(NSString *title, NSString *emoji, float pitchValue, UIStackView *stack) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Modern iOS Button Configuration (iOS 15+ style)
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = [NSString stringWithFormat:@"%@  %@", emoji, title];
    config.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15]; // Glassy background
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.contentInsets = NSDirectionalEdgeInsetsMake(12, 10, 12, 10);
    btn.configuration = config;
    
    // Action Logic
    [btn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
        if (globalPitchShifter) {
            globalPitchShifter.pitch = pitchValue;
            
            // Haptic Feedback (Vibration)
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [feedback impactOccurred];
            
            NSLog(@"[Enigma] Pitch changed to: %f", pitchValue);
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [stack addArrangedSubview:btn];
    return btn;
}

// Function to show the "Glass" Menu
void showEnigmaMenu() {
    if (isMenuOpen) return;
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    isMenuOpen = YES;

    // A. Full Screen Blur Overlay
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *overlay = [[UIVisualEffectView alloc] initWithEffect:blur];
    overlay.frame = keyWindow.bounds;
    overlay.alpha = 0;
    [keyWindow addSubview:overlay];
    
    // B. The Menu Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 400)];
    card.center = keyWindow.center;
    card.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95]; // Dark Grey
    card.layer.cornerRadius = 24;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    
    // Shadow for depth
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.5;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    card.layer.shadowRadius = 20;
    
    card.transform = CGAffineTransformMakeScale(0.8, 0.8); // Start smaller for pop animation
    [overlay.contentView addSubview:card];

    // C. Header Text
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, 320, 30)];
    header.text = @"ENIGMA VOICE";
    header.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    header.textColor = [UIColor whiteColor];
    header.textAlignment = NSTextAlignmentCenter;
    [card addSubview:header];

    // D. Options Stack
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(30, 80, 260, 280)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:stack];

    // Add Buttons
    createOptionButton(@"Normal", @"👤", PITCH_NORMAL, stack);
    createOptionButton(@"Girl", @"🎀", PITCH_GIRL, stack);
    createOptionButton(@"Kid", @"🎈", PITCH_KID, stack);
    createOptionButton(@"Monster", @"👹", PITCH_MONSTER, stack);

    // E. Close Logic (Tap background to close)
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(removeFromSuperview)];
    [overlay addGestureRecognizer:tap];
    
    // Reset the "isMenuOpen" flag when the view is removed
    // (In a real app, we'd subclass or use a delegate, but this is fine for a demo)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        isMenuOpen = NO; 
    });
    
    // Animate In
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        overlay.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

// --- 4. AUDIO HOOK ---
%hook AVAudioEngine

- (BOOL)startAndReturnError:(NSError **)outError {
    // 1. Intercept Audio Engine Start
    AVAudioInputNode *input = [self inputNode];
    
    // 2. Setup Pitch Node
    AVAudioUnitTimePitch *shifter = [[AVAudioUnitTimePitch alloc] init];
    shifter.pitch = PITCH_NORMAL; // Default
    globalPitchShifter = shifter; // Save to global for the UI to access
    
    [self attachNode:shifter];
    
    // 3. Re-route the graph: Input -> Shifter -> Mixer
    AVAudioFormat *format = [input inputFormatForBus:0];
    [self connect:input to:shifter format:format];
    [self connect:shifter to:[self mainMixerNode] format:format];
    
    // 4. Resume normal startup
    return %orig;
}

%end

// --- 5. UI INJECTION HOOK (AGGRESSIVE) ---
%hook UIWindow

- (void)layoutSubviews {
    %orig; // Let the window do its normal layout work

    // FILTER: Only add to the main interactive window
    if (!self.isKeyWindow) return;

    // CHECK: Does the button already exist? If yes, stop here.
    if ([self viewWithTag:8888]) return;

    // SAFETY: Ensure we are on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // DOUBLE CHECK: (Concurrency safety)
        if ([self viewWithTag:8888]) return;

        // Create Floating Entry Button
        UIButton *entryBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // Position: Top Right, slightly lower to avoid Dynamic Island/Notch
        entryBtn.frame = CGRectMake(self.frame.size.width - 70, 130, 50, 50);
        entryBtn.tag = 8888; // Unique Tag
        entryBtn.backgroundColor = [UIColor systemIndigoColor];
        entryBtn.layer.cornerRadius = 25;
        
        // Add "mic" symbol
        [entryBtn setTitle:@"🎤" forState:UIControlStateNormal];
        
        // Shadow (Make it pop)
        entryBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        entryBtn.layer.shadowOpacity = 0.5;
        entryBtn.layer.shadowOffset = CGSizeMake(0, 5);
        entryBtn.layer.shadowRadius = 5;

        // Add Action
        [entryBtn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
             // Reset menu flag just in case
             isMenuOpen = NO;
             showEnigmaMenu(); 
        }] forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:entryBtn];
        [self bringSubviewToFront:entryBtn];
        
        NSLog(@"[Enigma] Button FORCE INJECTED into UIWindow.");
    });
}

%end

// --- 6. CONSTRUCTOR ---
%ctor {
    NSLog(@"[Enigma] Dylib Loaded Successfully.");
}
