#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/mman.h>

// --- FIX FOR COMPILER ERRORS ---
#ifdef __cplusplus
extern "C" {
#endif
    kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);
    kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
#ifdef __cplusplus
}
#endif

// --- IL2CPP API ---
typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef size_t (*il2cpp_image_get_class_count_t)(void* image);
typedef void* (*il2cpp_image_get_class_t)(void* image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(void* klass);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);

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

// --- MEMORY ENGINE ---
uintptr_t get_active_base() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *nsName = [NSString stringWithUTF8String:name];
        NSString *fileName = [nsName lastPathComponent];
        if ([fileName containsString:@"UnityFramework"] || [fileName isEqualToString:@"cod"]) {
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

    // Error 2 happens here if get-task-allow is missing
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
    self.btn.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8];
    [self.btn setTitle:@"🎭" forState:UIControlStateNormal];
    self.btn.layer.cornerRadius = 27.5;
    [self.btn addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:self.btn];
}

- (void)openMenu {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"COD MOD" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Patch Method from your Tutorial
    [ac addAction:[UIAlertAction actionWithTitle:@"💉 Apply Aim Flick (Tutorial)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        // Offset for get_AimAssistAmount from your analysis
        uint64_t off = 0x5AE27C0; 
        // Hex for FMOV S0, #31; RET
        NSData *hex = hexToBytes(@"00F0271EC0035FD6");
        kern_return_t kr = safe_write(get_active_base() + off, (void *)[hex bytes], [hex length]);
        
        NSString *res = (kr == KERN_SUCCESS) ? @"✅ Flick Applied!" : @"❌ Error 2: Needs JIT/Entitlement";
        UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Result" message:res preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self.window.rootViewController presentViewController:r animated:YES completion:nil];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:ac animated:YES completion:nil];
}
@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ModMenu shared] setup];
    });
}
