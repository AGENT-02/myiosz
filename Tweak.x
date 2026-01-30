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
#define IGNORE_NAME @"Enigma" // YOUR DYLIB NAME TO IGNORE

// --- HELPER ---
void sendText(NSString *text) {
    @try {
        NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                            TG_TOKEN, TG_CHAT_ID, 
                            [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:nil] resume];
    } @catch (NSException *e) {}
}

// =========================================================
// PART 1: THE URL KILLER (RUNTIME REDIRECT)
// =========================================================
%hook NSURL
+ (instancetype)URLWithString:(NSString *)URLString {
    if ([URLString localizedCaseInsensitiveContainsString:TARGET_URL]) {
        return %orig(@"http://127.0.0.1"); // Redirect to Dead Localhost
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
// PART 2: THE MULTI-THREADED SCANNER
// =========================================================
void fastScanBundle() {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    sendText([NSString stringWithFormat:@"🚀 HYPER-SCAN STARTED for: %@\nIgnored: %@", TARGET_URL, IGNORE_NAME]);

    // 1. COLLECT FILES (Serial but fast)
    NSMutableArray *filesToScan = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    NSString *file;
    
    while (file = [enumerator nextObject]) {
        // FILTER: Skip Assets & Our Dylib
        if ([file hasSuffix:@".png"] || [file hasSuffix:@".jpg"] || 
            [file hasSuffix:@".car"] || [file hasSuffix:@".plist"] || 
            [file hasSuffix:@".nib"] || [file hasSuffix:@".lproj"] ||
            [file containsString:IGNORE_NAME]) { 
            continue; 
        }
        [filesToScan addObject:file];
    }

    // 2. SCAN FILES (PARALLEL - Uses all Cores)
    // dispatch_apply runs the block concurrently
    dispatch_apply(filesToScan.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(size_t i) {
        
        NSString *filename = filesToScan[i];
        NSString *fullPath = [bundlePath stringByAppendingPathComponent:filename];
        const char *target = [TARGET_URL UTF8String];
        size_t targetLen = strlen(target);

        int fd = open([fullPath UTF8String], O_RDONLY);
        if (fd == -1) return;

        struct stat sb;
        if (fstat(fd, &sb) == -1 || sb.st_size == 0) { close(fd); return; }

        // Map into memory
        void *mapped = mmap(NULL, sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (mapped == MAP_FAILED) { close(fd); return; }

        // FAST SEARCH
        if (memmem(mapped, sb.st_size, target, targetLen)) {
            sendText([NSString stringWithFormat:@"🎯 TARGET FOUND!\n\n📂 File: %@\n📍 Path: %@", filename, fullPath]);
        }

        munmap(mapped, sb.st_size);
        close(fd);
    });
    
    sendText([NSString stringWithFormat:@"✅ SCAN COMPLETE.\nProcessed %lu potential binaries.", (unsigned long)filesToScan.count]);
}

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        fastScanBundle();
    });
}
