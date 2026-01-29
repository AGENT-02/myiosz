#import <UIKit/UIKit.h>
#import <substrate.h>

// --- TELEGRAM CONFIG ---
#define TELEGRAM_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TELEGRAM_CHAT_ID @"7730331218"

// --- ATOMIC TELEMETRY ---
void sendAtomicLog(NSString *text) {
    // We use a background configuration to survive the app crash
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TG_BOT_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    
    NSString *body = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                     TG_CHAT_ID, [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    // Execute via a raw C-level session to avoid the Objective-C runtime overhead
    [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
}

// --- ATOMIC CONSTRUCTOR ---
// This runs the MOMENT the dylib is loaded into the process memory
__attribute__((constructor)) static void initializeEnigma() {
    // 1. Immediate Audit
    NSString *bID = [[NSBundle mainBundle] bundleIdentifier];
    BOOL isSidlo = [[NSFileManager defaultManager] fileExistsAtPath:[[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]];
    
    NSString *report = [NSString stringWithFormat:@"☢️ ATOMIC REPORT ☢️\nBundle: %@\nSideloaded: %@\nStatus: SS03 Detected", 
                        bID, isSidlo ? @"YES" : @"NO"];
    
    sendAtomicLog(report);
    
    // 2. Class Dump (Manual lookup of the class from your image)
    // If the app is closing, we dump the existence of the target class immediately
    if (objc_getClass("SCONeTapLoginMultiAccountLandingPage")) {
        sendAtomicLog(@"[✓] Target Class Found in Memory: SCONeTapLoginMultiAccountLandingPage");
    }
}
