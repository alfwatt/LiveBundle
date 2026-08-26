
# LiveBundle

## Keep your Resources Fresh
`NSBundle+LiveBundle` is a category which provides dynamic updating of  
resources from your web server.

Let's say you have a resource, any resource will do, but for e.g. a plist 
which contains a list of your companies products, their prices, and links 
to purchase them; which is stored inside MyApplication's bundle as a resource:

    MyApplication.app/Contents/Resources/productTable.plist

And let's say you want to add a new product, or change a price for a sale, 
or update a link, but don't want to release a new version of your app or write
a web server that hosts an API or the code to support it?

LiveBundle provides infrastructure for hosting bundle resources on your web
server at a URL that you specify, so that your app can check to see if there
is an updated version of the resource avaliable for download:

    https://exaple.com/support/livebundle/com.example.myapplication/productsTable.plist

LiveBundle makes an `If-Modified-Since:` request to your server when the 
resource is requested. It then downloads the updated version of the resource,
and copies it into  the users's Library folder (or it's sandboxed equivalent):

    ~/Library/Application Support/MyApplication/LiveBundle/com.example.myapplication/products_table.plist

And that's the path that your code sees when it asks for the resource:

    NSString* livePath = [[NSBundle mainBundle] livePathForResource:@"productsTable" ofType:@"plist"];
    NSDictionary* productsTable = [NSDictionary dictionaryWithContentsOfFile:livePath];

    // Subscribe to be notified for updates to the file path (or just watch the file path yourelf):

    [NSNotificationCenter。defaultCenter 
        addObserverForName:ILLiveBundleResourceUpdateNote 
        object:livePth 
        queue:nil 
        usingBlock:^(NSNotification *note) {
            productsTable = [NSDictionary dictionaryWithContentsOfFile:livePath];
            // update the ui...
        }];

The initial path is a link back to the resource in the application's bundle, 
once an updated version has been sucesfully downloaded the notificaion will 
be sent to the application. Send `object:nil` to recieve notifications for 
all LiveBundle Resource Updates.

This works well for data that changes on a weekly or monthly basis, the app 
should only check a URL once per launch, or as much as daily if it's running 
for a long time.

## Using LiveBundle in your App

- Clone the latest sources: `git clone https://github.com/iStumblerLabs/LiveBundle.git` 
  near or inside your application's source 
- Drag `LiveBundle.xcodproj` into your project
- include the `LiveBundle.framework` in your applications `Resources/Frameworks` directory
    - link the `LiveBundle.framework` to all the targets which produce bundles you would like to update

## Swift Package <a id="spm"></a>

A Swift Package is defined in `Package.swift` for projects using Swift Package
Manager, you can include the following URL in your project to use it:

    https://github.com/alfwatt/LiveBundle.git

## Configure LiveBundle

- add a key to the `Info.plist` of all the `NSBundle`s you want to update pionting to the web server
    - `ILLiveBundleURLKey` is the base url for the bundles resources
        - e.g. `https://example.com/livebundle/`
    - when calling `livePathForResource:` the URL is prepended to the resource requested
        - e.g. `livePathForResource:@"resource.plist"` is `https://example.com/livebundle/resource.plist`
- add a UI element to disable LiveBundle if the user doesn't want updates:
    - bind the element's value to the `NSUserDefaults` key: `ILLiveBundleDisableUpdates`
    - checkboxes work well if you use `NSNegateBoolean` with the phrase `Automatically Update Resources on Startup`
    - it will be selected by default, and the user disabling will set the value to YES
- deploy resources to your web server and always test before you ship!

## TODO
- `<NSDictionary+LiveBundle.h>` for plists loaded via `livePlistFor:...`
- `<NSImage+LiveBundle.h>` for images loaded via `liveImageFor:...`
- Certificte Pinning Support on top of the existing SSL Nag

## Releases
- 2.0.0 - August 2026
    - Swift conversion
- 1.2.1 - 13 August 2024
    * Swift Package Manager Support
- 1.2 - 12 August 2024
    * Added tvOS build
    * Added +[NSBundle trashLiveBudles] to help with app reset tasks
    * Remove CircleCI build config
    * Nullability in `NSDate+RFC1123`
    * Use `dispatch_once` for static formatters
    * Move TODO items into README.md
    * Add `LiveBundle (All)` target for build testing
- 1.1 - November 2017
- 1.0.1 - 14 May 2016
- 1.0 - 13 May 2016

## License
    
    The MIT License (MIT)
    
    Copyright © 2015-2026 Alf Watt
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
