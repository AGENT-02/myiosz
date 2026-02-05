#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <substrate.h>

// --- 1. CONFIGURATION ---
#define PITCH_NORMAL 0.0
#define PITCH_GIRL 500.0
#define PITCH_KID 1000.0
#define PITCH_MONSTER -1200.0

// --- 2. GLOBALS ---
static AVAudioUnitTimePitch *globalPitchShifter = nil;
static BOOL isMenuOpen = NO;
static UIButton *activeButton = nil; // To track which button is "ON"

// --- 3. UI HELPER FUNCTIONS ---

// Update the button look to show if it is ON or OFF
void setButtonState(UIButton *btn, BOOL isOn) {
    UIButtonConfiguration *config = btn.configuration;
    
    if (isOn) {
        config.baseBackgroundColor = [UIColor systemGreenColor]; // Turn Green
        config.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        config.subtitle = @"Status: ON";
    } else {
        config.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15]; // Grey
        config.image = nil;
        config.subtitle = @"Tap to enable";
    }
    
    btn.configuration = config;
}

UIButton* createOptionButton(NSString *title, NSString *emoji, float pitchValue, UIStackView *stack) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Modern Configuration
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = [NSString stringWithFormat:@"%@  %@", emoji, title];
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.imagePadding = 10;
    config.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    btn.configuration = config;
    
    // Default State: OFF
    setButtonState(btn, NO);
    
    // Action Logic
    [btn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
        
        // 1. Update Audio
        if (globalPitchShifter) {
            globalPitchShifter.pitch = pitchValue;
            globalPitchShifter.bypass = (pitchValue == 0.0); // Bypass if Normal
        }
        
        // 2. Update UI (Radio Button Logic)
        if (activeButton && activeButton != btn) {
            setButtonState(activeButton, NO); // Turn off old button
        }
        
        setButtonState(btn, YES); // Turn on new button
        activeButton = btn;
        
        // Haptics
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [feedback impactOccurred];
        
        NSLog(@"[Enigma] Selected: %@ (Pitch: %f)", title, pitchValue);
        
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [stack addArrangedSubview:btn];
    return btn;
}

void showEnigmaMenu() {
    if (isMenuOpen) return;
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    isMenuOpen = YES;

    // Blur Background
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *overlay = [[UIVisualEffectView alloc] initWithEffect:blur];
    overlay.frame = keyWindow.bounds;
    overlay.alpha = 0;
    [keyWindow addSubview:overlay];
    
    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 450)]; // Taller for subtitles
    card.center = keyWindow.center;
    card.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    card.layer.cornerRadius = 24;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    card.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [overlay.contentView addSubview:card];

    // Header
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, 320, 30)];
    header.text = @"ENIGMA STUDIO";
    header.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    header.textColor = [UIColor whiteColor];
    header.textAlignment = NSTextAlignmentCenter;
    [card addSubview:header];

    // Options Stack
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(30, 80, 260, 340)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:stack];

    // Add Buttons
    createOptionButton(@"Normal", @"👤", PITCH_NORMAL, stack);
    createOptionButton(@"Girl Voice", @"🎀", PITCH_GIRL, stack);
    createOptionButton(@"Chipmunk", @"🎈", PITCH_KID, stack);
    createOptionButton(@"Monster", @"👹", PITCH_MONSTER, stack);

    // Close Gesture
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(removeFromSuperview)];
    [overlay addGestureRecognizer:tap];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        isMenuOpen = NO; 
    });
    
    // Animate In
    [UIView animateWithDuration:0.3 animations:^{
        overlay.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    }];
}

// --- 4. AUDIO HOOK (AGGRESSIVE MODE) ---
%hook AVAudioEngine

- (BOOL)startAndReturnError:(NSError **)outError {
    NSLog(@"[Enigma] Audio Engine Starting...");
    
    // 1. Get Input Node (Mic)
    AVAudioInputNode *input = [self inputNode];
    
    // 2. Setup Pitch Shifter
    AVAudioUnitTimePitch *shifter = [[AVAudioUnitTimePitch alloc] init];
    shifter.pitch = PITCH_NORMAL; 
    shifter.bypass = YES; // Start bypassed
    globalPitchShifter = shifter; 
    
    // 3. Attach Node
    [self attachNode:shifter];
    
    // 4. CONNECT: Input -> Shifter -> MainMixer
    // We force the format to match the input hardware format
    AVAudioFormat *format = [input inputFormatForBus:0];
    
    // Disconnect any existing connections first (Safety)
    [self disconnectNodeInput:input];
    
    // Reconnect Chain
    [self connect:input to:shifter format:format];
    [self connect:shifter to:[self mainMixerNode] format:format];
    
    NSLog(@"[Enigma] Audio Graph Re-Wired Successfully!");
    
    return %orig;
}

// Hook reset to ensure we stay attached if the app clears the graph
- (void)reset {
    %orig;
    NSLog(@"[Enigma] Engine Reset - Re-initializing might be needed.");
}

%end

// --- 5. UI INJECTION ---
%hook UIWindow

- (void)layoutSubviews {
    %orig;
    if (!self.isKeyWindow) return;
    if ([self viewWithTag:8888]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self viewWithTag:8888]) return;

        UIButton *entryBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        entryBtn.frame = CGRectMake(self.frame.size.width - 70, 130, 50, 50);
        entryBtn.tag = 8888;
        entryBtn.backgroundColor = [UIColor systemIndigoColor];
        entryBtn.layer.cornerRadius = 25;
        
        // Shadow
        entryBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        entryBtn.layer.shadowOpacity = 0.5;
        entryBtn.layer.shadowOffset = CGSizeMake(0, 5);

        [entryBtn setTitle:@"🎤" forState:UIControlStateNormal];
        
        [entryBtn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
             isMenuOpen = NO;
             showEnigmaMenu(); 
        }] forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:entryBtn];
        [self bringSubviewToFront:entryBtn];
    });
}

%end

%ctor {
    NSLog(@"[Enigma] Loaded.");
}
