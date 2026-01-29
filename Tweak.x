#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h> // Required to find app classes

// --- UI CONFIG ---
@interface EnigmaOverlay : UIView <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>
// UI Elements
@property (nonatomic, strong) UIButton *cornerBtn;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UITextView *terminalView;
@property (nonatomic, strong) UITableView *classTableView; // The new List
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *modeBtn; // Toggle between Terminal/Browser

// Data
@property (nonatomic, strong) NSMutableArray *appClasses; // Stores the list of found classes
@property (nonatomic, strong) NSMutableArray *filteredClasses; // For search filtering
@end

@implementation EnigmaOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        [self loadAppClasses]; // Scan memory immediately
        [self setupUI];
    }
    return self;
}

// --- MEMORY SCANNER ---
- (void)loadAppClasses {
    self.appClasses = [NSMutableArray array];
    
    // 1. Get the name of the main executable (The App itself)
    const char *mainImage = _dyld_get_image_name(0);
    
    // 2. Get all classes defined in that executable
    unsigned int count = 0;
    const char **classes = objc_copyClassNamesForImage(mainImage, &count);
    
    for (unsigned int i = 0; i < count; i++) {
        NSString *className = [NSString stringWithUTF8String:classes[i]];
        [self.appClasses addObject:className];
    }
    
    if (classes) free(classes);
    
    // Sort alphabetically for easy browsing
    [self.appClasses sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.filteredClasses = [NSMutableArray arrayWithArray:self.appClasses];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}

- (void)setupUI {
    // 1. Corner Button
    self.cornerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cornerBtn.frame = CGRectMake(self.frame.size.width - 60, 80, 50, 50);
    self.cornerBtn.backgroundColor = [UIColor blackColor];
    self.cornerBtn.layer.cornerRadius = 25;
    self.cornerBtn.layer.borderColor = [UIColor greenColor].CGColor;
    self.cornerBtn.layer.borderWidth = 2;
    [self.cornerBtn setTitle:@">_" forState:UIControlStateNormal];
    [self.cornerBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.cornerBtn];

    // 2. Main Window
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 140, self.frame.size.width - 40, 500)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.98];
    self.menuView.layer.cornerRadius = 15;
    self.menuView.layer.borderColor = [UIColor greenColor].CGColor;
    self.menuView.layer.borderWidth = 1;
    self.menuView.hidden = YES;
    [self addSubview:self.menuView];

    // 3. Search / Input Field
    self.inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 15, self.menuView.frame.size.width - 110, 35)];
    self.inputField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.inputField.textColor = [UIColor greenColor];
    self.inputField.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
    self.inputField.placeholder = @"Search Classes...";
    self.inputField.layer.cornerRadius = 8;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.menuView addSubview:self.inputField];

    // 4. Mode Toggle (BROWSE / DUMP)
    self.modeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modeBtn.frame = CGRectMake(self.menuView.frame.size.width - 85, 15, 70, 35);
    self.modeBtn.backgroundColor = [UIColor greenColor];
    self.modeBtn.layer.cornerRadius = 8;
    [self.modeBtn setTitle:@"LIST" forState:UIControlStateNormal]; // Starts in Browser mode
    [self.modeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.modeBtn addTarget:self action:@selector(toggleMode) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:self.modeBtn];

    // 5. CLASS BROWSER (TableView)
    self.classTableView = [[UITableView alloc] initWithFrame:CGRectMake(15, 60, self.menuView.frame.size.width - 30, 425)];
    self.classTableView.backgroundColor = [UIColor clearColor];
    self.classTableView.separatorColor = [UIColor darkGrayColor];
    self.classTableView.delegate = self;
    self.classTableView.dataSource = self;
    self.classTableView.hidden = NO; // Show list by default
    [self.menuView addSubview:self.classTableView];

    // 6. TERMINAL OUTPUT (Hidden initially)
    self.terminalView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, self.menuView.frame.size.width - 30, 425)];
    self.terminalView.backgroundColor = [UIColor blackColor];
    self.terminalView.textColor = [UIColor greenColor];
    self.terminalView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.terminalView.editable = NO;
    self.terminalView.hidden = YES;
    [self.menuView addSubview:self.terminalView];
}

- (void)toggleMenu {
    self.menuView.hidden = !self.menuView.hidden;
    if (self.menuView.hidden) [self.inputField resignFirstResponder];
}

// Switch between List View and Terminal View
- (void)toggleMode {
    if (self.classTableView.hidden) {
        // Switch to List
        self.classTableView.hidden = NO;
        self.terminalView.hidden = YES;
        [self.modeBtn setTitle:@"LIST" forState:UIControlStateNormal];
        self.inputField.placeholder = @"Search Classes...";
    } else {
        // Switch to Terminal
        self.classTableView.hidden = YES;
        self.terminalView.hidden = NO;
        [self.modeBtn setTitle:@"LOGS" forState:UIControlStateNormal];
    }
}

// --- SEARCH LOGIC ---
- (void)textFieldDidChange:(UITextField *)textField {
    if (!self.classTableView.hidden) {
        // Filter the list based on typing
        NSString *query = textField.text;
        if (query.length == 0) {
            self.filteredClasses = [NSMutableArray arrayWithArray:self.appClasses];
        } else {
            NSPredicate *p = [NSPredicate predicateWithFormat:@"SELF contains[c] %@", query];
            self.filteredClasses = [NSMutableArray arrayWithArray:[self.appClasses filteredArrayUsingPredicate:p]];
        }
        [self.classTableView reloadData];
    }
}

// --- TABLEVIEW DELEGATES ( The Browser ) ---

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredClasses.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ClassCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    }
    cell.textLabel.text = self.filteredClasses[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // User tapped a class!
    NSString *selectedClass = self.filteredClasses[indexPath.row];
    
    // 1. Update UI
    self.inputField.text = selectedClass;
    [self.inputField resignFirstResponder];
    
    // 2. Switch to Terminal Mode
    self.classTableView.hidden = YES;
    self.terminalView.hidden = NO;
    [self.modeBtn setTitle:@"LOGS" forState:UIControlStateNormal];
    
    // 3. Run the Dump
    [self runDumpForClass:selectedClass];
}

// --- DUMPER LOGIC ---
- (void)runDumpForClass:(NSString *)className {
    self.terminalView.text = @""; // Clear old logs
    [self logToTerminal:[NSString stringWithFormat:@"[*] Dumping: %@\n-------------------", className]];

    Class targetClass = objc_getClass([className UTF8String]);
    if (!targetClass) {
        [self logToTerminal:@"[!] Error: Class not loaded."];
        return;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);

    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        NSString *methodName = NSStringFromSelector(method_getName(method));
        [self logToTerminal:[NSString stringWithFormat:@"- %@", methodName]];
    }
    
    // Also dump properties if you want
    [self logToTerminal:@"\n[Properties]"];
    unsigned int propCount = 0;
    objc_property_t *props = class_copyPropertyList(targetClass, &propCount);
    for (unsigned int i = 0; i < propCount; i++) {
        const char *name = property_getName(props[i]);
        [self logToTerminal:[NSString stringWithFormat:@". %s", name]];
    }

    free(methods);
    free(props);
    [self logToTerminal:@"\n[✓] END OF DUMP"];
}

- (void)logToTerminal:(NSString *)text {
    self.terminalView.text = [self.terminalView.text stringByAppendingFormat:@"%@\n", text];
    if(self.terminalView.text.length > 0) {
        [self.terminalView scrollRangeToVisible:NSMakeRange(self.terminalView.text.length - 1, 1)];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}
@end

%ctor {
    // 5-second safe delay before injecting UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = nil;
        for (UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *win in s.windows) if (win.isKeyWindow) { w = win; break; }
            }
        }
        if (!w) w = [UIApplication sharedApplication].keyWindow;
        if (w) [w addSubview:[[EnigmaOverlay alloc] initWithFrame:w.bounds]];
    });
    %init;
}
