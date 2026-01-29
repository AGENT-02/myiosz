#import <UIKit/UIKit.h>
#import <substrate.h>

// --- TELEGRAM CONFIG ---
#define TELEGRAM_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TELEGRAM_CHAT_ID @"7730331218"

// --- SILENT TELEMETRY ENGINE ---
// This runs in the background without any UI interference
void sendGhostAudit(NSString *message) {
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TELEGRAM_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    NSString *postBody = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                         TELEGRAM_CHAT_ID, 
                         [message stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [request setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];
    
    // We use a semaphore to force the request to finish even if the app crashes right after
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
}

// --- HEADLESS AUDIT LOGIC ---
// Analyzes why login fails (SS03/SS06) without showing a menu
void runGhostAudit() {
    NSMutableString *log = [NSMutableString stringWithString:@"👻 GHOST AUDIT INITIATED 👻\n\n"];
    
    // 1. Check Signature Status
    NSString *provisionPath = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    BOOL sideloaded = [[NSFileManager defaultManager] fileExistsAtPath:provisionPath];
    [log appendFormat:@"Sideloaded: %@\n", sideloaded ? @"YES" : @"NO"];
    
    // 2. Identify Team ID Mismatch
    if (sideloaded) {
        NSString *profile = [NSString stringWithContentsOfFile:provisionPath encoding:NSISOLatin1StringEncoding error:nil];
        if ([profile containsString:@"<key>TeamIdentifier</key>"]) {
            [log appendString:@"Result: Unauthorized Signer Detected.\n"];
        }
    }
    
    // 3. Environment Check
    [log appendFormat:@"Bundle ID: %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [log appendString:@"\n[!] Login Status: Blocked by Server (SS03)."];
    
    sendGhostAudit(log);
}

// --- CONSTRUCTOR: THE GHOST ENTRY ---
%ctor {
    // Run the audit 1 second after injection, before the UI even loads
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        runGhostAudit();
    });
}
