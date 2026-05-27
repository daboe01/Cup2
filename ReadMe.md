# Cup2 (Cappuccino Uploader 2)

Cup2 is a file upload management framework for the [Cappuccino Web Framework](http://www.cappuccino-project.org). Built entirely on modern native browser APIs (`XMLHttpRequest` Level 2, `FormData`, HTML5 Drag-and-Drop), it operates without external dependencies like jQuery or the jQuery File Upload library like its predecessor Cup.

By integrating directly with core Cappuccino concepts (KVO, Bindings, Array Controllers), the framework allows you to build file upload interfaces with minimal code, including direct configuration in Xcode/Interface Builder.

---

## Features

- **No External Dependencies:** Written in pure Objective-J, utilizing standard Web APIs.
- **Flexible Queue Management:** Supports sequential or concurrent uploads (with configurable limits on active concurrent connections).
- **Chunked Uploads:** Supports slicing large files into smaller chunks using the `Content-Range` header.
- **Drag-and-Drop & Paste:** Configure any `CPView` (or the main browser window) as a drop zone or clipboard paste listener.
- **KVO & Bindings Support:** Integration with table views (`CPTableView`) or progress bars using a standard `CPArrayController`.
- **Comprehensive Delegate Protocol:** Detailed callback support for validation filters, file size limits, progress tracking, and state changes for chunks and files.

---

## Installation

1. Copy the `Cup` framework folder into your project directory (e.g., under `Frameworks/`).
2. Import the framework in your application code or build configuration:

```objective-j
@import <Cup/Cup.j>
```

---

## Getting Started

### Programmatic Initialization

You can instantiate and configure a `Cup` object programmatically:

```objective-j
// Initialize the uploader
var uploader = [[Cup alloc] initWithURL:@"/upload-endpoint"];

// Customize options
[uploader setSequential:YES];
[uploader setMaxFileSize:10485760]; // 10 MB
[uploader setAutoUpload:YES];

// Set the delegate
[uploader setDelegate:self];

// Set the entire window as a drop target
[uploader setDropTarget:[CPPlatformWindow primaryPlatformWindow]];
```

### Using Interface Builder (Xcode)

Because of its design, `Cup` can be configured directly inside Interface Builder:

1. Add an `NSObject` to your `.xib` file and set its class to `Cup`.
2. Connect the `Cup` object to an outlet in your custom controller.
3. Add an `NSArrayController` and connect the `queueController` outlet of the `Cup` object to it.
4. Bind your UI controls (such as a table view displaying the file queue or a `CPProgressIndicator` for the upload status) directly to the array controller or to the progress properties of the `Cup` object.

---

## Key Classes

### `Cup`
The central controller class. Manages global settings (target URL, filters, concurrency limits) and triggers operations.

- **Actions:**
  - `- (void)addFiles:(id)sender` (Opens the system file chooser dialog)
  - `- (void)start:(id)sender` (Starts processing the upload queue)
  - `- (void)stop:(id)sender` (Stops active uploads)
  - `- (void)clearQueue:(id)sender` (Clears the file queue)

### `CupFile`
Represents an individual item in the upload queue. Exposes observable properties such as `name`, `size`, `uploadedBytes`, `percentComplete`, `bitrate`, and `status` for use with Bindings.

### `CupByteCountTransformer`
A helper value transformer designed to convert raw byte sizes into human-readable strings like KB, MB, or GB (utilizes `CPByteCountFormatter`).

---

## Delegate Protocol (`CupDelegate`)

Implement these methods in your controller to monitor and react to events in the upload lifecycle:

```objective-j
// Determine if a file should be accepted into the queue before it is added
- (BOOL)cup:(Cup)cup willAddFile:(CupFile)file
{
    return YES;
}

// Receive progress updates for individual files
- (void)cup:(Cup)cup uploadForFile:(CupFile)file didProgress:(JSObject)progress
{
    // progress contains: uploadedBytes, total, bitrate
}

// Receive a notification when a file upload succeeds, along with the server response
- (void)cup:(Cup)cup uploadDidSucceedForFile:(CupFile)file response:(id)response
{
    CPLog.info(@"Upload succeeded for: " + [file name]);
    
    if (response && response.status === @"success")
    {
        CPLog.info(@"Server file ID: " + response.file_id);
    }
}

// Receive a notification when a file upload succeeds
- (void)cup:(Cup)cup uploadDidSucceedForFile:(CupFile)file
{
    CPLog.info(@"Upload succeeded for: " + [file name]);
}
```

For a full list of available delegate methods, refer to `CupDelegate.j`.
