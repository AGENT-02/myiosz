#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/mman.h>

// --- 1. IL2CPP API DEFINITIONS (For the Scanner) ---
typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef size_t (*il2cpp_image_get_class_count_t)(void* image);
typedef void* (*il2cpp_image_get_class_t)(void* image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(void* klass);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);

// --- 2. MEMORY TOOLS (Jailed Safe) ---

// Helper: Convert Hex String to Bytes
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

// Helper: Find Base Address of UnityFramework
uintptr_t get_unity_base() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    // Fallback for games statically linked
    return (uintptr_t)_dyld_get_image_header(0);
}

// THE FIX: Standard Jailed Write (No Copy Flag)
kern_return_t write_memory(uintptr_t address, void *data, size_t size) {
    mach_port_t task = mach_task_self();
    kern_return_t kr;

    // 1. Align to Page
    vm_address_t page_start = address & ~PAGE_MASK;
    vm_address_t page_end = (address + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;

    // 2. Unlock (Read + Write) - REMOVED VM_PROT_COPY TO FIX ERROR 3
    kr = mach_vm_protect(task, page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) return kr;

    // 3. Write
    kr = mach_vm_write(task, address, (vm_offset_t)data, (mach_msg_type_number_t)size);
    if (kr != KERN_SUCCESS) {
        // Backup: memcpy
        memcpy((void *)address, data, size);
    }

    // 4. Lock (Read + Execute)
    mach_vm_protect(task, page_start, page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    
    return KERN_SUCCESS;
}

NSString *apply_patch(uint64_t offset, NSString *hexStr) {
    NSData *data = dataFromHexString(hexStr);
    if (!data || data.length == 0) return @"Invalid Hex";

    uintptr_t base = get_unity_base();
    uintptr_t finalAddr = base + offset;

    kern_return_t kr = write_memory(finalAddr, (void *)[data bytes], [data length]);
    
    if (kr == KERN_SUCCESS) return @"✅ Patch Applied!";
    return [NSString stringWithFormat:@"❌ Fail: Kernel Error %d", kr];
}

// --- 3. UNITY INSPECTOR (Scanner) ---
NSString *scan_unity_methods(NSString *keyword) {
    NSMutableString *log = [NSMutableString stringWithString:@"--- Results ---\n"];
    
    void *handle = dlopen("UnityFramework.framework/UnityFramework", RTLD_LAZY);
    if (!handle) handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) return @"❌ Error: Unity Not Found";

    // Load Il2Cpp Functions
    il2cpp_domain_get_t domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_image_get_class_count_t get_class_count = (il2cpp_image_get_class_count_t)dlsym(handle, "il2cpp_image_get_class_count");
    il2cpp_image_get_class_t get_class = (il2cpp_image_get_class_t)dlsym(handle, "il2cpp_image_get_class");
    il2cpp_class_get_name_t class_get_name = (il2cpp_class_get_name_t)dlsym(handle, "il2cpp_class_get_name");
    il2cpp_class_get_methods_t class_get_methods = (il2cpp_class_get_methods_t)dlsym(handle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t method_get_name = (il2cpp_method_get_name_t)dlsym(handle, "il2cpp_method_get_name");

    if (!domain_get) return @"❌ Error: Symbols Hidden";

    uintptr_t base = get_unity_base();
    size_t asm_count = 0;
    void **assemblies = get_assemblies(domain_get(), &asm_count);
    int foundCount = 0;

    for (int i = 0; i < asm_count; i++) {
        void *image = get_image(assemblies[i]);
        size_t classCount = get_class_count(image);
        
        for (int c = 0; c < classCount; c++) {
            void *klass = get_class(image, c);
            const char *cNamePtr = class_get_name(klass);
            if (!cNamePtr) continue;
            NSString *className = [NSString stringWithUTF8String:cNamePtr];
            
            // Skip common junk
            if ([className hasPrefix:@"System"] || [className hasPrefix:@"UnityEngine"]) continue;

            void *iter = NULL;
            void *method = NULL;
            while ((method = class_get_methods(klass, &iter))) {
                const char *mNamePtr = method_get_name(method);
                if (!mNamePtr) continue;
                NSString *methodName = [NSString stringWithUTF8String:mNamePtr];

                if ([className localizedCaseInsensitiveContainsString:keyword] || 
                    [methodName localizedCaseInsensitiveContainsString:keyword]) {
                    
                    uintptr_t ptr = *(uintptr_t*)method; // Get Pointer
                    if (ptr > base) {
                        uintptr_t offset = ptr - base;
                        [log appendFormat:@"0x%lx : %@[%@]\n", offset, className, methodName];
                        foundCount++;
                    }
                }
            }
        }
        if (foundCount > 50) break;
    }
    
    if (foundCount == 0) return @"No matches found.";
    return log;
}

// --- 4. FLOATING UI (Pass-Through) ---

@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) return nil;
    return hitView;
}
@end

@interface MenuManager : NSObject
@property (nonatomic, strong) PassThroughWindow *overlayWindow;
@property (nonatomic, strong) UIButton *menuBtn;
+ (instancetype)shared;
@end

@implementation MenuManager
+ (instancetype)shared {
    static MenuManager *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MenuManager new]; });
    return s;
}

- (void)start { [self performSelector:@selector(findScene) withObject:nil afterDelay:1.0]; }

- (void)findScene {
    UIWindowScene *activeScene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive) { activeScene = (UIWindowScene*)s; break; }
    }
    if (!activeScene) { [self performSelector:@selector(findScene) withObject:nil afterDelay:1.0]; return; }
    [self setupWindow:activeScene];
}

- (void)setupWindow:(UIWindowScene *)scene {
    if (self.overlayWindow) return;
    self.overlayWindow = [[PassThroughWindow alloc] initWithWindowScene:scene];
    self.overlayWindow.frame = [UIScreen mainScreen].bounds;
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    
    UIViewController *rootVC = [UIViewController new];
    rootVC.view.backgroundColor = [UIColor clearColor];
    self.overlayWindow.rootViewController = rootVC;
    self.overlayWindow.hidden = NO;
    [self createButton];
}

- (void)createButton {
    self.menuBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuBtn.frame = CGRectMake(20, 100, 50, 50);
    self.menuBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.9];
    [self.menuBtn setTitle:@"🔥" forState:UIControlStateNormal];
    self.menuBtn.layer.cornerRadius = 25;
    self.menuBtn.layer.borderColor = [UIColor redColor].CGColor;
    self.menuBtn.layer.borderWidth = 2;
    [self.menuBtn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.menuBtn addGestureRecognizer:p];
    [self.overlayWindow.rootViewController.view addSubview:self.menuBtn];
}

- (void)drag:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:self.overlayWindow];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.overlayWindow];
}

- (void)showMenu {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Mod Menu" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    // SCANNER
    [ac addAction:[UIAlertAction actionWithTitle:@"Find Offsets" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *s = [UIAlertController alertControllerWithTitle:@"Scanner" message:@"Search (e.g. Coin, Health)" preferredStyle:UIAlertControllerStyleAlert];
        [s addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Keyword"; }];
        [s addAction:[UIAlertAction actionWithTitle:@"Scan" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *res = scan_unity_methods(s.textFields[0].text);
            UIPasteboard.generalPasteboard.string = res; // Auto-copy
            [self showTextResult:res];
        }]];
        [s addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:s animated:YES completion:nil];
    }]];
    
    // PATCHER
    [ac addAction:[UIAlertAction actionWithTitle:@"Apply Patch" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        UIAlertController *p = [UIAlertController alertControllerWithTitle:@"Patcher" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Offset (0x...)"; }];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Hex (e.g. C0035FD6)"; }];
        [p addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            NSString *res = apply_patch(strtoull([p.textFields[0].text UTF8String], NULL, 16), p.textFields[1].text);
            [self alertRes:res];
        }]];
        [p addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:p animated:YES completion:nil];
    }]];
    
    [ac addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:ac animated:YES completion:nil];
}

- (void)showTextResult:(NSString *)text {
    UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Results (Copied)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [res addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *vc = [UIViewController new];
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 270, 300)];
    tv.text = text;
    tv.editable = NO;
    tv.font = [UIFont systemFontOfSize:10];
    vc.preferredContentSize = CGSizeMake(270, 300);
    [vc.view addSubview:tv];
    [res setValue:vc forKey:@"contentViewController"];
    [self.overlayWindow.rootViewController presentViewController:res animated:YES completion:nil];
}

- (void)alertRes:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:a animated:YES completion:nil];
}
@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[MenuManager shared] start];
    });
}
