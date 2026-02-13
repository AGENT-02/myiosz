#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/mman.h> // Required for mprotect constants

// --- 1. MEMORY PATCHING ENGINE ---

/*
 * Helper: Converts "C0035FD6" string to raw bytes
 */
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

/*
 * The Patch Function
 * 1. Unlocks memory (RWX)
 * 2. Writes bytes
 * 3. Relocks memory (RX)
 */
NSString *apply_patch(uint64_t offset, NSString *hexStr) {
    NSData *data = dataFromHexString(hexStr);
    if (!data || data.length == 0) return @"Invalid Hex Data";

    // Get Binary Base Address
    uintptr_t base = (uintptr_t)_dyld_get_image_header(0);
    uintptr_t addr = base + offset;

    // Align to page size (Required for vm_protect)
    vm_size_t size = data.length;
    vm_address_t page_start = addr & ~PAGE_MASK;
    vm_address_t page_end = (addr + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;

    // Unlock Memory
    // Note: vm_protect is used here. If this fails on Jailed, JIT is likely missing.
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    
    if (kr != KERN_SUCCESS) {
        return [NSString stringWithFormat:@"Error: Memory Unlock Failed (Code %d). Is JIT enabled?", kr];
    }

    // Write Data
    memcpy((void *)addr, [data bytes], size);

    // Relock Memory
    vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);

    // Flush CPU Cache (Important for ARM64)
    sys_icache_invalidate((void *)addr, size);

    return @"Patch Applied Successfully!";
}

// --- 2. FLOATING MENU UI ---

@interface FloatingMenu : UIWindow
@property (nonatomic, strong) UIButton *btn;
+ (instancetype)shared;
@end

@implementation FloatingMenu

+ (instancetype)shared {
    static FloatingMenu *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FloatingMenu alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return shared;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 1; // Sit above everything
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.hidden = NO;
        [self createButton];
    }
    return self;
}

// Pass touches through the empty parts of the window
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.btn.frame, point)) {
        return YES;
    }
    return NO;
}

- (void)createButton {
    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(20, 100, 50, 50);
    self.btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.8];
    [self.btn setTitle:@"🛠️" forState:UIControlStateNormal];
    self.btn.layer.cornerRadius = 25;
    self.btn.layer.borderWidth = 2;
    self.btn.layer.borderColor = [UIColor cyanColor].CGColor;
    
    // Add Drag Gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.btn addGestureRecognizer:pan];
    
    // Add Tap Action
    [self.btn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [self addSubview:self.btn];
}

- (void)handleDrag:(UIPanGestureRecognizer *)sender {
    UIView *view = sender.view;
    CGPoint translation = [sender translationInView:self];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:self];
}

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Live Patcher"
                                                                   message:@"Enter Relative Offset & Hex"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Offset (e.g. 0x1005A0)";
        field.textColor = [UIColor blackColor];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Hex (e.g. C0035FD6)";
        field.textColor = [UIColor blackColor];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    UIAlertAction *patchAction = [UIAlertAction actionWithTitle:@"APPLY PATCH" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *offsetStr = alert.textFields[0].text;
        NSString *hexStr = alert.textFields[1].text;
        
        // Parse Offset
        unsigned long long offset = 0;
        NSScanner *scanner = [NSScanner scannerWithString:offsetStr];
        [scanner scanHexLongLong:&offset];

        // Apply
        NSString *result = apply_patch(offset, hexStr);
        
        // Show Result Toast
        UIAlertController *resAlert = [UIAlertController alertControllerWithTitle:@"Result" 
                                                                          message:result 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [resAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.rootViewController presentViewController:resAlert animated:YES completion:nil];
    }];

    [alert addAction:patchAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// --- 3. CONSTRUCTOR ---

%ctor {
    // Wait 5 seconds for the app to launch fully before adding our UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [FloatingMenu shared];
    });
}
