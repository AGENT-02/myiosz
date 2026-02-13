#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/mman.h>

// --- DECLARATIONS ---
extern void sys_icache_invalidate(void *start, size_t len);

// --- 1. MEMORY PATCHER ---
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
    uintptr_t base = (uintptr_t)_dyld_get_image_header(0);
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

// --- 2. OFFSET INSPECTOR (The Scraper) ---
NSString *scan_methods(NSString *keyword) {
    NSMutableString *results = [NSMutableString stringWithFormat:@"--- Scanning for '%@' ---\n", keyword];
    int count = 0;
    uintptr_t base = (uintptr_t)_dyld_get_image_header(0);

    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        const char *cName = class_getName(cls);
        NSString *className = [NSString stringWithUTF8String:cName];

        if ([className hasPrefix:@"UI"] || [className hasPrefix:@"NS"] || [className hasPrefix:@"_"]) continue;

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);

        for (unsigned int j = 0; j < methodCount; j++) {
            Method m = methods[j];
            SEL sel = method_getName(m);
            NSString *selectorName = [NSString stringWithUTF8String:sel_getName(sel)];

            if (([className localizedCaseInsensitiveContainsString:keyword] || 
                 [selectorName localizedCaseInsensitiveContainsString:keyword])) {
                
                uintptr_t imp = (uintptr_t)method_getImplementation(m);
                if (imp > base) {
                    uintptr_t offset = imp - base;
                    [results appendFormat:@"0x%lx : [%@ %@]\n", offset, className, selectorName];
                    count++;
                }
            }
        }
        free(methods);
        if (count > 50) {
            [results appendString:@"... (Too many results)\n"];
            break; 
        }
    }
    free(classes);
    if (count == 0) return @"No matches found.";
    return results;
}

// --- 3. UI SYSTEM (FIXED HIT TEST) ---

@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // THE FIX: If the hit view is the Window itself or the Root View Controller's background,
    // return nil so the touch passes through to the game.
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    
    // Otherwise (if it's a Button, TextField, or Alert), return the view.
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
    
    // Create a generic VC for the window
    UIViewController *rootVC = [UIViewController new];
    rootVC.view.backgroundColor = [UIColor clearColor]; // Ensure transparent
    self.overlayWindow.rootViewController = rootVC;
    self.overlayWindow.hidden = NO;
    
    // Add button to the RootVC's view, NOT the window directly (Fixes rotation issues)
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
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Inspector" message:@"Choose Action" preferredStyle:UIAlertControllerStyleActionSheet];
    
    // ACTION 1: PATCHER
    [ac addAction:[UIAlertAction actionWithTitle:@"Apply Hex Patch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *p = [UIAlertController alertControllerWithTitle:@"Patcher" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Offset (0x...)"; }];
        [p addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Hex (C003...)"; }];
        [p addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            NSString *res = apply_patch(strtoull([p.textFields[0].text UTF8String], NULL, 16), p.textFields[1].text);
            [self alertRes:res];
        }]];
        [p addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.overlayWindow.rootViewController presentViewController:p animated:YES completion:nil];
    }]];
    
    // ACTION 2: SCRAPER
    [ac addAction:[UIAlertAction actionWithTitle:@"Search Offsets" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *s = [UIAlertController alertControllerWithTitle:@"Scraper" message:@"Enter keyword" preferredStyle:UIAlertControllerStyleAlert];
        [s addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"Keyword"; }];
        [s addAction:[UIAlertAction actionWithTitle:@"Scan" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *logs = scan_methods(s.textFields[0].text);
            
            UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Results" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [res addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [UIPasteboard generalPasteboard].string = logs;
            }]];
            [res addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
            
            UIViewController *vc = [[UIViewController alloc] init];
            UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 270, 300)];
            tv.text = logs;
            tv.editable = NO;
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[MenuManager shared] start];
    });
}
