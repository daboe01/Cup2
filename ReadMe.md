# Cup2 (Cappuccino Uploader 2)

Cup2 is a file upload management framework for the [Cappuccino Web Framework](http://www.cappuccino-project.org). 

It was forked from the Cup framework (aparajita/Cup) with two primary goals:
1. **Eliminate the jQuery dependency:** Cup2 removes the requirement for jQuery and the jQuery File Upload library, instead utilizing modern native browser APIs (`XMLHttpRequest` Level 2, `FormData`, and HTML5 Drag-and-Drop).
2. **Expose server responses:** It introduces the delegate method `- (void)cup:(Cup)cup uploadDidSucceedForFile:(CupFile)file response:(id)response`, allowing developers to retrieve and process server response data directly upon a successful upload.

To maintain source compatibility and ease the migration process, class names, file names, and import structures have not been renamed and continue to use the original `Cup` prefix.

---

## Features

- **No External Dependencies:** Written in native Objective-J, utilizing standard Web APIs rather than third-party libraries.
- **Flexible Queue Management:** Supports sequential or concurrent uploads (with configurable limits on active concurrent connections).
- **Chunked Uploads:** Supports slicing large files into smaller chunks using the `Content-Range` header.
- **Drag-and-Drop & Paste:** Configure any `CPView` (or the main browser window) as a drop zone or clipboard paste listener.
- **KVO & Bindings Support:** Integration with table views (`CPTableView`) or progress bars using a standard `CPArrayController`.
- **Comprehensive Delegate Protocol:** Detailed callback support for validation filters, file size limits, progress tracking, and state changes—including access to the raw server response.

---

## Installation & Compatibility

Because the class and file names remain unchanged for backward compatibility, installation follows the same structure as the original framework:

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

`Cup` can be configured directly inside Interface Builder:

1. Add an `NSObject` to your `.xib` file and set its class to `Cup`.
2. Connect the `Cup` object to an outlet in your custom controller.
3. Add an `NSArrayController` and connect the `queueController` outlet of the `Cup` object to it.
4. Bind your UI controls (such as a table view displaying the file queue or a `CPProgressIndicator` for the upload status) directly to the array controller or to the progress properties of the `Cup` object.

---

## Server-Side Integration

When handling the file upload on your server, note that files are transmitted via standard `multipart/form-data` payloads. 

The framework appends the file payload using the specific form field name **`files[]`**:

```javascript
formData.append("files[]", nativeFile, name);
```

Your server-side application should be configured to parse and process files under the `files[]` field key.

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

Implement these methods in your controller to monitor and react to events in the upload lifecycle. 

Note the added delegate method that provides access to the server response object:

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

// NEW IN CUP2: Receive notification when an upload succeeds, including the server response
- (void)cup:(Cup)cup uploadDidSucceedForFile:(CupFile)file response:(id)response
{
    CPLog.info(@"Upload succeeded for: " + [file name]);
    
    if (response && response.status === @"success")
    {
        CPLog.info(@"Server file ID: " + response.file_id);
    }
}

// Legacy delegate method for basic success notifications
- (void)cup:(Cup)cup uploadDidSucceedForFile:(CupFile)file
{
    CPLog.info(@"Upload succeeded for: " + [file name]);
}
```

For a complete list of available delegate methods, please refer to `CupDelegate.j`.
