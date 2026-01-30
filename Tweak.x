#import <UIKit/UIKit.h>
#import <substrate.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"

// --- HELPER: CREATE MULTIPART BODY ---
NSData *createBody(NSString *boundary, NSString *filename, NSData *data) {
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"document\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: text/plain\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

// --- MAIN FUNCTION ---
void scanAndSendFileList() {
    // 1. Scan the Bundle
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSArray *files = [fm contentsOfDirectoryAtPath:bundlePath error:nil];
    
    // 2. Create the List String
    NSMutableString *list = [NSMutableString stringWithFormat:@"=== APP BUNDLE FILE LIST ===\nPath: %@\nFiles: %lu\n\n", bundlePath, (unsigned long)files.count];
    
    for (NSString *file in files) {
        // Simple filter to remove noise (optional, you can remove this if you want everything)
        if (![file hasSuffix:@".png"] && ![file hasSuffix:@".car"] && ![file hasSuffix:@".lproj"]) {
            [list appendFormat:@"%@\n", file];
        }
    }
    
    NSData *fileData = [list dataUsingEncoding:NSUTF8StringEncoding];
    
    // 3. Upload to Telegram
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument?chat_id=%@", TG_TOKEN, TG_CHAT_ID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    
    NSString *boundary = @"Boundary-FileList";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:createBody(boundary, @"Bundle_File_List.txt", fileData)];
    
    // Fire Request
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:nil] resume];
}

%ctor {
    // Run immediately in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        scanAndSendFileList();
    });
}
