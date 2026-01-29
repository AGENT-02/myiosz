#import <UIKit/UIKit.h>
#import <substrate.h>

// --- TELEGRAM CONFIG ---
#define TELEGRAM_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TELEGRAM_CHAT_ID @"7730331218"
#define THEME_COLOR [UIColor colorWithRed:0.0 green:1.0 blue:0.8 alpha:1.0]

// --- TELEMETRY ENGINE ---
// This bypasses the "vanishing menu" issue by sending data out immediately
void sendToTelegram(NSString *message) {
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage", TELEGRAM_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    NSString *postBody = [NSString stringWithFormat:@"chat_id=%@&text=%@", 
                         TELEGRAM_CHAT_ID, 
                         [message stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    [request setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Asynchronous request so it doesn't freeze the app
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSLog(@"[Enigma] Telemetry Sent Successfully.");
        }
    }] resume];
}

// --- UPDATED SECURITY AUDIT ---
// Automatically sends the "Sideload Fingerprint" report to your bot
void runRemoteAudit() {
    NSMutableString *auditReport = [NSMutableString stringWithString:@"🚨 ENIGMA REMOTE AUDIT 🚨\n\n"];
    
    // 1. Signature Check
    NSString *provisionPath = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    BOOL isSideloaded = [[NSFileManager defaultManager] fileExistsAtPath:provisionPath];
    [auditReport appendFormat:@"Sideloaded: %@\n", isSideloaded ? @"YES" : @"NO"];
    
    // 2. Bundle ID
    [auditReport appendFormat:@"Bundle ID: %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    
    // 3. Team ID Extraction
    if (isSideloaded) {
        NSString *profile = [NSString stringWithContentsOfFile:provisionPath encoding:NSISOLatin1StringEncoding error:nil];
        if ([profile containsString:@"<key>TeamIdentifier</key>"]) {
            [auditReport appendString:@"Team ID: Detected Unauthorized Signer\n"];
        }
    }
    
    [auditReport appendString:@"\n[!] Environment Likely Compromised (SS03 Error Trigger)."];
    
    sendToTelegram(auditReport);
}

// --- UPDATED HOOKS ---
%hook SCONeTapLoginMultiAccountLandingPage

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // The moment the screen appears, we dump data to Telegram 
    // This way, if Snap Zero kills the app, you already have the data!
    runRemoteAudit();
    
    NSString *classDump = @"[CLASS LOG] LandingPage View Controller initialized and active.";
    sendToTelegram(classDump);
}

%end

// --- MENU UI ---
// (Keep your existing EnigmaMenu UI code here)
