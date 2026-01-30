#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- CONFIGURATION ---
// No Telegram token needed. This saves directly to your phone.

void saveFileListLocally() {
    // 1. Setup Paths
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    
    // Get path to Documents directory (accessible via Files app)
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *outputPath = [documentsPath stringByAppendingPathComponent:@"App_File_List.txt"];

    // 2. Scan Bundle
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:bundlePath error:&error];

    if (error) {
        NSLog(@"[Enigma] Error reading bundle: %@", error);
        return;
    }

    // 3. Build the List
    NSMutableString *log = [NSMutableString stringWithFormat:@"=== APP BUNDLE CONTENTS ===\n"];
    [log appendFormat:@"Bundle Path: %@\n", bundlePath];
    [log appendFormat:@"Total Files: %lu\n\n", (unsigned long)files.count];
    
    for (NSString *fileName in files) {
        // Optional: Filter out junk to make reading easier
        if (![fileName hasSuffix:@".png"] && ![fileName hasSuffix:@".car"] && ![fileName hasSuffix:@".lproj"]) {
             [log appendFormat:@"%@\n", fileName];
        }
    }

    // 4. Save to Disk
    NSError *writeError = nil;
    BOOL success = [log writeToFile:outputPath
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&writeError];

    if (success) {
        // Success!
        NSLog(@"[Enigma] ✅ SAVED LIST TO: %@", outputPath);
    } else {
        NSLog(@"[Enigma] ❌ FAILED TO SAVE: %@", writeError);
    }
}

// --- MAIN ENTRY POINT ---
%ctor {
    // Run immediately on a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        saveFileListLocally();
    });
}
