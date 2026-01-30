#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- SYNCHRONOUS TELEGRAM ENGINE ---
// This blocks the app from closing until the message is sent
void sendBlockingTelegram(NSString *text) {
    // 1. Prepare Request
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TG_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    
    // Truncate if too long (Telegram limit)
    if (text.length > 4000) text = [text substringToIndex:4000];
    
    NSString *body = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                     TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    // 2. The Blocker (Semaphore)
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) NSLog(@"[Enigma] Upload Error: %@", e);
        else NSLog(@"[Enigma] Upload Success!");
        
        // Signal that we are done
        dispatch_semaphore_signal(sema);
    }] resume];
    
    // 3. FREEZE HERE until upload finishes (Max wait: 3 seconds)
    // This physically stops the 'exit()' function from completing
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
}

// --- CLASS DUMPER ---
void dumpSCClasses(NSString *reason) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    
    NSMutableString *log = [NSMutableString stringWithFormat:@"🚨 INTERCEPTED EXIT: %@ 🚨\n\n", reason];
    [log appendFormat:@"Total Classes: %u\n", count];
    
    // Filter for Snapchat classes (SC*)
    int found = 0;
    [log appendString:@"[DUMP START]\n"];
    for (int i = 0; i < count; i++) {
        const char *cname = class_getName(classes[i]);
        if (cname) {
            NSString *name = [NSString stringWithUTF8String:cname];
            if ([name hasPrefix:@"SC"] || [name containsString:@"Login"] || [name containsString:@"Manager"]) {
                [log appendFormat:@"%@\n", name];
                found++;
                if (found >= 80) break; // Limit to 80 to prevent timeout
            }
        }
    }
    free(classes);
    [log appendString:@"[DUMP END]"];
    
    // Send it while blocking the crash
    sendBlockingTelegram(log);
}

// --- ANTI-KILL HOOKS ---
// These hooks catch the app trying to kill itself

// 1. Hook the standard C exit() function
%hookf(void, exit, int status) {
    // App tried to die! Catch it.
    dumpSCClasses([NSString stringWithFormat:@"exit(%d) called", status]);
    
    // Now allow it to die
    %orig(status);
}

// 2. Hook the abort() function (used in crashes)
%hookf(void, abort) {
    dumpSCClasses(@"abort() called");
    %orig;
}

// 3. Hook the Main Bundle (Fallback Trigger)
// If the app doesn't crash, we trigger this manually 2 seconds in.
%hook NSBundle
- (NSString *)bundleIdentifier {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [NSThread sleepForTimeInterval:2.0];
            dumpSCClasses(@"Timer Trigger (2s)");
        });
    });
    return %orig;
}
%end

// --- CONSTRUCTOR ---
%ctor {
    // Initialize hooks immediately
    %init;
}
