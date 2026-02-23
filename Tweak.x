#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/mman.h>

// --- KERNEL & MEMORY API DEFINITIONS ---
#ifdef __cplusplus
extern "C" {
#endif
    kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);
    kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
#ifdef __cplusplus
}
#endif

// --- STATE MANAGEMENT ---
static BOOL isAutoPlayEnabled = NO;

// --- MEMORY ENGINE ---
uintptr_t get_active_base() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *nsName = [NSString stringWithUTF8String:name];
        NSString *fileName = [nsName lastPathComponent];
        // Target the 8-Ball Pool specific binary or engine framework
        if ([fileName containsString:@"UnityFramework"] || [fileName containsString:@"8Ball"]) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return (uintptr_t)_dyld_get_image_header(0);
}

kern_return_t safe_write(uintptr_t address, void *data, size_t size) {
    mach_port_t task = mach_task_self();
    vm_address_t page_start = address & ~PAGE_MASK;
    vm_address_t page_end = (address + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;

    kern_return_t kr = mach_vm_protect(task, page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) return kr;

    kr = mach_vm_write(task, address, (vm_offset_t)data, (mach_msg_type_number_t)size);
    if (kr != KERN_SUCCESS) memcpy((void *)address, data, size);

    mach_vm_protect(task, page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return KERN_SUCCESS;
}

NSData *hexToBytes(NSString *str) {
    str = [str stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSMutableData *data = [NSMutableData data];
    unsigned char byte;
    char chars[3] = {'\0', '\0', '\0'};
    for (int i = 0; i < [str length] / 2; i++) {
        chars[0] = [str characterAtIndex:i*2];
        chars[1] = [str characterAtIndex:i*2+1];
        byte = strtol(chars, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

// --- UI & ORIENTATION ---
@interface LandscapeController : UIViewController @end
@implementation LandscapeController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

// --- MOD MENU ---
@interface ModMenu : NSObject
@property (nonatomic, strong) PassThroughWindow *window;
@property (nonatomic, strong) UIButton *btn;
+ (instancetype)shared;
@end

@implementation ModMenu
+ (instancetype)shared {
    static ModMenu *m; static dispatch_once_t t;
    dispatch_once(&t, ^{ m = [ModMenu new]; }); return m;
}

- (void)setup {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene*)s; break; }
    }
    if (!scene) { [self performSelector:@selector(setup) withObject:nil afterDelay:1.0]; return; }

    self.window = [[PassThroughWindow alloc] initWithWindowScene:scene];
    self.window.frame = UIScreen.mainScreen.bounds;
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.rootViewController = [LandscapeController new];
    self.window.hidden = NO;

    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(100, 100, 55, 55);
    self.btn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    [self.btn setTitle:@"🎱" forState:UIControlStateNormal];
    self.btn.layer.cornerRadius = 27.5;
    [self.btn addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:self.btn];
}

- (void)openMenu {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"POOL AUTOPLAY" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *toggleText = isAutoPlayEnabled ? @"🔴 Disable Auto-Play" : @"🟢 Enable Auto-Play";
    
    [ac addAction:[UIAlertAction actionWithTitle:toggleText style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        isAutoPlayEnabled = !isAutoPlayEnabled;
        
        // Example: If enabling auto-play also requires forcing long lines via memory patch
        if (isAutoPlayEnabled) {
            uint64_t longLinesOffset = 0x2A3B4C0; // Mock offset for 8-Ball pool lines
            NSData *hex = hexToBytes(@"200080D2C0035FD6"); // MOV X0, #1; RET
            safe_write(get_active_base() + longLinesOffset, (void *)[hex bytes], [hex length]);
        }
        
        NSString *res = isAutoPlayEnabled ? @"✅ Auto-Play Active!" : @"⏸ Auto-Play Paused";
        UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Status" message:res preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self.window.rootViewController presentViewController:r animated:YES completion:nil];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:ac animated:YES completion:nil];
}
@end

// --- 8-BALL POOL AUTO-PLAY HOOK ---
%hook GameController

- (void)onFrameUpdate:(id)frameData {
    %orig;

    if (isAutoPlayEnabled) {
        // Validation: Check if the "Green Hole" indicator is active for the current target
        BOOL isGreenHoleTargeted = [self performSelector:NSSelectorFromString(@"isTargetPocketConfirmed")]; 

        if (isGreenHoleTargeted) {
            static dispatch_once_t executionToken;
            dispatch_once(&executionToken, ^{
                
                // Actuator: Simulate the shot with calculated power
                [self performSelector:@selector(executeShotWithPower:) withObject:@(0.85)]; 
                
                // Reset token after the turn is complete
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    executionToken = 0; 
                });
            });
        }
    }
}
%end

// --- INITIALIZATION ---
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ModMenu shared] setup];
    });
}
