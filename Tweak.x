#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <substrate.h>
#import <math.h>

// ==========================================
// PART 1: AUDIO PROCESSING (THE ROBOT EFFECT)
// ==========================================

// Global Settings
static BOOL gEnabled = YES;       // Default to ON so you hear it immediately
static float gRobotFreq = 400.0;  // 400Hz = Deep Robot Voice

// Pointer to the original system function
OSStatus (*orig_AudioUnitRender)(AudioUnit unit, 
                                 AudioUnitRenderActionFlags *ioActionFlags, 
                                 const AudioTimeStamp *inTimeStamp, 
                                 UInt32 inBusNumber, 
                                 UInt32 inNumberFrames, 
                                 AudioBufferList *ioData);

// OUR INTERCEPTOR FUNCTION
OSStatus hook_AudioUnitRender(AudioUnit unit, 
                              AudioUnitRenderActionFlags *ioActionFlags, 
                              const AudioTimeStamp *inTimeStamp, 
                              UInt32 inBusNumber, 
                              UInt32 inNumberFrames, 
                              AudioBufferList *ioData) {
    
    // 1. Let the system capture the real microphone audio first
    OSStatus status = orig_AudioUnitRender(unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
    
    // 2. If it failed, or we are disabled, just return
    if (status != noErr || !gEnabled) return status;
    
    // 3. APPLY THE EFFECT (Ring Modulation)
    // We multiply the audio by a Sine Wave. This creates a "Dalek" robot effect.
    // It works even if Discord tries to cancel noise.
    
    static double phase = 0.0;
    double phaseIncrement = 2.0 * 3.14159 * gRobotFreq / 48000.0; // Assume 48kHz
    
    // Loop through all audio buffers (Left/Right channels)
    for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
        AudioBuffer buffer = ioData->mBuffers[i];
        if (!buffer.mData) continue;
        
        SInt16 *samples = (SInt16 *)buffer.mData; // Raw Audio Samples
        UInt32 count = inNumberFrames;
        
        for (UInt32 j = 0; j < count; j++) {
            // Read sample
            float raw = (float)samples[j];
            
            // Generate Sine Wave
            float modulator = sin(phase);
            
            // MATH: Multiply them together
            samples[j] = (SInt16)(raw * modulator);
            
            // Advance the sine wave
            phase += phaseIncrement;
            if (phase > 6.28318) phase -= 6.28318;
        }
    }
    
    return status;
}

// ==========================================
// PART 2: THE MENU UI
// ==========================================

static BOOL isMenuOpen = NO;
static UIButton *activeButton = nil;

// Helper to make buttons look nice
void setButtonState(UIButton *btn, BOOL isOn) {
    UIButtonConfiguration *config = btn.configuration;
    if (isOn) {
        config.baseBackgroundColor = [UIColor systemGreenColor];
        config.image = [UIImage systemImageNamed:@"waveform.path.ecg"];
    } else {
        config.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        config.image = nil;
    }
    btn.configuration = config;
}

void showEnigmaMenu() {
    if (isMenuOpen) return;
    
    // Modern Window Finder (iOS 15 - iOS 26 Compatible)
    UIWindow *targetWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) {
                    targetWindow = w;
                    break;
                }
            }
        }
        if (targetWindow) break;
    }
    if (!targetWindow) return; // Safety check

    isMenuOpen = YES;

    // 1. Blur Background
    UIVisualEffectView *overlay = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    overlay.frame = targetWindow.bounds;
    overlay.alpha = 0;
    [targetWindow addSubview:overlay];
    
    // 2. Menu Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 380)];
    card.center = targetWindow.center;
    card.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    card.layer.cornerRadius = 24;
    card.layer.borderColor = [UIColor whiteColor].CGColor;
    card.layer.borderWidth = 1;
    [overlay.contentView addSubview:card];
    
    // 3. Header
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, 320, 30)];
    lbl.text = @"ENIGMA: DISCORD MODE";
    lbl.textColor = [UIColor whiteColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    [card addSubview:lbl];

    // 4. Button Stack
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(30, 80, 260, 260)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:stack];

    // Helper Block to add buttons
    void (^addBtn)(NSString*, NSString*, float) = ^(NSString* name, NSString* icon, float freq) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *conf = [UIButtonConfiguration filledButtonConfiguration];
        conf.title = [NSString stringWithFormat:@"%@  %@", icon, name];
        btn.configuration = conf;
        
        // Initial State
        setButtonState(btn, (gEnabled && gRobotFreq == freq));
        
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action){
            if (freq == 0) {
                gEnabled = NO; // Turn Off
            } else {
                gEnabled = YES;
                gRobotFreq = freq;
            }
            
            // Visual Update
            if (activeButton) setButtonState(activeButton, NO);
            setButtonState(btn, YES);
            activeButton = btn;
            
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [stack addArrangedSubview:btn];
    };

    // Add the Options
    addBtn(@"Normal Voice", @"👤", 0.0);
    addBtn(@"Deep Robot", @"🤖", 400.0);
    addBtn(@"High Alien", @"👽", 800.0);
    addBtn(@"Glitch Mode", @"👾", 1200.0);

    // 5. Close Logic
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(removeFromSuperview)];
    [overlay addGestureRecognizer:tap];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ isMenuOpen = NO; });

    [UIView animateWithDuration:0.3 animations:^{ overlay.alpha = 1; }];
}

// ==========================================
// PART 3: INJECTION HOOKS
// ==========================================

%hook UIWindow

- (void)layoutSubviews {
    %orig;
    
    // Only inject into the main window
    if (!self.isKeyWindow) return;
    
    // Prevent duplicates
    if ([self viewWithTag:9999]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self viewWithTag:9999]) return;
        
        // Create the Floating "Alien" Button
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(self.frame.size.width - 70, 160, 50, 50);
        btn.tag = 9999;
        btn.backgroundColor = [UIColor systemIndigoColor];
        btn.layer.cornerRadius = 25;
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        
        [btn setTitle:@"👽" forState:UIControlStateNormal];
        
        // Open Menu on Tap
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action){
            isMenuOpen = NO;
            showEnigmaMenu();
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [self addSubview:btn];
        [self bringSubviewToFront:btn];
    });
}

%end

// ==========================================
// PART 4: CONSTRUCTOR (LOADER)
// ==========================================

%ctor {
    NSLog(@"[Enigma] Loading System Audio Hook...");
    
    // Hook the Low-Level AudioUnitRender function
    MSHookFunction(
        (void *)AudioUnitRender,
        (void *)hook_AudioUnitRender,
        (void **)&orig_AudioUnitRender
    );
}
