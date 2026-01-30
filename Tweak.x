#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/mman.h>
#import <sys/stat.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define TARGET_URL @"0devs.org"

// --- HELPER: TELEGRAM ---
void sendText(NSString *text) {
    @try {
        NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                            TG_TOKEN, TG_CHAT_ID, 
                            [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:nil] resume];
    } @catch (NSException *e) {}
}

// =========================================================
// PART 1: THE URL SWAPPER (RUNTIME HOOK)
// =========================================================
// This intercepts the URL *before* the app uses it.
// It effectively "swaps" it in memory without breaking the file signature.

%hook NSURL

+ (instancetype)URLWithString:(NSString *)URLString {
    if ([URLString localizedCaseInsensitiveContainsString:TARGET_URL]) {
        // SWAP DETECTION
        // sendText([NSString stringWithFormat:@"🚨 INTERCEPTED & SWAPPED:\n%@", URLString]);
        
        // Redirect to nowhere (Localhost)
        return %orig(@"http://127.0.0.1");
    }
    return %orig;
}

- (instancetype)initWithString:(NSString *)URLString {
    if ([URLString localizedCaseInsensitiveContainsString:TARGET_URL]) {
        return %orig(@"http://127.0.0.1");
    }
    return %orig;
}

%end

// =========================================================
// PART 2: THE HIGH-SPEED SCANNER
// =========================================================
// Scans every file in the bundle for the target string.

void scanBundleForTarget() {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    
    sendText([NSString stringWithFormat:@"🚀 FAST SCAN STARTED!\nSearching for '%@' in: %@", TARGET_URL, [bundlePath lastPathComponent]]);
    
    const char *target = [TARGET_URL UTF8String];
    size_t targetLen = strlen(target);
    
    NSString *file;
    int scannedCount = 0;
    
    while (file = [enumerator nextObject]) {
        scannedCount++;
        
        // Skip media assets to speed up (Images/Audio don't contain code)
        if ([file hasSuffix:@".png"] || [file hasSuffix:@".jpg"] || [file hasSuffix:@".car"]) continue;
        
        NSString *fullPath = [bundlePath stringByAppendingPathComponent:file];
        
        // 1. Map file to memory (Fastest reading method)
        int fd = open([fullPath UTF8String], O_RDONLY);
        if (fd == -1) continue;
        
        struct stat sb;
        if (fstat(fd, &sb) == -1) { close(fd); continue; }
        
        if (sb.st_size == 0) { close(fd); continue; }
        
        void *mapped = mmap(NULL, sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (mapped == MAP_FAILED) { close(fd); continue; }
        
        // 2. Search using 'memmem' (C-level byte search)
        if (memmem(mapped, sb.st_size, target, targetLen)) {
            // FOUND IT!
            sendText([NSString stringWithFormat:@"🎯 FOUND TARGET URL!\n\n📂 File: %@\n📍 Path: %@", file, fullPath]);
        }
        
        // Cleanup
        munmap(mapped, sb.st_size);
        close(fd);
    }
    
    sendText([NSString stringWithFormat:@"✅ SCAN COMPLETE.\nScanned %d files.", scannedCount]);
}

%ctor {
    // Run scan in background immediately
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        scanBundleForTarget();
    });
}
