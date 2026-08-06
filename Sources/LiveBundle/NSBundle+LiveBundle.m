#import "NSBundle+LiveBundle.h"
#import "NSDate+RFC1123.h"

NSString* const ILLiveBundles = @"LiveBundles";
NSString* const ILLiveBundleURLKey = @"ILLiveBundleURLKey";
NSString* const ILLiveBundleResourceUpdateNote = @"PluginLiveBundleResourceUpdateNote";
NSString* const ILPlistType = @"plist";

// MARK: -

@implementation NSBundle (LiveBundle)

+ (NSBundle*) bundleWithResource:(NSString*) name ofType:(NSString*) extension {
    NSBundle* firstMatch = nil;
    for (NSBundle* appBundle in [NSBundle allBundles]) {
        if ([appBundle pathForResource:name ofType:extension]) {
            firstMatch = appBundle;
            break; // for
        }
    }

    return firstMatch;
}

+ (NSBundle*) frameworkWithResource:(NSString*) name ofType:(NSString*) extension {
    NSBundle* firstMatch = nil;
    for (NSBundle* frameworkBundle in [NSBundle allFrameworks]) {
        if ([frameworkBundle pathForResource:name ofType:extension]) {
            firstMatch = frameworkBundle;
            break; // for
        }
    }

    return firstMatch;
}

+ (BOOL) trashLiveBundles:(NSError**) error {
    NSArray* searchPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSURL* liveBundlesURL = [NSURL fileURLWithPath:[searchPaths.lastObject stringByAppendingPathComponent:ILLiveBundles]];

    return [NSFileManager.defaultManager removeItemAtURL:liveBundlesURL error:error];
}

+ (BOOL) trashLiveBundles {
    NSError* trashError = nil;
    BOOL wasTrashed = [self trashLiveBundles:&trashError];
    if (!wasTrashed) {
        NSLog(@"ERROR trashLiveBundles error: %@", trashError);
    }

    return wasTrashed;
}

// MARK: -

- (NSString*) liveBundlePath {
    return [[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject]
             stringByAppendingPathComponent:ILLiveBundles]
             stringByAppendingPathComponent:[self bundleIdentifier]];
}

- (NSURL*) remoteURLForResource:(NSString*) resource withExtension:(NSString*) type {
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
- (NSString*) livePathForResourceURL:(NSURL*) download {
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
- (NSString*) tempPathForResourceURL:(NSURL*) download {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[download resourceSpecifier]];
}

- (NSString*) livePathForResource:(NSString*) resource ofType:(NSString*) type {
    NSURL* remoteResourceURL = [self remoteURLForResource:resource withExtension:type]; // URL to the resource
    NSString* liveResourcePath = [self livePathForResourceURL:remoteResourceURL]; // path the app will use
    NSString* staticResourcePath = [self pathForResource:resource ofType:type]; // path to the resource in the app bundle

    if (staticResourcePath && liveResourcePath) {
        NSError* error = nil;
        BOOL isDirectory = NO;

#if DEBUG
        // check for Xcode/DerivedData in the staticPath, don't link up to build products or simulator resources
        if (([staticResourcePath rangeOfString:@"Xcode/DerivedData"].location != NSNotFound)
         || ([staticResourcePath rangeOfString:@"Developer/CoreSimulator"].location != NSNotFound)) {
            NSLog(@"DEBUG LiveBundle using staticPath: %@ remoteURL: %@", staticResourcePath, remoteResourceURL);
            return staticResourcePath;
        }
#endif

        // check for existance of file at staticResourcePath, and that it's not a directory
        if (![NSFileManager.defaultManager fileExistsAtPath:staticResourcePath isDirectory:&isDirectory]) {
            NSLog(@"WARNING LiveBundle livePathForResource can't find static resource: %@", staticResourcePath);
            return staticResourcePath;
        }
        else if (isDirectory) {
            NSLog(@"WARNING LiveBundle livePathForResource can't link live resource: %@ is a directory", staticResourcePath);
            return staticResourcePath;
        }

        // check for existing liveBundlePath, create if necessary
        isDirectory = NO;
        BOOL liveBundlePathExists = [NSFileManager.defaultManager fileExistsAtPath:self.liveBundlePath isDirectory:&isDirectory];
        if (liveBundlePathExists && !isDirectory) { // regular file in the way, attempt to remove it
            if (![NSFileManager.defaultManager removeItemAtPath:self.liveBundlePath error:&error]) {
                NSLog(@"ERROR LiveBundle livePathForResource can't remove: %@ error: %@", self.liveBundlePath, error);
                return staticResourcePath;
            }
            liveBundlePathExists = NO; // recently removed
        }

        // path either didn't exist, or was sucessfully removed
        if (!liveBundlePathExists && ![NSFileManager.defaultManager createDirectoryAtPath:self.liveBundlePath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"ERROR LiveBundle livePathForResource can't create: %@ error: %@", [self liveBundlePath], error);
            return staticResourcePath;
        }

        // check for read write permission of the liveBundlePath
        if (![NSFileManager.defaultManager isWritableFileAtPath:self.liveBundlePath]
         || ![NSFileManager.defaultManager isReadableFileAtPath:self.liveBundlePath]) { // we can't access the path
            NSLog(@"ERROR LiveBundle livePathForResource can't read or write to: %@", self.liveBundlePath);
            return staticResourcePath;
        }

        // get info for the static and live paths
        NSDictionary* staticInfo = [NSFileManager.defaultManager attributesOfItemAtPath:staticResourcePath error:&error];
        NSDictionary* liveInfo = [NSFileManager.defaultManager attributesOfItemAtPath:liveResourcePath error:&error];

        if (liveInfo) { // file exists at liveResourcePath, validate it
            BOOL isValid = NO;
            isDirectory = NO;
            // if there is a link, check that it's correctly pointing to the staticResourcePath
            if (liveInfo && (liveInfo[NSFileType] == NSFileTypeSymbolicLink)) {
                NSString* livePathLinkTarget = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:liveResourcePath error:&error];
                if (livePathLinkTarget // can't happen
                 && [NSFileManager.defaultManager fileExistsAtPath:livePathLinkTarget isDirectory:&isDirectory] // points somewhere
                 && !isDirectory // that's not a directory
                 && [livePathLinkTarget isEqualToString:staticResourcePath]) { // and is the static path
                    isValid = YES;
                }
            } // if it isn't a link, validate the liveResourcePath; is not a directory, and not an empty file
            else if ([NSFileManager.defaultManager fileExistsAtPath:liveResourcePath isDirectory:&isDirectory]
                && (!isDirectory || liveInfo[NSFileSize] > 0)) {
                    isValid = YES;
            }

            if (!isValid) { // attempt to remove the link, directory, or empty file from the live path
                if (![NSFileManager.defaultManager removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
                    NSLog(@"ERROR in LiveBundle livePathForResource can't remove: %@ error: %@", liveResourcePath, error);
                    return staticResourcePath;
                }

                liveInfo = nil;
            }
        }

        // check to see if a file exists, we canot rely on liveInfo because validation might delete what's there
        if (![NSFileManager.defaultManager fileExistsAtPath:liveResourcePath isDirectory:nil]) {
            if (![NSFileManager.defaultManager createSymbolicLinkAtPath:liveResourcePath withDestinationPath:staticResourcePath error:&error]) {
                NSLog(@"ERROR in livePathForResrouce can't link: %@ -> %@ error: %@", staticResourcePath, liveResourcePath, error);
                return staticResourcePath;
            }
        }

        // everything is validated and up to date, info may have changed
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
        NSLog(@"WARNING livePathForResource:%@ ofType:%@ could not determine liveResourcePath from URL: %@ (did you set ILLiveBundleURLKey in your Info.plist?) returning static path %@", resource, type, remoteResourceURL, staticResourcePath);

        liveResourcePath = staticResourcePath;
    }

    return liveResourcePath;
}

// MARK: - NSURLSessionDelegate Methods

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    if (error) {
        NSLog(@"ERROR URLSession: %@ didBecomeInvalidWithError: %@", session, error);
    }
}

// MARK: - NSURLSessionTaskDelegate Methods

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
}

// MARK: - NSURLSessionDownloadDelegate Methods

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)download didFinishDownloadingToURL:(NSURL *)fileURL {
    if ([download.response isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse*)download.response statusCode] == 200) { // OK!
        NSString* liveResourcePath = [self livePathForResourceURL:download.originalRequest.URL];
        NSError* error = nil;

        // TODO check integrety of the temp file against HTTP MD5 header if provided
        // is something at the liveResourcePath already? we should remove that
        if ([NSFileManager.defaultManager fileExistsAtPath:liveResourcePath isDirectory:nil]) {
            if (![NSFileManager.defaultManager removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
                NSLog(@"ERROR in connectionDidFinishLoading can't remove: %@ error: %@", liveResourcePath, error);
                goto exit;
            }
        }

        // the landing site it clear, move the temp file over to the resrouce path
        if (![NSFileManager.defaultManager moveItemAtPath:fileURL.path toPath:liveResourcePath error:&error]) {
            NSLog(@"ERROR in connectionDidFinishLoading can't move: %@ -> %@ error: %@", fileURL.path, liveResourcePath, error);
            goto exit;
        }

#if DEBUG
        NSLog(@"DEBUG LiveBundle updated: %@ from: %@ original: %@", liveResourcePath,
              download.currentRequest.URL, download.originalRequest.URL);
#endif

        // file was moved into place sucessfully, tell the world
        [NSNotificationCenter.defaultCenter postNotificationName:ILLiveBundleResourceUpdateNote object:liveResourcePath];
    }
    else {
        // NSLog(@"NOTE: session %@ ended with response: %@", session, download.response); // 304 is expected for out of date items
    }
exit:
    return;
}

@end
