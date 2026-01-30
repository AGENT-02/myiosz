#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
// --- WORKER THREAD ---
void performPanicDump() {
    NSLog(@"[Enigma] Worker thread started...");
    
    // 1. GATHER DATA
    NSMutableString *log = [NSMutableString stringWithFormat:@"❄️ TIME-FREEZE DUMP ❄️\n"];
    
    // Check for the specific class you wanted
    Class target = objc_getClass("SCONeTapLoginMultiAccountLandingPage");
    if (target) {
        [log appendString:@"[✓] SCONeTapLoginMultiAccountLandingPage: FOUND\n"];
        [log appendFormat:@"Memory Address: %p\n", target];
    } else {
        [log appendString:@"[X] Target Class: NOT FOUND (yet)\n"];
    }
    
    // Check Environment
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    [log appendFormat:@"Bundle: %@\n", bundle];
    
    // 2. SEND TO TELEGRAM (Synchronous Request)
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TG_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    
    NSString *body = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                     TG_CHAT_ID, [log stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    
    // We use a semaphore to ensure the network request completes before we release the freeze
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) NSLog(@"[Enigma] Error: %@", e);
        else NSLog(@"[Enigma] Success!");
        dispatch_semaphore_signal(sema);
    }] resume];
    
    // Wait max 3 seconds for upload
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
}

// --- THE FREEZE CONSTRUCTOR ---
// This runs BEFORE the app's 'main' function
__attribute__((constructor)) static void freezeAndExfiltrate() {
    
    // 1. Spawn a background thread to do the work
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        performPanicDump();
    });
    
    // 2. FREEZE THE MAIN THREAD
    // This stops the app from launching (and crashing) for 2 seconds.
    // During this 2 seconds, the background thread above sends the message.
    NSLog(@"[Enigma] Freezing Main Thread for 2 seconds...");
    [NSThread sleepForTimeInterval:2.0];
    NSLog(@"[Enigma] Thawing...");
}
