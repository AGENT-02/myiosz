#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// --- MEMORY PATCHING ENGINE ---

/*
 * Converts "C0035FD6" (String) -> <C0 03 5F D6> (NSData)
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
 * Tries to make memory Writable (RWX) to apply the patch.
 */
NSString *apply_patch(uint64_t offset, NSString *hexStr) {
    NSData *data = dataFromHexString(hexStr);
    if (!data || data.length == 0) return @"Invalid Hex Data";

    // 1. Get location
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base = (uintptr_t)_dyld_get_image_header(0);
    uintptr_t addr = base + offset;

    // 2. Align to page size (required for vm_protect)
    vm_size_t size = data.length;
    vm_address_t page_start = addr & ~PAGE_MASK;
    vm_address_t page_end = (addr + size + PAGE_MASK) & ~PAGE_MASK;
    vm_size_t page_size = page_end - page_start;

    // 3. Unlock Memory
    // NOTE: In jailed mode without JIT, this is the step that usually fails.
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    
    if (kr != KERN_SUCCESS) {
        return [NSString stringWithFormat:@"Failed to unlock memory (Error: %d). JIT might be required.", kr];
    }

    // 4. Write Data
    memcpy((void *)addr, [data bytes], size);

    // 5. Relock Memory (Execute)
    vm_protect(mach_task_self(), page_start, page_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);

    return @"Success!";
}

// --- FLOATING MENU UI ---

@interface FloatingMenu : UIWindow
@property (nonatomic, strong) UIButton *btn;
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
        self.windowLevel = UIWindowLevelAlert + 1; // Above everything
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.hidden = NO;
        [self createButton];
    }
    return self;
}

// Ensure touches pass through empty space to the game
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.btn.frame, point)) return YES;
    return NO;
}

- (void)createButton {
    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(20, 100, 50, 50);
    self.btn.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    [self.btn setTitle:@"M" forState:UIControlStateNormal];
    self.btn.layer.cornerRadius = 25;
    self.btn.layer.borderWidth = 1;
    self.btn.layer.borderColor = [UIColor redColor].CGColor;
    
    // Add Drag Support
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.btn addGestureRecognizer:pan];
    
    // Add Tap Support
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
                                                                   message:@"Enter Offset & Hex"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Offset (e.g. 0x123456)";
        field.textColor = [UIColor blackColor]; 
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Hex (e.g. C0035FD6)";
        field.textColor = [UIColor blackColor];
    }];

    UIAlertAction *patch = [UIAlertAction actionWithTitle:@"PATCH" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *offsetStr = alert.textFields[0].text;
        NSString *hexStr = alert.textFields[1].text;
        
        // Parse Offset String to Long Long
        unsigned long long offset = 0;
        NSScanner *scanner = [NSScanner scannerWithString:offsetStr];
        [scanner scanHexLongLong:&offset];

        // Run Patch
        NSString *result = apply_patch(offset, hexStr);
        
        // Show Result
        UIAlertController *resAlert = [UIAlertController alertControllerWithTitle:@"Result" message:result preferredStyle:UIAlertControllerStyleAlert];
        [resAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.rootViewController presentViewController:resAlert animated:YES completion:nil];
    }];

    [alert addAction:patch];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// --- CONSTRUCTOR ---
%ctor {
    // Delay load to ensure UIWindow is ready
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [FloatingMenu shared];
    });
}
