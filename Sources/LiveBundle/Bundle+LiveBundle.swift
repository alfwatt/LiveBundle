import Foundation

/// The key in a bundle's Info.plist that specifies the base URL to check for live updates of its resources.
public let LiveBundleURLKey = "ILLiveBundleURLKey"

/// Posted when a live bundle resource has finished downloading, with the resource's local file path as the notification's object.
public let LiveBundleResourceUpdateNotification = Notification.Name("PluginLiveBundleResourceUpdateNote")

/// The `plist` resource type.
public let LiveBundlePlistType = "plist"

/// Objective-C-compatible access to LiveBundle's notification name and Info.plist key, which can't be
/// exposed directly since top-level Swift globals aren't visible to Objective-C.
@objc(LiveBundleConstants)
public final class LiveBundleConstants: NSObject {
    @objc public static let resourceUpdateNotification = LiveBundleResourceUpdateNotification
    @objc public static let urlKey = LiveBundleURLKey
}

private let liveBundlesDirectoryName = "LiveBundles"

private let liveResourcePathCacheLock = NSLock()
@MainActor private var liveResourcePathCache: [URL: String] = [:]

public extension Bundle {

    /// Returns the bundle among all loaded bundles that contains the named resource of the type provided.
    static func bundle(withResource name: String, ofType type: String?) -> Bundle? {
        Bundle.allBundles.first { $0.path(forResource: name, ofType: type) != nil }
    }

    /// Returns the framework bundle in the current application that contains the named resource of the type provided.
    static func framework(withResource name: String, ofType type: String?) -> Bundle? {
        Bundle.allFrameworks.first { $0.path(forResource: name, ofType: type) != nil }
    }

    /// Moves the application's LiveBundles directory to the trash. Returns `true` on success.
    @discardableResult
    static func trashLiveBundles() -> Bool {
        do {
            try FileManager.default.removeItem(at: liveBundlesDirectoryURL)
            return true
        } catch {
            NSLog("ERROR trashLiveBundles error: \(error)")
            return false
        }
    }

    private static var liveBundlesDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent(liveBundlesDirectoryName)
    }

    // MARK: -

    /// The local path for this bundle's live resources in the user's Application Support directory.
    var liveBundlePath: String {
        Bundle.liveBundlesDirectoryURL.appendingPathComponent(bundleIdentifier ?? "").path
    }

    /// The remote URL for the resource specified, built from the bundle's `LiveBundleURLKey` Info.plist entry.
    func remoteURL(forResource resource: String, withExtension type: String) -> URL? {
        guard let bundleURLString = infoDictionary?[LiveBundleURLKey] as? String,
              let liveBundleURL = URL(string: bundleURLString) else {
            NSLog("WARNING LiveBundle remoteURLForResource:... \(self) infoDictionary does not contain an ILLiveBundleURLKey")
            return nil
        }

        return liveBundleURL.appendingPathComponent(resource).appendingPathExtension(type)
    }

    /// The temp path for downloading a particular URL.
    func tempPath(forResourceURL download: URL) -> String {
        let specifier = (download as NSURL).resourceSpecifier ?? download.lastPathComponent
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(specifier)
    }

    /// The live path for the remote URL specified.
    @MainActor func livePath(forResourceURL download: URL?) -> String? {
        guard let download else { return nil }

        liveResourcePathCacheLock.lock()
        defer { liveResourcePathCacheLock.unlock() }

        if let cached = liveResourcePathCache[download] {
            return cached
        }

        let resourceFile = download.lastPathComponent
        let path = (liveBundlePath as NSString).appendingPathComponent(resourceFile)
        liveResourcePathCache[download] = path
        return path
    }

    /// The live path for the resource specified, and initiates the check process.
    ///
    /// NB: only call this method once per launch per resource to prevent excessive network traffic.
    ///
    /// Maps a 'static' filename from the Resources directory of the bundle and places a link in the user's
    /// library folder, then checks `LiveBundleURLKey` for an updated version of the resource, downloads it to
    /// the live path and notifies any listeners with `LiveBundleResourceUpdateNotification` if a new version
    /// is available.
    ///
    /// The updated version of the resource is cached locally and will be loaded preferentially on the next app load.
    ///
    /// e.g. for an example app with the `LiveBundleURLKey` of: https://example.com/livebundle
    ///
    /// Example.app/Contents/Resources/example.plist
    /// -> ~/Library/Application Support/LiveBundles/com.example.app/example.plist
    /// -> https://example.com/livebundle/example.plist
    @objc @MainActor func livePath(forResource resource: String, ofType type: String) -> String? {
        let remoteResourceURL = remoteURL(forResource: resource, withExtension: type)
        let liveResourcePath = livePath(forResourceURL: remoteResourceURL)
        let staticResourcePath = path(forResource: resource, ofType: type)

        guard let staticResourcePath, let liveResourcePath else {
            NSLog("WARNING livePathForResource:\(resource) ofType:\(type) could not determine liveResourcePath from URL: \(String(describing: remoteResourceURL)) (did you set ILLiveBundleURLKey in your Info.plist?) returning static path \(String(describing: staticResourcePath))")
            return staticResourcePath
        }

        let fileManager = FileManager.default

        #if DEBUG
        // check for Xcode/DerivedData in the staticPath, don't link up to build products or simulator resources
        if staticResourcePath.contains("Xcode/DerivedData") || staticResourcePath.contains("Developer/CoreSimulator") {
            NSLog("DEBUG LiveBundle using staticPath: \(staticResourcePath) remoteURL: \(String(describing: remoteResourceURL))")
            return staticResourcePath
        }
        #endif

        // check for existence of file at staticResourcePath, and that it's not a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: staticResourcePath, isDirectory: &isDirectory) else {
            NSLog("WARNING LiveBundle livePathForResource can't find static resource: \(staticResourcePath)")
            return staticResourcePath
        }
        guard !isDirectory.boolValue else {
            NSLog("WARNING LiveBundle livePathForResource can't link live resource: \(staticResourcePath) is a directory")
            return staticResourcePath
        }

        // check for existing liveBundlePath, create if necessary
        isDirectory = false
        let liveBundlePathExists = fileManager.fileExists(atPath: liveBundlePath, isDirectory: &isDirectory)
        if liveBundlePathExists && !isDirectory.boolValue { // regular file in the way, attempt to remove it
            do {
                try fileManager.removeItem(atPath: liveBundlePath)
            } catch {
                NSLog("ERROR LiveBundle livePathForResource can't remove: \(liveBundlePath) error: \(error)")
                return staticResourcePath
            }
        }

        // path either didn't exist, or was successfully removed
        if !(liveBundlePathExists && isDirectory.boolValue) {
            do {
                try fileManager.createDirectory(atPath: liveBundlePath, withIntermediateDirectories: true)
            } catch {
                NSLog("ERROR LiveBundle livePathForResource can't create: \(liveBundlePath) error: \(error)")
                return staticResourcePath
            }
        }

        // check for read write permission of the liveBundlePath
        guard fileManager.isWritableFile(atPath: liveBundlePath), fileManager.isReadableFile(atPath: liveBundlePath) else {
            NSLog("ERROR LiveBundle livePathForResource can't read or write to: \(liveBundlePath)")
            return staticResourcePath
        }

        // get info for the static and live paths
        let staticInfo = try? fileManager.attributesOfItem(atPath: staticResourcePath)
        var liveInfo = try? fileManager.attributesOfItem(atPath: liveResourcePath)

        if liveInfo != nil { // file exists at liveResourcePath, validate it
            var isValid = false
            isDirectory = false

            // if there is a link, check that it's correctly pointing to the staticResourcePath
            if (liveInfo?[.type] as? FileAttributeType) == .typeSymbolicLink {
                if let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: liveResourcePath),
                   fileManager.fileExists(atPath: linkTarget, isDirectory: &isDirectory),
                   !isDirectory.boolValue, // that's not a directory
                   linkTarget == staticResourcePath { // and is the static path
                    isValid = true
                }
            } // if it isn't a link, validate the liveResourcePath; is not a directory, and not an empty file
            else if fileManager.fileExists(atPath: liveResourcePath, isDirectory: &isDirectory),
                    !isDirectory.boolValue || ((liveInfo?[.size] as? Int) ?? 0) > 0 {
                isValid = true
            }

            if !isValid { // attempt to remove the link, directory, or empty file from the live path
                do {
                    try fileManager.removeItem(atPath: liveResourcePath)
                } catch {
                    NSLog("ERROR in LiveBundle livePathForResource can't remove: \(liveResourcePath) error: \(error)")
                    return staticResourcePath
                }

                liveInfo = nil
            }
        }

        // check to see if a file exists, we cannot rely on liveInfo because validation might delete what's there
        if !fileManager.fileExists(atPath: liveResourcePath) {
            do {
                try fileManager.createSymbolicLink(atPath: liveResourcePath, withDestinationPath: staticResourcePath)
            } catch {
                NSLog("ERROR in livePathForResource can't link: \(staticResourcePath) -> \(liveResourcePath) error: \(error)")
                return staticResourcePath
            }
        }

        // everything is validated and up to date, info may have changed
        liveInfo = try? fileManager.attributesOfItem(atPath: liveResourcePath)

        // make sure the developer isn't a complete idiot
        guard let remoteResourceURL else {
            return liveResourcePath
        }

        guard remoteResourceURL.scheme == "https" else {
            NSLog("WARNING livePathForResource will not load resources over an insecure connection.\n\nUse https://letsencrypt.org to get free SSL certs for your site\n\n")
            return liveResourcePath
        }

        var resourceModificationTime = staticInfo?[.modificationDate] as? Date

        // get the date of the current live file, if it's not a link to the static file
        if (liveInfo?[.type] as? FileAttributeType) != .typeSymbolicLink {
            resourceModificationTime = liveInfo?[.modificationDate] as? Date
        }

        // start a request against liveResourceURL and send a request with If-Modified-Since header
        var downloadRequest = URLRequest(url: remoteResourceURL)
        if let resourceModificationTime {
            downloadRequest.addValue(resourceModificationTime.rfc1123String, forHTTPHeaderField: "If-Modified-Since")
        }
        downloadRequest.cachePolicy = .reloadIgnoringLocalCacheData
        downloadRequest.httpShouldHandleCookies = false
        downloadRequest.timeoutInterval = 30 // shorter maybe?
        downloadRequest.httpMethod = "GET"

        Task {
            await Bundle.downloadLiveResource(request: downloadRequest, to: liveResourcePath)
        }

        return liveResourcePath
    }

    private static func downloadLiveResource(request: URLRequest, to liveResourcePath: String) async {
        let session = URLSession(configuration: .ephemeral)

        do {
            let (downloadedFileURL, response) = try await session.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return // 304 is expected for out of date items
            }

            let fileManager = FileManager.default

            // TODO check integrity of the temp file against HTTP MD5 header if provided
            // is something at the liveResourcePath already? we should remove that
            if fileManager.fileExists(atPath: liveResourcePath) {
                try fileManager.removeItem(atPath: liveResourcePath)
            }

            // the landing site is clear, move the downloaded file over to the resource path
            try fileManager.moveItem(at: downloadedFileURL, to: URL(fileURLWithPath: liveResourcePath))

            #if DEBUG
            NSLog("DEBUG LiveBundle updated: \(liveResourcePath) from: \(response.url?.absoluteString ?? "") original: \(request.url?.absoluteString ?? "")")
            #endif

            // file was moved into place successfully, tell the world
            NotificationCenter.default.post(name: LiveBundleResourceUpdateNotification, object: liveResourcePath)
        } catch {
            NSLog("ERROR LiveBundle download failed for \(request.url?.absoluteString ?? ""): \(error)")
        }
    }
}
