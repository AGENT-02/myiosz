#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <substrate.h>
#import <math.h>

// --- CONFIGURATION ---
// Simple "Robot" frequency. 
// 500 = Deep Robot
// 1000 = High Alien
static float ROBOT_FREQ = 0.0; 
static BOOL IS_ENABLED = NO;

// --- UI HELPER: BUTTON STATE ---
void setButtonState(UIButton *btn, BOOL isOn) {
    UIButtonConfiguration *config = btn.configuration;
    if (isOn) {
        config.baseBackgroundColor = [UIColor systemGreenColor];
        config.image = [UIImage systemImageNamed:@"waveform.path.ecg"];
        config.subtitle = @"Active";
    } else {
        config.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        config.image = nil;
        config.subtitle = @"Tap to activate";
    }
    btn.configuration = config;
}

// --- CORE AUDIO HOOK (THE HARD PART) ---
// This is the function pointer to the original AudioUnitRender
OSStatus (*orig_AudioUnitRender)(AudioUnit unit, 
                                 AudioUnitRenderActionFlags *ioActionFlags, 
                                 const AudioTimeStamp *inTimeStamp, 
                                 UInt32 inBusNumber, 
                                 UInt32 inNumberFrames, 
                                 AudioBufferList *ioData);

// Our Replacement Function
OSStatus hook_AudioUnitRender(AudioUnit unit, 
                              AudioUnitRenderActionFlags *ioActionFlags, 
                              const AudioTimeStamp *inTimeStamp, 
                              UInt32 inBusNumber, 
                              UInt32 inNumberFrames, 
                              AudioBufferList *ioData) {
    
    // 1. Call Original (Let the mic fill the buffer)
    OSStatus result = orig_AudioUnitRender(unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
    
    // 2. If it failed or we are turned off, just return
    if (result != noErr || !IS_ENABLED || ROBOT_FREQ == 0.0) return result;
    
    // 3. MODIFY THE AUDIO (DSP)
    // We are now inside the raw audio loop. This runs 100s of times a second.
    // We apply a "Ring Modulator" effect (Robot Voice).
    
    static double phase = 0.0;
    double phaseIncrement = 2.0 * M_PI * ROBOT_FREQ / 44100.0; // Assuming 44.1kHz
    
    for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
        AudioBuffer buffer = ioData->mBuffers[i];
        SInt16 *frameBuffer = (SInt16 *)buffer.mData; // standard 16-bit audio
        
        // Loop through every sample in this packet
        for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
            if (buffer.mDataByteSize > 0) {
                // Modulate: Sample * SineWave
                float signal = frameBuffer[frame];
                float modulator = sin(phase);
                
                // Mix them
                frameBuffer[frame] = (SInt16)(signal * modulator);
                
                // Advance the sine wave
                phase += phaseIncrement;
                if (phase > 2.0 * M_PI) phase -= 2.0 * M_PI;
            }
        }
    }
    
    return result;
}

// --- UI HELPERS ---
static BOOL isMenuOpen = NO;
static UIButton *activeButton = nil;

void showEnigmaMenu() {
    if (isMenuOpen) return;
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    isMenuOpen = YES;

    // Blur
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *overlay = [[UIVisualEffectView alloc] initWithEffect:blur];
    overlay.frame = keyWindow.bounds;
    overlay.alpha = 0;
    [keyWindow addSubview:overlay];
    
    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 400)];
    card.center = keyWindow.center;
    card.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    card.layer.cornerRadius = 24;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    card.layer.borderWidth = 1;
    [overlay.contentView addSubview:card];

    // Header
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, 320, 30)];
    header.text = @"ENIGMA: DISCORD MODE";
    header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    header.textColor = [UIColor whiteColor];
    header.textAlignment = NSTextAlignmentCenter;
    [card addSubview:header];

    // Stack
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(30, 80, 260, 280)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:stack];

    // Button Creator
    void (^addBtn)(NSString*, NSString*, float) = ^(NSString* title, NSString* emoji, float freq) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = [NSString stringWithFormat:@"%@  %@", emoji, title];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        btn.configuration = config;
        
        setButtonState(btn, NO);
        
        [btn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
            // Update Logic
            if (freq == 0) {
                IS_ENABLED = NO;
                ROBOT_FREQ = 0;
                setButtonState(btn, YES); // Highlight "Normal"
            } else {
                IS_ENABLED = YES;
                ROBOT_FREQ = freq;
                setButtonState(btn, YES);
            }
            
            // UI Toggle
            if (activeButton && activeButton != btn) setButtonState(activeButton, NO);
            activeButton = btn;
            
            NSLog(@"[Enigma] Frequency set to: %f", freq);
            
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [stack addArrangedSubview:btn];
    };

    addBtn(@"Normal Voice", @"👤", 0.0);
    addBtn(@"Deep Robot", @"🤖", 400.0);
    addBtn(@"Alien / Dalek", @"👽", 800.0);
    addBtn(@"Glitch Noise", @"👾", 1200.0);

    // Close
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(removeFromSuperview)];
    [overlay addGestureRecognizer:tap];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ isMenuOpen = NO; });
    
    [UIView animateWithDuration:0.3 animations:^{ overlay.alpha = 1; }];
}

// --- FORCE INJECT BUTTON ---
%hook UIWindow
- (void)layoutSubviews {
    %orig;
    if (!self.isKeyWindow || [self viewWithTag:9999]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self viewWithTag:9999]) return;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(self.frame.size.width - 60, 150, 50, 50);
        btn.tag = 9999;
        btn.backgroundColor = [UIColor systemRedColor]; // Red for "Live"
        btn.layer.cornerRadius = 25;
        [btn setTitle:@"🤖" forState:UIControlStateNormal];
        
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action){
            isMenuOpen = NO;
            showEnigmaMenu();
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [self addSubview:btn];
        [self bringSubviewToFront:btn];
    });
}
%end

// --- CONSTRUCTOR ---
%ctor {
    NSLog(@"[Enigma] Loading CoreAudio Hook...");
    
    // We must hook AudioUnitRender. This is found in AudioToolbox.
    // MSImageRef ref = MSGetImageByName("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox");
    // void *symbol = MSFindSymbol(ref, "_AudioUnitRender");
    
    // Easier way with MSHookFunction if we link AudioToolbox
    MSHookFunction(
        (void *)AudioUnitRender, 
        (void *)hook_AudioUnitRender, 
        (void **)&orig_AudioUnitRender
    );
}
