#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <substrate.h>
#import <mach/mach.h>
#import <pthread.h>

// ==========================================
// PART 1: CIRCULAR BUFFER DSP (THE COMPLEX PART)
// ==========================================

#define BUFFER_SIZE 32768 // Large buffer to hold audio
#define MAX_CHANNELS 2

typedef struct {
    float buffer[BUFFER_SIZE * MAX_CHANNELS];
    int writeIndex;
    float readIndex;
    int size;
} CircularBuffer;

// Global State
static CircularBuffer gBuffer;
static float gPitchRatio = 1.0; // 1.0 = Normal, 1.5 = Girl, 0.7 = Monster
static BOOL gEnabled = NO;
static pthread_mutex_t gAudioMutex;

void InitBuffer() {
    memset(gBuffer.buffer, 0, sizeof(gBuffer.buffer));
    gBuffer.writeIndex = 0;
    gBuffer.readIndex = 0;
    gBuffer.size = BUFFER_SIZE;
    pthread_mutex_init(&gAudioMutex, NULL);
}

// Simple Linear Interpolation for smooth pitch shifting
float ReadBuffer(float index) {
    int i = (int)index;
    float frac = index - i;
    int nextI = (i + 1) % gBuffer.size;
    
    float a = gBuffer.buffer[i];
    float b = gBuffer.buffer[nextI];
    return a + frac * (b - a);
}

// ==========================================
// PART 2: THE HIJACKER (AUDIO UNIT HOOK)
// ==========================================

// Pointer to Discord's Original Callback
AURenderCallbackStruct originalCallbackStruct;
AudioUnit gInputUnit = NULL;

// OUR CUSTOM CALLBACK (Runs 100x per second on the audio thread)
OSStatus MyRenderCallback(void *inRefCon, 
                          AudioUnitRenderActionFlags *ioActionFlags, 
                          const AudioTimeStamp *inTimeStamp, 
                          UInt32 inBusNumber, 
                          UInt32 inNumberFrames, 
                          AudioBufferList *ioData) {
    
    // 1. Let Discord fetch the REAL microphone data first
    OSStatus status = originalCallbackStruct.inputProc(
        originalCallbackStruct.inputProcRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    );

    // If failed or disabled, exit early
    if (status != noErr || !gEnabled || gPitchRatio == 1.0) return status;

    // 2. DSP PROCESSING (Pitch Shift via Resampling)
    pthread_mutex_lock(&gAudioMutex);
    
    SInt16 *samples = (SInt16 *)ioData->mBuffers[0].mData;
    int count = inNumberFrames;
    
    // A. WRITE Step: Put real mic data into our circular buffer
    for (int i = 0; i < count; i++) {
        // Convert SInt16 to Float for processing
        gBuffer.buffer[gBuffer.writeIndex] = (float)samples[i] / 32768.0f;
        gBuffer.writeIndex = (gBuffer.writeIndex + 1) % gBuffer.size;
    }
    
    // B. READ Step: Pull data out at a different speed (The Pitch Shift)
    for (int i = 0; i < count; i++) {
        float val = ReadBuffer(gBuffer.readIndex);
        
        // Convert back to SInt16
        if (val > 1.0f) val = 1.0f;
        if (val < -1.0f) val = -1.0f;
        samples[i] = (SInt16)(val * 32767.0f);
        
        // Advance read head by Pitch Ratio
        // > 1.0 = Faster (High Pitch)
        // < 1.0 = Slower (Low Pitch)
        gBuffer.readIndex += gPitchRatio;
        
        // Wrap around logic
        if (gBuffer.readIndex >= gBuffer.size) {
            gBuffer.readIndex -= gBuffer.size;
        }
    }
    
    // C. Anti-Drift (Prevent echo/delay buildup)
    // If read pointer gets too far from write pointer, snap it back
    int dist = gBuffer.writeIndex - (int)gBuffer.readIndex;
    if (dist < 0) dist += gBuffer.size;
    
    if (dist > 2048) { // If lag is > 40ms, jump forward
        gBuffer.readIndex = gBuffer.writeIndex - 1024; 
        if (gBuffer.readIndex < 0) gBuffer.readIndex += gBuffer.size;
    }

    pthread_mutex_unlock(&gAudioMutex);
    return status;
}

// Hook AudioUnitSetProperty to catch when Discord sets up the mic
OSStatus (*orig_AudioUnitSetProperty)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);

OSStatus hook_AudioUnitSetProperty(AudioUnit unit, AudioUnitPropertyID propID, AudioUnitScope scope, AudioUnitElement element, const void *data, UInt32 dataSize) {
    
    // Check if the app is setting an Input Callback (Recording)
    if (propID == kAudioOutputUnitProperty_SetInputCallback) {
        NSLog(@"[Enigma] DETECTED MICROPHONE CALLBACK SETTING!");
        
        // 1. Save the original callback (Discord's function)
        AURenderCallbackStruct *callback = (AURenderCallbackStruct *)data;
        originalCallbackStruct = *callback;
        
        // 2. Create a new struct pointing to OUR function
        AURenderCallbackStruct newCallback;
        newCallback.inputProc = MyRenderCallback;
        newCallback.inputProcRefCon = NULL;
        
        // 3. Save reference to the unit
        gInputUnit = unit;
        
        // 4. Pass OUR callback to the system
        return orig_AudioUnitSetProperty(unit, propID, scope, element, &newCallback, sizeof(newCallback));
    }
    
    return orig_AudioUnitSetProperty(unit, propID, scope, element, data, dataSize);
}


// ==========================================
// PART 3: THE UI (MENU)
// ==========================================

// Global UI State
static BOOL isMenuOpen = NO;
static UIButton *activeButton = nil;

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
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    isMenuOpen = YES;
    
    // Overlay
    UIVisualEffectView *overlay = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    overlay.frame = keyWindow.bounds;
    overlay.alpha = 0;
    [keyWindow addSubview:overlay];
    
    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 420)];
    card.center = keyWindow.center;
    card.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    card.layer.cornerRadius = 24;
    card.layer.borderColor = [UIColor whiteColor].CGColor;
    card.layer.borderWidth = 1;
    [overlay.contentView addSubview:card];
    
    // Title
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 320, 40)];
    lbl.text = @"ENIGMA: DISCORD MODE";
    lbl.textColor = [UIColor whiteColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [card addSubview:lbl];

    // Stack
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(30, 80, 260, 300)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:stack];

    // Helper to add buttons
    void (^addBtn)(NSString*, NSString*, float) = ^(NSString* name, NSString* icon, float ratio) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *conf = [UIButtonConfiguration filledButtonConfiguration];
        conf.title = [NSString stringWithFormat:@"%@  %@", icon, name];
        btn.configuration = conf;
        setButtonState(btn, NO);
        
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action){
            gPitchRatio = ratio;
            gEnabled = (ratio != 1.0);
            
            if (activeButton) setButtonState(activeButton, NO);
            setButtonState(btn, YES);
            activeButton = btn;
            
            NSLog(@"[Enigma] Ratio Set: %f", ratio);
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [stack addArrangedSubview:btn];
    };

    addBtn(@"Normal", @"👤", 1.0);
    addBtn(@"Girl Voice", @"🎀", 1.3);     // 30% Faster
    addBtn(@"Chipmunk", @"🐿", 1.6);      // 60% Faster
    addBtn(@"Monster", @"👹", 0.7);       // 30% Slower
    addBtn(@"Demon", @"💀", 0.5);         // 50% Slower

    // Close Handler
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(removeFromSuperview)];
    [overlay addGestureRecognizer:tap];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ isMenuOpen = NO; });

    [UIView animateWithDuration:0.3 animations:^{ overlay.alpha = 1; }];
}

// ==========================================
// PART 4: FORCE UI & INIT
// ==========================================

%hook UIWindow
- (void)layoutSubviews {
    %orig;
    if (!self.isKeyWindow || [self viewWithTag:7777]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self viewWithTag:7777]) return;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(self.frame.size.width - 60, 160, 50, 50);
        btn.tag = 7777;
        btn.backgroundColor = [UIColor systemGreenColor];
        btn.layer.cornerRadius = 25;
        [btn setTitle:@"👽" forState:UIControlStateNormal];
        
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action){
            isMenuOpen = NO;
            showEnigmaMenu();
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [self addSubview:btn];
        [self bringSubviewToFront:btn];
    });
}
%end

%ctor {
    NSLog(@"[Enigma] Loading CORE AUDIO INTERCEPTOR...");
    InitBuffer();
    
    MSHookFunction(
        (void *)AudioUnitSetProperty,
        (void *)hook_AudioUnitSetProperty,
        (void **)&orig_AudioUnitSetProperty
    );
}
