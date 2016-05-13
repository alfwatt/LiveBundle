#import "NSBundle+LiveBundle.h"
#import "NSDate+RFC1123.h"

NSString* const ILLiveBundles = @"LiveBundles";
NSString* const ILLiveBundleURLKey = @"ILLiveBundleURLKey";
NSString* const ILLiveBundleResourceUpdateNote = @"PluginLiveBundleResourceUpdateNote";

NSString* const NSBundlePlistType = @"plist";

#pragma mark -

@implementation NSBundle (LiveBundle)

+ (NSBundle*) bundleWithResource:(NSString*) name ofType:(NSString*) extension
{
    NSBundle* firstMatch = nil;
    for( NSBundle* appBundle in [NSBundle allBundles]) {
        if( [appBundle pathForResource:name ofType:extension]) {
            firstMatch = appBundle;
            break; // for
        }
    }
    return firstMatch;
}

+ (NSBundle*) frameworkWithResource:(NSString*) name ofType:(NSString*) extension
{
    NSBundle* firstMatch = nil;
    for( NSBundle* frameworkBundle in [NSBundle allFrameworks]) {
        if( [frameworkBundle pathForResource:name ofType:extension]) {
            firstMatch = frameworkBundle;
            break; // for
        }
    }
    return firstMatch;
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
    NSString* liveBundleURL = [[self infoDictionary] objectForKey:ILLiveBundleURLKey]; // this is set per-bundle
    return [NSURL URLWithString:[[liveBundleURL stringByAppendingPathComponent:resource] stringByAppendingPathExtension:type]];
}

/* @returns an interned NSString* with the path for the URL specified */
- (NSString*) livePathForResourceURL:(NSURL*) download
{
    static NSMutableDictionary* pathCache; // holds the interened paths, so that the NSNotifications are delivered

    if( !pathCache) {
        pathCache = [NSMutableDictionary new];
    }
    
    if( download && ![pathCache objectForKey:download]) {
        NSString* resourceFile = [download lastPathComponent];
        NSString* liveResourcePath = [[self liveBundlePath] stringByAppendingPathComponent:resourceFile];
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
    NSString* liveResourcePath = [self livePathForResourceURL:remoteResourceURL]; // this interns the string

    if( liveResourcePath) {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSError* error = nil;

        // check for existing live files
        if( ![fm fileExistsAtPath:[self liveBundlePath] isDirectory:nil]) {
            if( ![fm createDirectoryAtPath:[self liveBundlePath] withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"ERROR in livePathForResource can't create: %@ error: %@", [self liveBundlePath], error);
                return staticPath;
            }
        }

        // get some info
        NSDictionary* liveInfo = nil;
        NSDictionary* staticInfo = [fm attributesOfItemAtPath:staticPath error:nil];

        // does the live bundle path exist?
        if( [fm fileExistsAtPath:liveResourcePath isDirectory:nil]) {
            liveInfo = [fm attributesOfItemAtPath:liveResourcePath error:nil];
            
            if( ([liveInfo fileType] != NSFileTypeSymbolicLink) // nothing to do if it's a link already
               && ([[staticInfo fileModificationDate] timeIntervalSinceDate:[liveInfo fileModificationDate]] > 0)) { // check the dates on the file, was the bundle updated?
                if( ![fm removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
                    NSLog(@"ERROR in livePathForResource can't remove: %@ error: %@", liveResourcePath, error);
                    return staticPath;
                }
                
                if( ![fm createSymbolicLinkAtPath:liveResourcePath withDestinationPath:staticPath error:nil]) {
                    NSLog(@"ERROR in livePathForResrouce can't link: %@ -> %@ error: %@", staticPath, liveResourcePath, error);
                    return staticPath;
                }
            }
        }
        else { // if not, just link in the static path
            if( ![fm createSymbolicLinkAtPath:liveResourcePath withDestinationPath:staticPath error:&error]) {
                NSLog(@"ERROR in livePathForResrouce can't link: %@ -> %@ error: %@", staticPath, liveResourcePath, error);
                return staticPath;
            }
        }

        // info may have changed
        liveInfo = [fm attributesOfItemAtPath:liveResourcePath error:nil];

        // make sure the developer isn't a complete idiot
        if( [remoteResourceURL.scheme isEqualToString:@"https"]) {
            NSDate* resourceModificationTime = [staticInfo fileModificationDate];

            // get the date of the current live file, if it's not a link to the static file
            if( [liveInfo fileType] != NSFileTypeSymbolicLink)
                resourceModificationTime = [liveInfo fileModificationDate];

            // check for an existing temp file, remove it
            // TODO check for other downloads running in parallel
            NSString* tempFilePath = [self tempPathForResourceURL:remoteResourceURL];
            NSString* tempFileDir = [tempFilePath stringByDeletingLastPathComponent];

            
            if( ![fm fileExistsAtPath:tempFileDir isDirectory:nil]) {
                if( ![fm createDirectoryAtPath:tempFileDir withIntermediateDirectories:YES attributes:nil error:&error]) {
                    NSLog(@"ERROR in livePathForResource can't create: %@ error: %@", tempFileDir, error);
                    return staticPath;
                }
            }

            if( [fm fileExistsAtPath:tempFilePath isDirectory:nil]
             && ![fm removeItemAtURL:[NSURL fileURLWithPath:tempFilePath] error:&error]) {
                NSLog(@"ERROR in livePathForResource can't remove temp file: %@ error: %@", [NSURL fileURLWithPath:tempFilePath], error);
                return staticPath;
            }
            
            if( ![fm createFileAtPath:tempFilePath contents:nil attributes:nil]) {
                NSLog(@"ERROR in livePathForResource can't create: %@", tempFilePath);
                return staticPath;
            }

            // start a request against liveResourceURL and send a request with If-Modified-Since header
            NSMutableURLRequest* downloadRequest = [NSMutableURLRequest new];
            [downloadRequest setURL:remoteResourceURL];
            [downloadRequest addValue:[resourceModificationTime rfc1123String] forHTTPHeaderField:@"If-Modified-Since"];

            downloadRequest.cachePolicy = NSURLRequestReloadIgnoringCacheData;
            downloadRequest.HTTPShouldHandleCookies = NO;
            downloadRequest.timeoutInterval = 30; // shorter maybe?
            downloadRequest.HTTPMethod = @"GET";

            NSURLDownload* download = [[NSURLDownload alloc] initWithRequest:downloadRequest delegate:self];
            [download setDestination:tempFilePath allowOverwrite:YES];
        }
        else NSLog(@"WARNING livePathForResource can't load live bundle resrouces over an insecure connection. Or won't.");
    }
    else {
        NSLog(@"WARNING livePathForResource:%@ ofType:%@ could not determine liveResourcePath from URL: %@ (did you set ILLiveBundleURLKey in your Info.plist?) returning static path %@", resource, type, remoteResourceURL, staticPath);
        liveResourcePath = staticPath; // just provide the static path if the url hasn't been configured
    }

exit:
    
    return liveResourcePath;
}

- (NSURL*) liveURLForResource:(NSString*) resource withExtension:(NSString*) type
{
    return [NSURL fileURLWithPath:[self livePathForResource:resource ofType:type]];
}

#pragma mark - 

- (void)downloadDidBegin:(NSURLDownload*) download
{
//    NSLog(@"NSBundle+LiveBundle downloadDidBegin: %@", download);
}

- (NSURLRequest *)download:(NSURLDownload*) download willSendRequest:(NSURLRequest*) request redirectResponse:(NSURLResponse*) redirectResponse
{
    return request;
}

- (void)download:(NSURLDownload*) download didReceiveResponse:(NSURLResponse*) response
{
    // check for a response to see if the content exists and has been updated changed
    if( [response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger connectionStatus = [(NSHTTPURLResponse*)response statusCode];
        
        if( connectionStatus != 200) { // 404 and 304 would be the most common, but any non standard return should stop loading
            [download cancel];
        }
    }
}

- (void)download:(NSURLDownload*) download willResumeWithResponse:(NSURLResponse*) response fromByte:(long long)startingByte
{
//    NSLog(@"NSBundle+LiveBundle download: %@ willResumeWithResponse: %@ fromByte: %lli", download.request.URL, response, startingByte);
}

- (void)download:(NSURLDownload*) download didReceiveDataOfLength:(NSUInteger) length
{
//    NSLog(@"NSBundle+LiveBundle download: %@ didReceiveDataOfLength: %li", download.request.URL, length);
}

- (BOOL)download:(NSURLDownload*) download shouldDecodeSourceDataOfMIMEType:(NSString*) encodingType
{
    return YES;
}

- (void)download:(NSURLDownload*) download didCreateDestination:(NSString*) path
{
//    NSLog(@"NSBundle+LiveBundle download: %@ didCreateDestination: %@", download.request.URL, path);
}

- (void)downloadDidFinish:(NSURLDownload*) download
{
    NSString* tempFile = [self tempPathForResourceURL:download.request.URL];
    NSString* liveResourcePath = [self livePathForResourceURL:download.request.URL];
    
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* error = nil;

    // TODO check integrety of the temp file against HTTP MD5 header if provided
    
    // is something at the liveResourcePath already? we should remove that
    if( [fm fileExistsAtPath:liveResourcePath isDirectory:nil]) {
        if( ![fm removeItemAtURL:[NSURL fileURLWithPath:liveResourcePath] error:&error]) {
            NSLog(@"ERROR in connectionDidFinishLoading can't remove: %@ error: %@", liveResourcePath, error);
            goto exit;
        }
    }
    
    // the landing site it clear, move the temp file over to the resrouce path
    if( ![fm moveItemAtPath:tempFile toPath:liveResourcePath error:&error]) {
        NSLog(@"ERROR in connectionDidFinishLoading can't move: %@ -> %@ error: %@", tempFile, liveResourcePath, error);
        goto exit;
    }
    
//    if( DEBUG) NSLog(@"LiveBundle updated: %@", liveResourcePath);
    
    // file was moved into place sucessfully, tell the world
    [[NSNotificationCenter defaultCenter] postNotificationName:ILLiveBundleResourceUpdateNote object:liveResourcePath];
    
exit:
    return;
}

- (void)download:(NSURLDownload*) download didFailWithError:(NSError*) error
{
//    NSLog(@"ERROR NSBundle+LiveBundle download: %@ didFailWithError: %@", download, error);
}

@end
