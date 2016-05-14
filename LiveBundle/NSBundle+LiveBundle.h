
#import <Foundation/Foundation.h>

/*! @const the base URL for this live bundle, which will be checked for updates of live files */
extern NSString* const ILLiveBundleURLKey;

/*! @const notification sent when a given plugin resource has been updated */
extern NSString* const ILLiveBundleResourceUpdateNote;

@interface NSBundle (LiveBundle) <NSURLDownloadDelegate>

/*! @returns the NSBundle in the current application with the named resource of the type provided */
+ (NSBundle*) bundleWithResource:(NSString*) name ofType:(NSString*) extension;

/*! @returns the NSBundle of a Framework in the current applicaiton with the named resource of the type provided */
+ (NSBundle*) frameworkWithResource:(NSString*) name ofType:(NSString*) extension;

/*! @returns the local path for the live bundle in the user's Application Support directory */
- (NSString*) liveBundlePath;

/*! @returns the remote URL for the resource specified */
- (NSURL*) remoteURLForResource:(NSString*) resource withExtension:(NSString*) type;

/*! @returns the temp path for downloading a particular URL */
- (NSString*) tempPathForResourceURL:(NSURL*) download;

/*! @returns the live path for the remote URL specified */
- (NSString*) livePathForResourceURL:(NSURL*) download;

/*! @returns the live path for the resource specified, and initiates the check process

    @abstract NB: only call this method once per launch per resource to prevent exessive network traffic
 
    Map a 'static' filename from the Resources directory of the bundle and place a link in the in the user's library folder,
    then check ILLiveBundleURLKey for an updated version of the resource, download it to the live path and notify any
    listeners with ILLiveBundleResourceUpdateNote if a new version is avaliable.

    The updatede version of the resource is cahced locally and will be loaded preferentially on the next app load.

    e.g. for an example app with the ILLiveBundleURLKey of: https://example.com/livebundle

    Example.app/Contents/Resources/example.plist
    -> ~/Library/Application Support/LiveBundles/com.example.app/example.plist
    -> https://example.com/livebundle/example.plist

*/
- (NSString*) livePathForResource:(NSString*) resrouces ofType:(NSString*) type;

@end
