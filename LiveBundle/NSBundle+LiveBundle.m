#import "NSBundle+LiveBundle.h"
#import "NSDate+RFC1123.h"

NSString* const ILLiveBundles = @"LiveBundles";
NSString* const ILLiveBundleURLKey = @"ILLiveBundleURLKey";
NSString* const ILLiveBundleResourceUpdateNote = @"PluginLiveBundleResourceUpdateNote";
NSString* const ILPlistType = @"plist";

#pragma mark -

@implementation NSBundle (LiveBundle)

+ (NSBundle*) bundleWithResource:(NSString*) name ofType:(NSString*) extension
{
    NSBundle* firstMatch = nil;
    for (NSBundle* appBundle in [NSBundle allBundles]) {
        if ([appBundle pathForResource:name ofType:extension]) {
            firstMatch = appBundle;
            break; // for
        }
    }
    return firstMatch;
}

+ (NSBundle*) frameworkWithResource:(NSString*) name ofType:(NSString*) extension
{
    NSBundle* firstMatch = nil;
    for (NSBundle* frameworkBundle in [NSBundle allFrameworks]) {
        if ([frameworkBundle pathForResource:name ofType:extension]) {
            firstMatch = frameworkBundle;
            break; // for
        }
    }
    return firstMatch;
}

+ (BOOL) trashLiveBundles:(NSError**) error
{
    NSArray* searchPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSURL* liveBundlesURL = [NSURL fileURLWithPath:[searchPaths.lastObject stringByAppendingPathComponent:ILLiveBundles]];
#if TARGET_OS_MAC
    return [NSFileManager.defaultManager trashItemAtURL:liveBundlesURL resultingItemURL:nil error:error];
#else
    return [NSFileManager.defaultManager removeItemAtURL:liveBundlesURL error:error];
#endif
}

+ (BOOL) trashLiveBundles
{
    NSError* trashError = nil;
    BOOL wasTrashed = [self trashLiveBundles:&trashError];
    if (!wasTrashed) {
        NSLog(@"trashLiveBundles error: %@", trashError);
    }
    return wasTrashed;
}

#pragma mark -

- (NSString*) liveBundlePath
{
    return [[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject]
             stringByAppendingPathComponent:ILLiveBundles]
             stringByAppendingPathComponent:[self bundleIdentifier]];
}

- (NSURL*) remoteURLForResource:(NSString*) resource withExtension:(NSString*) type
{
    NSURL* remoteURL = nil;
    NSString* bundleURL = [[self infoDictionary] objectForKey:ILLiveBundleURLKey]; // this is set per-bundle
    if (bundleURL) {
        NSURL* liveBundleURL = [NSURL URLWithString:bundleURL];
        remoteURL = [[liveBundleURL URLByAppendingPathComponent:resource] URLByAppendingPathExtension:type];
    }
    else NSLog(@"WARNING LiveBundle remoteURLForResource:... %@ infoDictionary does not contain an ILLiveBundleURLKey", self);
    
    return remoteURL;
}

/* @returns an interned NSString* with the path for the URL specified */
- (NSString*) livePathForResourceURL:(NSURL*) download
{
    static NSMutableDictionary* pathCache; // holds the interened paths, so that the NSNotifications are delivered

    if (!pathCache) {
        pathCache = NSMutableDictionary.new;
    }
    
    if (download && ![pathCache objectForKey:download]) {
        NSString* resourceFile = [download lastPathComponent];
        NSString* liveResourcePath = [self.liveBundlePath stringByAppendingPathComponent:resourceFile];
        [pathCache setObject:liveResourcePath forKey:download];
    }

    return [pathCache objectForKey:download];
}

/** @returns the temp path for a given url download */
- (NSString*) tempPathForResourceURL:(NSURL*) download
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[download resourceSpecifier]];
}

- (NSString*) livePathForResource:(NSString*) resource ofType:(NSString*) type
{
    NSURL* remoteResourceURL = [self remoteURLForResource:resource withExtension:type];
    NSString* staticPath = [self pathForResource:resource ofType:type];
    NSString* liveResourcePath = [self livePathForResourceURL:remoteResourceURL]; // interned the string

    if (liveResourcePath) {
        NSError* error = nil;

        // check for existing live files
        if (![NSFileManager.defaultManager fileExistsAtPath:self.liveBundlePath isDirectory:nil]) {
            if (![NSFileManager.defaultManager createDirectoryAtPath:self.liveBundlePath withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"ERROR LiveBundle livePathForResource can't create: %@ error: %@", [self liveBundlePath], error);
                return staticPath;
            }
        }

        // check for read write permission in the resource path
        if (![NSFileManager.defaultManager isWritableFileAtPath:self.liveBundlePath]
         || ![NSFileManager.defaultManager isReadableFileAtPath:self.liveBundlePath]) { // we can't access the path
            NSLog(@"ERROR LiveBundle livePathForResource can't read or write to: %@", self.liveBundlePath);
            return staticPath;
        }

        // get some info
        NSDictionary* liveInfo = nil;
        NSDictionary* staticInfo = [NSFileManager.defaultManager attributesOfItemAtPath:staticPath error:&error];

#if DEBUG
        // check for Xcode/DerivedData in the staticPath, don't link up build products
        if ([staticPath rangeOfString:@"Xcode/DerivedData"].location != NSNotFound) {
            NSLog(@"DEBUG LiveBundle using staticPath: %@ remoteURL: %@", staticPath, remoteResourceURL);
            return staticPath;
        }
#endif
        
        // does the live bundle path exist?
        if ([NSFileManager.defaultManager fileExistsAtPath:liveResourcePath isDirectory:nil]) {
            liveInfo = [NSFileManager.defaultManager attributesOfItemAtPath:liveResourcePath error:nil];
            
            // check the dates on the file, was the bundle updated?
            if ((([staticInfo.fileModificationDate timeIntervalSinceDate:[liveInfo fileModificationDate]] > 0) // check for old-ness
              || (liveInfo.fileSize == 0))) { // also cleanup any random empty files
                // remove the old or empty version of the resource from the live path
                if (![NSFileManager.defaultManager removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
                    NSLog(@"ERROR in LiveBundle livePathForResource can't remove: %@ error: %@", liveResourcePath, error);
                    return staticPath;
                }
                // link in the updated resource from the app bundle
                if (![NSFileManager.defaultManager createSymbolicLinkAtPath:liveResourcePath withDestinationPath:staticPath error:nil]) {
                    NSLog(@"ERROR in LiveBundle livePathForResrouce can't link after removing: %@ -> %@ error: %@",
                        staticPath, liveResourcePath, error);
                    return staticPath;
                }
            }
        }
        else { // if not, just link in the static path
            if (![NSFileManager.defaultManager createSymbolicLinkAtPath:liveResourcePath withDestinationPath:staticPath error:&error]) {
                NSLog(@"ERROR in livePathForResrouce can't link: %@ -> %@ error: %@ info: %@",
                    staticPath, liveResourcePath, error, staticInfo);
                return staticPath;
            }
        }

        // info may have changed
        liveInfo = [NSFileManager.defaultManager attributesOfItemAtPath:liveResourcePath error:nil];

        // make sure the developer isn't a complete idiot
        if ([remoteResourceURL.scheme isEqualToString:@"https"]) {
            NSDate* resourceModificationTime = [staticInfo fileModificationDate];

            // get the date of the current live file, if it's not a link to the static file
            if ([liveInfo fileType] != NSFileTypeSymbolicLink) {
                resourceModificationTime = [liveInfo fileModificationDate];
            }

            // start a request against liveResourceURL and send a request with If-Modified-Since header
            NSMutableURLRequest* downloadRequest = [NSMutableURLRequest new];
            [downloadRequest setURL:remoteResourceURL];
            [downloadRequest addValue:[resourceModificationTime rfc1123String] forHTTPHeaderField:@"If-Modified-Since"];

            downloadRequest.cachePolicy = NSURLRequestReloadIgnoringCacheData;
            downloadRequest.HTTPShouldHandleCookies = NO;
            downloadRequest.timeoutInterval = 30; // shorter maybe?
            downloadRequest.HTTPMethod = @"GET";

            NSURLSession* session = [NSURLSession
                sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                delegate:self
                delegateQueue:[NSOperationQueue mainQueue]];
            NSURLSessionTask* download = [session downloadTaskWithRequest:downloadRequest];
            [download resume];
        }
        else NSLog(@"WARNING livePathForResource will not load resrouces over an insecure connection.\n\nUse https://letsencrypt.org to get free SSL certs for your site\n\n");
    }
    else {
        NSLog(@"WARNING livePathForResource:%@ ofType:%@ could not determine liveResourcePath from URL: %@ (did you set ILLiveBundleURLKey in your Info.plist?) returning static path %@", resource, type, remoteResourceURL, staticPath);
        liveResourcePath = staticPath; // just provide the static path if the url hasn't been configured
    }

exit:
    
    return liveResourcePath;
}

#pragma mark - NSURLSessionDelegate Methods

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    if (error) {
        NSLog(@"URLSession: %@ didBecomeInvalidWithError: %@", session, error);
    }
}

#pragma mark - NSURLSessionTaskDelegate Methods

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler
{
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
}

#pragma mark - NSURLSessionDownloadDelegate Methods

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)download didFinishDownloadingToURL:(NSURL *)fileURL
{
    if ([download.response isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse*)download.response statusCode] == 200) { // OK!
        NSString* liveResourcePath = [self livePathForResourceURL:download.originalRequest.URL];
        
        NSFileManager* fm = [NSFileManager defaultManager];
        NSError* error = nil;
        
        // TODO check integrety of the temp file against HTTP MD5 header if provided
        
        // is something at the liveResourcePath already? we should remove that
        if ([fm fileExistsAtPath:liveResourcePath isDirectory:nil]) {
            if (![fm removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
                NSLog(@"ERROR in connectionDidFinishLoading can't remove: %@ error: %@", liveResourcePath, error);
                goto exit;
            }
        }
        
        // the landing site it clear, move the temp file over to the resrouce path
        if (![fm moveItemAtPath:fileURL.path toPath:liveResourcePath error:&error]) {
            NSLog(@"ERROR in connectionDidFinishLoading can't move: %@ -> %@ error: %@", fileURL.path, liveResourcePath, error);
            goto exit;
        }
        
        //    if( DEBUG) NSLog(@"LiveBundle updated: %@", liveResourcePath);
        
        // file was moved into place sucessfully, tell the world
        [[NSNotificationCenter defaultCenter] postNotificationName:ILLiveBundleResourceUpdateNote object:liveResourcePath];
    }
    else {
        // NSLog(@"NOTE: session %@ ended with response: %@", session, download.response); // 304 is expected for out of date items
    }
exit:
    return;
}

@end
