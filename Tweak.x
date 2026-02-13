#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/mman.h>

// --- 1. IL2CPP API DEFINITIONS ---
typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef size_t (*il2cpp_image_get_class_count_t)(void* image);
typedef void* (*il2cpp_image_get_class_t)(void* image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(void* klass);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);

// --- 2. THE LANDSCAPE-DRIVEN ENGINE ---

// Custom Controller to force Landscape/Rotation support
@interface LandscapeController : UIViewController @end
@implementation LandscapeController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

// Pass-through window to ensure clicks hit the game, not the empty menu
@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

// --- 3. MEMORY & BASE DETECTION ---

// Finds "cod" main binary or UnityFramework automatically
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

// Jailed-safe write to bypass Error 3 (No VM_PROT_COPY)
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
        chars[0] = [str characterAtIndex:i*2]; chars[1] = [str characterAtIndex:i*2+1];
        byte = strtol(chars, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

// --- 4. THE SCANNER & MENU ---

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
    self.window.rootViewController = [LandscapeController new]; // Forces Landscape
    self.window.hidden = NO;

    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(100, 100, 55, 55);
    self.btn.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8];
    [self.btn setTitle:@"🎭" forState:UIControlStateNormal];
    self.btn.layer.cornerRadius = 27.5;
    self.btn.layer.borderColor = [UIColor cyanColor].CGColor;
    self.btn.layer.borderWidth = 2;
    [self.btn addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.btn addGestureRecognizer:p];
    [self.window.rootViewController.view addSubview:self.btn];
}

- (void)drag:(UIPanGestureRecognizer *)p {
    UIView *v = p.view; CGPoint t = [p translationInView:self.window];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.window];
}

- (NSString *)scan:(NSString *)keyword {
    NSMutableString *log = [NSMutableString stringWithString:@"--- Results ---\n"];
    void *h = dlopen(NULL, RTLD_LAZY);
    il2cpp_domain_get_t d_get = (il2cpp_domain_get_t)dlsym(h, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t a_get = (il2cpp_domain_get_assemblies_t)dlsym(h, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t i_get = (il2cpp_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    il2cpp_image_get_class_count_t cc = (il2cpp_image_get_class_count_t)dlsym(h, "il2cpp_image_get_class_count");
    il2cpp_image_get_class_t cg = (il2cpp_image_get_class_t)dlsym(h, "il2cpp_image_get_class");
    il2cpp_class_get_name_t cn = (il2cpp_class_get_name_t)dlsym(h, "il2cpp_class_get_name");
    il2cpp_class_get_methods_t cm = (il2cpp_class_get_methods_t)dlsym(h, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t mn = (il2cpp_method_get_name_t)dlsym(h, "il2cpp_method_get_name");

    if (!d_get) return @"❌ Unity symbols not found.";

    uintptr_t base = get_active_base();
    size_t count = 0; void **asms = a_get(d_get(), &count);
    for (int i = 0; i < count; i++) {
        void *img = i_get(asms[i]); size_t clCount = cc(img);
        for (int c = 0; c < clCount; c++) {
            void *kl = cg(img, c); const char *name = cn(kl); if (!name) continue;
            NSString *cN = [NSString stringWithUTF8String:name];
            void *it = NULL; void *m = NULL;
            while ((m = cm(kl, &it))) {
                NSString *mN = [NSString stringWithUTF8String:mn(m)];
                if ([cN localizedCaseInsensitiveContainsString:keyword] || [mN localizedCaseInsensitiveContainsString:keyword]) {
                    uintptr_t p = *(uintptr_t*)m; if (p > base) [log appendFormat:@"0x%lx : %@[%@]\n", p - base, cN, mN];
                }
            }
        }
    }
    return log;
}

- (void)openMenu {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"COD LANDSCAPE MOD" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"🔍 Scanner (MP/Aim)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIAlertController *s = [UIAlertController alertControllerWithTitle:@"Scan" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [s addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder = @"Mp, Health, Weapon..."; }];
        [s addAction:[UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *r = [self scan:s.textFields[0].text]; UIPasteboard.generalPasteboard.string = r;
            [self showRes:r];
        }]];
        [self.window.rootViewController presentViewController:s animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"💉 Patch" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        UIAlertController *p = [UIAlertController alertControllerWithTitle:@"Patch" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder = @"Offset"; }];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder = @"Hex"; }];
        [p addAction:[UIAlertAction actionWithTitle:@"Patch" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            uint64_t o = strtoull([p.textFields[0].text UTF8String], NULL, 16); NSData *h = hexToBytes(p.textFields[1].text);
            kern_return_t kr = safe_write(get_active_base() + o, (void *)[h bytes], [h length]);
            [self showRes:(kr == KERN_SUCCESS ? @"Applied!" : @"Error")];
        }]];
        [self.window.rootViewController presentViewController:p animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:ac animated:YES completion:nil];
}

- (void)showRes:(NSString *)t {
    UIAlertController *r = [UIAlertController alertControllerWithTitle:@"System" message:t preferredStyle:UIAlertControllerStyleAlert];
    [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:r animated:YES completion:nil];
}
@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ModMenu shared] setup];
    });
}
