#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/mman.h>

// --- IL2CPP API DEFINITIONS (Minimal) ---
typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef size_t (*il2cpp_image_get_class_count_t)(void* image);
typedef void* (*il2cpp_image_get_class_t)(void* image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(void* klass);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);
typedef uintptr_t (*il2cpp_method_get_pointer_t)(void* method); // Returns absolute address

// --- HELPERS ---
uintptr_t get_image_base(const char* image_name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, image_name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// --- 1. THE UNITY SCRAPER ---
NSString *scan_unity_methods(NSString *keyword) {
    NSMutableString *log = [NSMutableString stringWithString:@"--- IL2CPP Scan Results ---\n"];
    
    // 1. Find UnityFramework Handle
    void *handle = dlopen(NULL, RTLD_LAZY); // Search global scope first
    if (!dlsym(handle, "il2cpp_domain_get")) {
        // If not found globally, try opening UnityFramework directly
        handle = dlopen("UnityFramework.framework/UnityFramework", RTLD_LAZY);
    }
    
    if (!handle) return @"Error: Could not find UnityFramework.";

    // 2. Resolve Functions
    il2cpp_domain_get_t il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t il2cpp_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_image_get_class_count_t il2cpp_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(handle, "il2cpp_image_get_class_count");
    il2cpp_image_get_class_t il2cpp_image_get_class = (il2cpp_image_get_class_t)dlsym(handle, "il2cpp_image_get_class");
    il2cpp_class_get_name_t il2cpp_class_get_name = (il2cpp_class_get_name_t)dlsym(handle, "il2cpp_class_get_name");
    il2cpp_class_get_methods_t il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(handle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(handle, "il2cpp_method_get_name");
    
    // Some newer Unity versions use a different API for getting function pointers
    // But usually method->methodPointer is at offset 0 or accessible. 
    // For simplicity in a tweak, we will assume standard layout or use basic offset calc.
    
    if (!il2cpp_domain_get) return @"Error: Il2Cpp symbols hidden/stripped.";

    // 3. Get Domain & Assemblies
    void *domain = il2cpp_domain_get();
    size_t asm_count = 0;
    void **assemblies = il2cpp_domain_get_assemblies(domain, &asm_count);
    
    uintptr_t unityBase = get_image_base("UnityFramework");
    if (unityBase == 0) unityBase = get_image_base("MY_APP_NAME"); // Fallback

    int foundCount = 0;

    for (int i = 0; i < asm_count; i++) {
        void *image = il2cpp_assembly_get_image(assemblies[i]);
        // We mostly care about Assembly-CSharp (Game Logic)
        // You can remove this 'if' to scan EVERYTHING (Engine, UI, etc)
        // if (i != 0) continue; 
        
        size_t classCount = il2cpp_image_get_class_count(image);
        
        for (int c = 0; c < classCount; c++) {
            void *klass = il2cpp_image_get_class(image, c);
            const char *cName = il2cpp_class_get_name(klass);
            if (!cName) continue;
            NSString *className = [NSString stringWithUTF8String:cName];
            
            // Optimization: Skip system classes
            if ([className hasPrefix:@"System"] || [className hasPrefix:@"Mono"]) continue;

            // Check if CLASS matches keyword
            BOOL classMatch = [className localizedCaseInsensitiveContainsString:keyword];
            
            void *iter = NULL;
            void *method = NULL;
            while ((method = il2cpp_class_get_methods(klass, &iter))) {
                const char *mName = il2cpp_method_get_name(method);
                if (!mName) continue;
                NSString *methodName = [NSString stringWithUTF8String:mName];
                
                // SEARCH LOGIC
                if (classMatch || [methodName localizedCaseInsensitiveContainsString:keyword]) {
                    // Extract Pointer (Hack for Il2Cpp Method Struct)
                    // The pointer is usually the first member of the struct in recent Unity
                    uintptr_t ptr = *(uintptr_t*)method; 
                    
                    if (ptr > unityBase) {
                        uintptr_t offset = ptr - unityBase;
                        [log appendFormat:@"0x%lx : %@[%@]\n", offset, className, methodName];
                        foundCount++;
                    }
                }
            }
        }
        if (foundCount > 50) break; // Limit results
    }
    
    if (foundCount == 0) return @"No matches found in UnityFramework.";
    return log;
}

// --- 2. MEMORY PATCHER ---
extern void sys_icache_invalidate(void *start, size_t len);

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
    if (!data || data.length == 0) return @"Invalid Hex";
    
    // TARGET UNITY FRAMEWORK
    uintptr_t base = get_image_base("UnityFramework");
    if (base == 0) return @"Error: UnityFramework not found!";
    
    uintptr_t addr = base + offset;
    vm_size_t size = data.length;
    vm_address_t page_start = addr & ~PAGE_MASK;
    vm_address_t page_end = (addr + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;
    
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return [NSString stringWithFormat:@"Unlock Fail: %d", kr];
    
    memcpy((void *)addr, [data bytes], size);
    vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void *)addr, size);
    return @"Patched!";
}

// --- 3. UI SYSTEM ---
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
    self.menuBtn.backgroundColor = [UIColor blackColor];
    [self.menuBtn setTitle:@"🕵️" forState:UIControlStateNormal];
    self.menuBtn.layer.cornerRadius = 25;
    self.menuBtn.layer.borderColor = [UIColor greenColor].CGColor;
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
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Unity Inspector" message:@"Select Action" preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 1. PATCHER
    [ac addAction:[UIAlertAction actionWithTitle:@"Patcher (Offsets)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *p = [UIAlertController alertControllerWithTitle:@"Unity Patcher" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Offset (e.g. 0x123ABC)"; }];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Hex (e.g. C0035FD6)"; }];
        [p addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            NSString *res = apply_patch(strtoull([p.textFields[0].text UTF8String], NULL, 16), p.textFields[1].text);
            [self alertRes:res];
        }]];
        [p addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:p animated:YES completion:nil];
    }]];
    
    // 2. UNITY SCANNER
    [ac addAction:[UIAlertAction actionWithTitle:@"Scan Unity (Il2Cpp)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *s = [UIAlertController alertControllerWithTitle:@"Unity Scanner" message:@"Enter class/method name" preferredStyle:UIAlertControllerStyleAlert];
        [s addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"e.g. Health, Coins, God"; }];
        [s addAction:[UIAlertAction actionWithTitle:@"Scan" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *logs = scan_unity_methods(s.textFields[0].text);
            
            UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Scan Results" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [res addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [UIPasteboard generalPasteboard].string = logs;
            }]];
            [res addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
            
            UIViewController *vc = [[UIViewController alloc] init];
            UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 270, 300)];
            tv.text = logs;
            tv.editable = NO;
            tv.backgroundColor = [UIColor whiteColor];
            tv.textColor = [UIColor blackColor];
            tv.font = [UIFont fontWithName:@"Courier" size:10];
            vc.preferredContentSize = CGSizeMake(270, 300);
            [vc.view addSubview:tv];
            [res setValue:vc forKey:@"contentViewController"];
            
            [self.overlayWindow.rootViewController presentViewController:res animated:YES completion:nil];
        }]];
        [s addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:s animated:YES completion:nil];
    }]];
    
    [ac addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:ac animated:YES completion:nil];
}

- (void)alertRes:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"System" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:a animated:YES completion:nil];
}
@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[MenuManager shared] start];
    });
}
