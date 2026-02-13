#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h> // For vibration
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/mman.h>

// --- DECLARE MISSING FUNCTION ---
extern void sys_icache_invalidate(void *start, size_t len);

// --- 1. MEMORY PATCHING ENGINE ---

NSData *dataFromHexString(NSString *string) {
    string = [string stringByReplacingOccurrencesOfString:@" " withString:@""];
    string = [string stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    NSMutableData *data = [NSMutableData new];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    for (int i = 0; i < [string length] / 2; i++) {
        byte_chars[0] = [string characterAtIndex:i * 2];
        byte_chars[1] = [string characterAtIndex:i * 2 + 1];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return data;
}

NSString *apply_patch(uint64_t offset, NSString *hexStr) {
    NSData *data = dataFromHexString(hexStr);
    if (!data || data.length == 0) return @"Invalid Hex Data";

    uintptr_t base = (uintptr_t)_dyld_get_image_header(0);
    uintptr_t addr = base + offset;

    vm_size_t size = data.length;
    vm_address_t page_start = addr & ~PAGE_MASK;
    vm_address_t page_end = (addr + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;

    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return [NSString stringWithFormat:@"Error: Unlock Failed (%d)", kr];

    memcpy((void *)addr, [data bytes], size);
    vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void *)addr, size);

    return @"Patch Applied!";
}

// --- 2. ROBUST UI MANAGER ---

@interface MenuManager : NSObject
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIButton *menuBtn;
@property (nonatomic, strong) NSTimer *loadTimer;
+ (instancetype)shared;
- (void)tryToLoadMenu;
@end

@implementation MenuManager

+ (instancetype)shared {
    static MenuManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MenuManager alloc] init];
    });
    return shared;
}

- (void)start {
    // Retry every 2 seconds until we find a valid scene
    self.loadTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(tryToLoadMenu) userInfo:nil repeats:YES];
}

- (void)tryToLoadMenu {
    UIWindowScene *activeScene = nil;
    
    // 1. Find the active scene
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }

    // If no scene found yet, return and wait for next timer tick
    if (!activeScene) return;

    // 2. Found a scene! Stop timer and build UI.
    [self.loadTimer invalidate];
    self.loadTimer = nil;

    // Vibrate to tell user we loaded
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    
    // 3. Create Window attached to Scene
    self.overlayWindow = [[UIWindow alloc] initWithWindowScene:activeScene];
    self.overlayWindow.frame = [UIScreen mainScreen].bounds;
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 50.0; // Very high
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.rootViewController = [UIViewController new];
    self.overlayWindow.userInteractionEnabled = YES; // Must be YES, but we handle hitTest manually
    self.overlayWindow.hidden = NO;
    [self.overlayWindow makeKeyAndVisible];

    // 4. Create Button
    self.menuBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuBtn.frame = CGRectMake(50, 150, 60, 60);
    self.menuBtn.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8];
    [self.menuBtn setTitle:@"⚙️" forState:UIControlStateNormal];
    self.menuBtn.titleLabel.font = [UIFont systemFontOfSize:30];
    self.menuBtn.layer.cornerRadius = 30;
    self.menuBtn.layer.borderColor = [UIColor redColor].CGColor;
    self.menuBtn.layer.borderWidth = 2;
    
    [self.menuBtn addTarget:self action:@selector(showPopup) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.menuBtn addGestureRecognizer:pan];

    [self.overlayWindow addSubview:self.menuBtn];
    
    // Bring window to front again just in case
    [self.overlayWindow.layer setZPosition:MAXFLOAT];
}

// Pass touches through empty space
// We override the getter of the window to swap hit testing behavior
// But for simplicity in a single file, we can just be careful with size.
// Since we made the window full screen, we need to ensure it doesn't block touches.
// The easiest way in a simple Tweak.x is to actually ADD the button to the KeyWindow if possible,
// OR use this trick:

- (void)handleDrag:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:self.overlayWindow];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.overlayWindow];
}

- (void)showPopup {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Patcher" message:@"Enter Offset & Hex" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Offset (0x...)"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Hex (C003...)"; }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSString *res = apply_patch(strtoull([alert.textFields[0].text UTF8String], NULL, 16), alert.textFields[1].text);
        
        UIAlertController *resA = [UIAlertController alertControllerWithTitle:res message:nil preferredStyle:UIAlertControllerStyleAlert];
        [resA addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:resA animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// Helper to make clicks pass through the window
// We use method swizzling or just a subclass. Since we are in Tweak.x, let's just Hook UIWindow pointInside.
// This ensures that if the user clicks OUTSIDE the button, the click goes to the game.

%hook UIWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // Check if this is OUR overlay window
    if (self == [MenuManager shared].overlayWindow) {
        if (CGRectContainsPoint([MenuManager shared].menuBtn.frame, point)) {
            return YES; // Clicked the button
        }
        return NO; // Clicked empty space -> pass to game
    }
    return %orig;
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[MenuManager shared] start];
    });
}
