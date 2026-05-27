/*
 * Cup.j
 * Cup
 *
 * Created by Aparajita Fishman on February 3, 2013.
 * Copyright 2013, Filmworkers Club. All rights reserved.
 */

@import <Foundation/CPDictionary.j>
@import <Foundation/CPNumberFormatter.j>
@import <Foundation/CPRunLoop.j>
@import <Foundation/CPTimer.j>

@import <AppKit/CPAlert.j>
@import <AppKit/CPArrayController.j>
@import <AppKit/CPCompatibility.j>
@import <AppKit/CPPlatform.j>
@import <AppKit/CPPlatformWindow.j>
@import <AppKit/CPTableView.j>

CupFileStatusPending   = 0;
CupFileStatusUploading = 1;
CupFileStatusComplete  = 2;

/*
    These constants are bit flags passed to the cup:didFilterFile:because:
    delegate method, indicating why the file was rejected.
*/
CupFilteredName = 1 << 0;
CupFilteredSize = 1 << 1;

var FileStatuses = [];

var baseWidgetId = @"Cup_input",
    delegateFilter = 1 << 0,
    delegateWillAdd = 1 << 1,
    delegateAdd = 1 << 2,
    delegateSubmit = 1 << 3,
    delegateSend = 1 << 4,
    delegateSucceed = 1 << 5,
    delegateFail = 1 << 6,
    delegateComplete = 1 << 7,
    delegateStop = 1 << 8,
    delegateFileProgress = 1 << 9,
    delegateProgress = 1 << 10,
    delegateStart = 1 << 11,
    delegateStop = 1 << 12,
    delegateChange = 1 << 13,
    delegatePaste = 1 << 14,
    delegateDrop = 1 << 15,
    delegateDrag = 1 << 16,
    delegateChunkWillSend = 1 << 17,
    delegateChunkSucceed = 1 << 18,
    delegateChunkFail = 1 << 19,
    delegateChunkComplete = 1 << 20,
    delegateStartQueue = 1 << 21,
    delegateClearQueue = 1 << 22,
    delegateStopQueue = 1 << 23,
    delegateSucceedWithResponse = 1 << 24;

var CupDefaultProgressInterval = 100;

/*!
    @class Cup

    A pure JavaScript and Objective-J alternative to jQuery File Upload.
    The main configuration options are available as accessor methods.
*/
@implementation Cup : CPObject
{
    CPString            URL @accessors;
    CPString            redirectURL @accessors;
    BOOL                sequential @accessors;
    int                 maxChunkSize @accessors;
    int                 maxConcurrentUploads @accessors;
    int                 progressInterval @accessors;
    @outlet CPView      dropTarget @accessors(readonly);

    CPString            filenameFilter @accessors;
    RegExp              filenameFilterRegex @accessors;

    int                 maxFileSize @accessors;
    BOOL                autoUpload @accessors;
    BOOL                removeCompletedFiles @accessors;

    id                  currentEvent @accessors(readonly);
    JSObject            currentData @accessors(readwrite);

    BOOL                uploading @accessors;
    BOOL                indeterminate @accessors;
    CPMutableDictionary progress @accessors;

    @outlet id          delegate @accessors(readonly);
    int                 delegateImplementsFlags;

    Class               fileClass @accessors;

    CPString            widgetId;

    CPMutableArray      queue @accessors(readonly);
    @outlet CPArrayController queueController @accessors(readonly);

    // Native event listeners
    JSObject            _onDragOverHandler;
    JSObject            _onDropHandler;
    JSObject            _onPasteHandler;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(CPString)key
{
    if (key === @"filenameFilter" || key === @"filenameFilterRegex")
        return NO;
    else
        return [super automaticallyNotifiesObserversForKey:key];
}

/*!
    Returns the current version of the framework as a string.
*/
+ (CPString)versionString
{
    var bundle = [CPBundle bundleForClass:[self class]];

    return [bundle objectForInfoDictionaryKey:@"CPBundleVersion"];
}

#pragma mark Initialization

/*!
    Initializes and returns a Cup object which uploads to the given URL.
*/
- (id)initWithURL:(CPString)aURL
{
    self = [self init];

    if (self)
        [self setURL:aURL];

    return self;
}

/*!
    The designated initializer.
*/
- (id)init
{
    self = [super init];

    if (self)
        [self _init];

    return self;
}

#pragma mark Attributes

/*!
    Returns a copy of the options.
*/
- (JSObject)options
{
    return {
        "url": URL,
        "sequential": sequential,
        "maxChunkSize": maxChunkSize,
        "limitConcurrentUploads": maxConcurrentUploads,
        "progressInterval": progressInterval
    };
}

/*!
    Sets options that are mirrored in this class.
*/
- (void)setOptions:(JSObject)options
{
    if (options["url"] !== undefined)
        [self setURL:options["url"]];
    if (options["sequential"] !== undefined)
        [self setSequential:options["sequential"]];
    if (options["maxChunkSize"] !== undefined)
        [self setMaxChunkSize:options["maxChunkSize"]];
    if (options["limitConcurrentUploads"] !== undefined)
        [self setMaxConcurrentUploads:options["limitConcurrentUploads"]];
    if (options["progressInterval"] !== undefined)
        [self setProgressInterval:options["progressInterval"]];
}

/*!
    Sets the view that will be the drop target for files dragged into
    the browser. Pass [CPPlatformWindow primaryPlatformWindow] to make
    the entire window the drop target. Pass nil to disable drag and drop.
*/
- (void)setDropTarget:(CPView)target
{
    var oldElement = nil;

    if (dropTarget)
    {
        oldElement = (dropTarget === [CPPlatformWindow primaryPlatformWindow]) ? document : dropTarget._DOMElement;
    }

    if (oldElement)
    {
        oldElement.removeEventListener("dragover", _onDragOverHandler);
        oldElement.removeEventListener("drop", _onDropHandler);
        oldElement.removeEventListener("paste", _onPasteHandler);
    }

    dropTarget = target;

    if (!dropTarget)
        return;

    var element = (dropTarget === [CPPlatformWindow primaryPlatformWindow]) ? document : dropTarget._DOMElement;

    if (element)
    {
        element.addEventListener("dragover", _onDragOverHandler);
        element.addEventListener("drop", _onDropHandler);
        element.addEventListener("paste", _onPasteHandler);
    }
}

/*!
    Sets the delegate. For information on delegate methods, see the CupDelegate class.
*/
- (void)setDelegate:(id)aDelegate
{
    if (aDelegate === delegate)
        return;

    delegateImplementsFlags = 0;
    delegate = aDelegate;

    if (!delegate)
        return;

    if ([delegate respondsToSelector:@selector(cup:didFilterFile:because:)])
        delegateImplementsFlags |= delegateFilter;

    if ([delegate respondsToSelector:@selector(cup:willAddFile:)])
        delegateImplementsFlags |= delegateWillAdd;

    if ([delegate respondsToSelector:@selector(cup:didAddFile:)])
        delegateImplementsFlags |= delegateAdd;

    if ([delegate respondsToSelector:@selector(cupDidStart:)])
        delegateImplementsFlags |= delegateStart;

    if ([delegate respondsToSelector:@selector(cup:willSubmitFile:)])
        delegateImplementsFlags |= delegateSubmit;

    if ([delegate respondsToSelector:@selector(cup:willSendFile:)])
        delegateImplementsFlags |= delegateSend;

    if ([delegate respondsToSelector:@selector(cup:chunkWillSendForFile:)])
        delegateImplementsFlags |= delegateChunkWillSend;

    if ([delegate respondsToSelector:@selector(cup:chunkDidSucceedForFile:)])
        delegateImplementsFlags |= delegateChunkSucceed;

    if ([delegate respondsToSelector:@selector(cup:chunkDidFailForFile:)])
        delegateImplementsFlags |= delegateChunkFail;

    if ([delegate respondsToSelector:@selector(cup:chunkDidCompleteForFile:)])
        delegateImplementsFlags |= delegateChunkComplete;

    if ([delegate respondsToSelector:@selector(cup:uploadForFile:didProgress:)])
        delegateImplementsFlags |= delegateFileProgress;

    if ([delegate respondsToSelector:@selector(cup:uploadsDidProgress:)])
        delegateImplementsFlags |= delegateProgress;

    if ([delegate respondsToSelector:@selector(cup:uploadDidSucceedForFile:)])
        delegateImplementsFlags |= delegateSucceed;

    if ([delegate respondsToSelector:@selector(cup:uploadDidFailForFile:)])
        delegateImplementsFlags |= delegateFail;

    if ([delegate respondsToSelector:@selector(cup:uploadDidCompleteForFile:)])
        delegateImplementsFlags |= delegateComplete;

    if ([delegate respondsToSelector:@selector(cup:uploadWasStoppedForFile:)])
        delegateImplementsFlags |= delegateStop;

    if ([delegate respondsToSelector:@selector(cupDidStop:)])
        delegateImplementsFlags |= delegateStop;

    if ([delegate respondsToSelector:@selector(cup:fileInputDidSelectFiles:)])
        delegateImplementsFlags |= delegateChange;

    if ([delegate respondsToSelector:@selector(cupDidStartQueue:)])
        delegateImplementsFlags |= delegateStartQueue;

    if ([delegate respondsToSelector:@selector(cupDidClearQueue:)])
        delegateImplementsFlags |= delegateClearQueue;

    if ([delegate respondsToSelector:@selector(cupDidStopQueue:)])
        delegateImplementsFlags |= delegateStopQueue;

    if ([delegate respondsToSelector:@selector(cup:didPasteFiles:)])
        delegateImplementsFlags |= delegatePaste;

    if ([delegate respondsToSelector:@selector(cup:didDropFiles:)])
        delegateImplementsFlags |= delegateDrop;

    if ([delegate respondsToSelector:@selector(cup:wasDraggedOverWithEvent:)])
        delegateImplementsFlags |= delegateDrag;

    if ([delegate respondsToSelector:@selector(cup:uploadDidSucceedForFile:response:)])
        delegateImplementsFlags |= delegateSucceedWithResponse;
}

/*!
    Sets the class for the objects stored in the upload queue.
    The class must be CupFile or a subclass thereof.

    @param aClass Either a class object or a string name of a class
*/
- (void)setFileClass:(Class)aClass
{
    if ([aClass isKindOfClass:[CPString class]])
        aClass = CPClassFromString(aClass);

    if ([aClass isKindOfClass:[CupFile class]])
    {
        fileClass = aClass;
        [[self queueController] setObjectClass:fileClass];
    }
    else
        CPLog.warn("%s: %s the file class must be a subclass of CupFile.", [self className], [aClass className]);
}

/*!
    Sets the filter used to validate filenames that are being added to the queue.
    The string is passed to `new RegExp()`, so no delimiters should be included in the string.
*/
- (void)setFilenameFilter:(CPString)aFilter
{
    [self _setFilenameFilter:aFilter caseSensitive:YES];
}

/*!
    Sets the filter used to validate filenames that are being added to the queue.
    The string is passed to `new RegExp()`, so no delimiters should be included in the string.
    The filenameFilterRegex property stays in sync with this property.
*/
- (void)setFilenameFilter:(CPString)aFilter caseSensitive:(BOOL)caseSensitive
{
    [self _setFilenameFilter:aFilter caseSensitive:caseSensitive];
}

/*!
    Sets the filter regex used to validate filenames that are being added to the queue.
    The filenameFilter property stays in sync with this property.
*/
- (void)setFilenameFilterRegex:(RegExp)regex
{
    if ((filenameFilterRegex || "").toString() === (regex || "").toString())
        return;

    [self willChangeValueForKey:@"filenameFilterRegex"];
    [self willChangeValueForKey:@"filenameFilter"];

    filenameFilterRegex = regex;

    if (regex)
    {
        filenameFilter = regex.toString().replace(/^\/(.*)\/\w*$/, "$1");
    }
    else
        filenameFilter = @"";

    [self didChangeValueForKey:@"filenameFilter"];
    [self didChangeValueForKey:@"filenameFilterRegex"];
}

/*!
    Sets the list of allowed filename extensions (with or without dots) when adding files.
    This is just a convenience method that generates a filename filter regex.
    Any existing filename filter will be replaced.

    @param extensions   May be either an array of extensions or a whitespace-delimited list
                        in a single string.
*/
- (void)setAllowedExtensions:(id)extensions
{
    var filter = @"";

    if (extensions)
    {
        if ([extensions isKindOfClass:[CPString class]])
            extensions = extensions.split(/\s+/);

        [extensions enumerateObjectsUsingBlock:function(extension)
            {
                extension = extension.replace(/^\./, "");
            }];

        filter = [CPString stringWithFormat:@"^.+\\.(%@)$", extensions.join("|")];
    }

    [self setFilenameFilter:filter caseSensitive:NO];
}

/*!
    Returns the array controller for the queue, instantiating it (and the queue) if necessary
    and setting its content to the queue array.
*/
- (CPArrayController)queueController
{
    if (!queueController)
    {
        if (queue === nil)
            queue = [];

        queueController = [[CPArrayController alloc] initWithContent:queue];
        [queueController setObjectClass:[fileClass class]];
        [queueController addObserver:self forKeyPath:@"content" options:0 context:nil];
    }

    return queueController;
}

#pragma mark Actions

/*!
    Add files via a file chooser dialog.
    Can be used as an action method.
*/
- (@action)addFiles:(id)sender
{
    var input = document.getElementById(widgetId);
    if (input)
        input.click();
}

/*!
    Upload all of the files in the queue.
    Can be used as an action method.
*/
- (@action)start:(id)sender
{
    if (!URL)
    {
        CPLog.error("%s: The URL has not been set.", [self className]);
        return;
    }

    [self setUploading:YES];

    if (delegateImplementsFlags & delegateStartQueue)
        [delegate cupDidStartQueue:self];

    [self uploadDidStart];
    [self _processQueue];
}

/*!
    Stop all uploads. Can be used as an action method.
*/
- (@action)stop:(id)sender
{
    if (delegateImplementsFlags & delegateStopQueue)
        [delegate cupDidStopQueue:self];

    [queue makeObjectsPerformSelector:@selector(stop)];

    [self setUploading:NO];
}

/*!
    Clears the queue of files to be uploaded.
    If an upload is in progress, nothing happens.
    Can be used as an action method.
*/
- (@action)clearQueue:(id)sender
{
    if (uploading)
        return;

    [queue removeAllObjects];
    [[self queueController] setContent:queue];
    [self resetProgress];

    if (delegateImplementsFlags & delegateClearQueue)
        [delegate cupDidClearQueue:self];
}

#pragma mark Methods

/*!
    Returns the file in the queue with the given UID, or nil if none match.
*/
- (CupFile)fileWithUID:(CPString)aUID
{
    var index = [queue indexOfObjectPassingTest:function(file)
                    {
                        return [file UID] === aUID;
                    }];

    return index >= 0 ? queue[index] : nil;
}

#pragma mark Overrides

- (void)awakeFromCib
{
    [queueController setContent:queue];
    [queueController addObserver:self forKeyPath:@"content" options:0 context:nil];
}

- (void)observeValueForKeyPath:(CPString)aKeyPath ofObject:(id)anObject change:(CPDictionary)changeDict context:(JSObject)context
{
    if (aKeyPath === @"content")
    {
        [self resetProgress];
    }
}

#pragma mark Native File Upload Logic (private)

- (void)_processQueue
{
    if (!uploading)
        return;

    var activeCount = 0,
        count = [queue count];

    for (var i = 0; i < count; i++)
    {
        if ([queue[i] uploading])
            activeCount++;
    }

    for (var i = 0; i < count; i++)
    {
        var file = queue[i];

        if ([file status] === CupFileStatusPending && ![file uploading])
        {
            if (sequential && activeCount >= 1)
                break;

            if (maxConcurrentUploads > 0 && activeCount >= maxConcurrentUploads)
                break;

            var canSubmit = [self submitFile:file];
            if (canSubmit)
            {
                activeCount++;
                [file start];
            }
        }
    }

    if (activeCount === 0)
    {
        [self setUploading:NO];
        [self uploadDidStop];
    }
}

- (void)_recalculateOverallProgress
{
    var totalBytes = 0,
        uploadedBytes = 0,
        totalBitrate = 0,
        activeCount = 0;

    var count = [queue count];
    for (var i = 0; i < count; i++)
    {
        var file = queue[i];
        totalBytes += [file size];
        uploadedBytes += [file uploadedBytes];
        if ([file uploading])
        {
            totalBitrate += [file bitrate];
            activeCount++;
        }
    }

    var overallProgress = {
        uploadedBytes: uploadedBytes,
        total: totalBytes,
        bitrate: totalBitrate
    };

    [self updateProgressWithUploadedBytes:uploadedBytes
                                   total:totalBytes
                         percentComplete:(totalBytes > 0 ? (uploadedBytes / totalBytes * 100) : 0)
                                 bitrate:totalBitrate];

    if (delegateImplementsFlags & delegateProgress)
        [delegate cup:self uploadsDidProgress:overallProgress];
}

#pragma mark Delegate (private)

/// @cond IGNORE

- (void)addFile:(JSFile)file
{
    var filterFlags = [self validateFile:file],
        canAdd = filterFlags === 0,
        cupFile = [[fileClass alloc] initWithCup:self file:file data:nil];

    if (canAdd)
    {
        if (delegateImplementsFlags & delegateWillAdd)
            canAdd = [delegate cup:self willAddFile:cupFile];
    }
    else if (delegateImplementsFlags & delegateFilter)
        [delegate cup:self didFilterFile:cupFile because:filterFlags];
    else
        [self fileWasRejected:cupFile because:filterFlags];

    if (canAdd)
    {
        [[self queueController] addObject:cupFile];

        if (delegateImplementsFlags & delegateAdd)
            [delegate cup:self didAddFile:cupFile];

        if (autoUpload)
        {
            [self setUploading:YES];
            [cupFile submit];
        }
    }
}

- (void)uploadDidStart
{
    [[self queueController] setSelectionIndexes:[CPIndexSet indexSet]];
    [self setUploading:YES];

    if (delegateImplementsFlags & delegateStart)
        [delegate cupDidStart:self];
}

- (BOOL)submitFile:(CupFile)file
{
    if (!URL)
    {
        CPLog.error("%s: The URL has not been set.", [self className]);
        return NO;
    }

    var canSubmit = YES;

    if (delegateImplementsFlags & delegateSubmit)
        canSubmit = [delegate cup:self willSubmitFile:file];

    return canSubmit;
}

- (BOOL)willSendFile:(CupFile)file
{
    var canSend = YES;

    if (delegateImplementsFlags & delegateSend)
        canSend = [delegate cup:self willSendFile:file];

    return canSend;
}

- (BOOL)chunkWillSendForFile:(CupFile)file
{
    if (delegateImplementsFlags & delegateChunkWillSend)
        return [delegate cup:self willSendChunkForFile:file];

    return YES;
}

- (void)chunkDidSucceedForFile:(CupFile)file
{
    if (delegateImplementsFlags & delegateChunkSucceed)
        [delegate cup:self chunkDidSucceedForFile:file];
}

- (void)chunkDidFailForFile:(CupFile)file
{
    if (delegateImplementsFlags & delegateChunkFail)
        [delegate cup:self chunkDidFailForFile:file];
}

- (void)chunkDidCompleteForFile:(CupFile)file
{
    if (delegateImplementsFlags & delegateChunkComplete)
        [delegate cup:self chunkDidCompleteForFile:file];
}

- (void)uploadForFile:(CupFile)file didProgress:(JSObject)fileProgress
{
    if (fileProgress.uploadedBytes)
        [file setUploadedBytes:fileProgress.uploadedBytes];

    [file setBitrate:fileProgress.bitrate];

    if (delegateImplementsFlags & delegateFileProgress)
        [delegate cup:self uploadForFile:file didProgress:fileProgress];

    [self _recalculateOverallProgress];
}

- (void)uploadsDidProgress:(JSObject)overallProgress
{
    [self updateProgressWithUploadedBytes:overallProgress.uploadedBytes
                                   total:overallProgress.total
                         percentComplete:overallProgress.uploadedBytes / overallProgress.total * 100
                                 bitrate:overallProgress.bitrate];

    if (delegateImplementsFlags & delegateProgress)
        [delegate cup:self uploadsDidProgress:overallProgress];
}

- (void)uploadDidSucceedForFile:(CupFile)file withResponse:(CPString)responseText
{
    [file setStatus:CupFileStatusComplete];

    if (delegateImplementsFlags & delegateSucceedWithResponse)
        [delegate cup:self uploadDidSucceedForFile:file response:responseText];
    else if (delegateImplementsFlags & delegateSucceed)
        [delegate cup:self uploadDidSucceedForFile:file];
}

- (void)uploadDidSucceedForFile:(CupFile)file
{
    [file setStatus:CupFileStatusComplete];

    if (delegateImplementsFlags & delegateSucceed)
        [delegate cup:self uploadDidSucceedForFile:file];
}

- (void)uploadDidFailForFile:(CupFile)file
{
    [file setStatus:CupFileStatusPending];

    if (delegateImplementsFlags & delegateFail)
        [delegate cup:self uploadDidFailForFile:file];
}

- (void)uploadDidCompleteForFile:(CupFile)file
{
    [file setUploading:NO];

    if (delegateImplementsFlags & delegateComplete)
        [delegate cup:self uploadDidCompleteForFile:file];

    [self _processQueue];
}

- (void)uploadWasStoppedForFile:(CupFile)file
{
    if (delegateImplementsFlags & delegateStop)
        [delegate cup:self uploadWasStoppedForFile:file];
}

- (void)uploadDidStop
{
    [self setUploading:NO];

    if (delegateImplementsFlags & delegateStop)
        [delegate cupDidStop:self];

    if (removeCompletedFiles)
    {
        var indexes = [queue indexesOfObjectsPassingTest:function(file)
                        {
                            return [file status] === CupFileStatusComplete;
                        }];

        [queue removeObjectsAtIndexes:indexes];
        [[self queueController] setContent:queue];
    }
}

- (void)fileInputDidSelectFiles:(CPArray)files
{
    if (delegateImplementsFlags & delegateChange)
        [delegate cup:self fileInputDidSelectFiles:files];
}

- (void)filesWerePasted:(CPArray)files
{
    if (delegateImplementsFlags & delegatePaste)
        [delegate cup:self didPasteFiles:files];
}

- (void)filesWereDropped:(CPArray)files
{
    if (delegateImplementsFlags & delegateDrop)
        [delegate cup:self didDropFiles:files];
}

- (void)filesWereDraggedOverWithEvent:(id)anEvent
{
    if (delegateImplementsFlags & delegateDrag)
        [delegate cup:self wasDraggedOverWithEvent:anEvent];
}

#pragma mark Private helpers

- (void)_init
{
    var self_ = self;

    _onDragOverHandler = function(e)
    {
        e.preventDefault();
        [self_ filesWereDraggedOverWithEvent:e];
    };

    _onDropHandler = function(e)
    {
        e.preventDefault();
        var files = e.dataTransfer && e.dataTransfer.files;
        if (files && files.length > 0)
        {
            var fileArray = [];
            for (var i = 0; i < files.length; i++)
            {
                fileArray.push(files[i]);
            }

            [self_ filesWereDropped:fileArray];

            for (var i = 0; i < files.length; i++)
            {
                [self_ addFile:files[i]];
            }
        }
    };

    _onPasteHandler = function(e)
    {
        var items = (e.clipboardData || e.originalEvent.clipboardData).items;
        var fileArray = [];
        for (var i = 0; i < items.length; i++)
        {
            if (items[i].kind === 'file')
            {
                var file = items[i].getAsFile();
                if (file)
                {
                    fileArray.push(file);
                }
            }
        }

        if (fileArray.length > 0)
        {
            [self_ filesWerePasted:fileArray];

            for (var i = 0; i < fileArray.length; i++)
            {
                [self_ addFile:fileArray[i]];
            }
        }
    };

    [self makeFileInput];

    delegateImplementsFlags = 0;
    fileClass = [CupFile class];

    [self queueController];

    URL = URL || @"";
    redirectURL = @"";
    sequential = NO;
    maxConcurrentUploads = 0;
    maxChunkSize = 0;
    progressInterval = CupDefaultProgressInterval;
    progress = [CPMutableDictionary dictionary];
    dropTarget = [CPPlatformWindow primaryPlatformWindow];

    // Prevent standard browser drag/drop behavior on document level
    document.addEventListener("dragover", function(e) { e.preventDefault(); }, false);
    document.addEventListener("drop", function(e) { e.preventDefault(); }, false);

    [self setDropTarget:dropTarget];
    [self resetProgress];
    [self setUploading:NO];
    [self setIndeterminate:!CPFeatureIsCompatible(CPFileAPIFeature)];
}

- (void)makeFileInput
{
    var input = nil;

    for (var counter = 1; ; ++counter)
    {
        widgetId = baseWidgetId + counter;
        input = document.getElementById(widgetId);

        if (!input)
            break;
    }

    var bodyElement = [CPPlatform mainBodyElement];

    input = document.createElement("input");
    input.className = "cpdontremove";
    input.setAttribute("type", "file");
    input.setAttribute("id", widgetId);
    input.setAttribute("name", "files[]");
    input.setAttribute("multiple", "");
    input.style.position = "absolute";
    input.style.visibility = "hidden";
    input.style.width = "0";
    input.style.height = "0";

    bodyElement.appendChild(input);

    var self_ = self;
    input.addEventListener("change", function(e) {
        var files = e.target.files;
        if (!files || files.length === 0)
            return;

        var fileArray = [];
        for (var i = 0; i < files.length; i++)
        {
            fileArray.push(files[i]);
        }

        [self_ fileInputDidSelectFiles:fileArray];

        for (var i = 0; i < files.length; i++)
        {
            [self_ addFile:files[i]];
        }

        e.target.value = null;
    }, false);
}

- (void)_setFilenameFilter:(CPString)aFilter caseSensitive:(BOOL)caseSensitive
{
    var regex = new RegExp(aFilter, caseSensitive ? "" : "i");

    if (regex.toString() === (filenameFilterRegex || "").toString())
        return;

    [self willChangeValueForKey:@"filenameFilter"];
    [self willChangeValueForKey:@"filenameFilterRegex"];

    filenameFilter = aFilter;
    filenameFilterRegex = aFilter ? regex : nil;

    [self didChangeValueForKey:@"filenameFilterRegex"];
    [self didChangeValueForKey:@"filenameFilter"];
}

- (void)pumpRunLoop
{
    [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
}

- (CupFile)fileFromJSFile:(JSFile)file
{
    return [self fileWithUID:file.CPUID];
}

- (void)updateProgressWithUploadedBytes:(CPNumber)uploadedBytes total:(CPNumber)total percentComplete:(CPNumber)percentComplete bitrate:(CPNumber)bitrate
{
    if (uploadedBytes !== nil)
        [progress setValue:uploadedBytes forKey:@"uploadedBytes"];

    if (total !== nil)
        [progress setValue:total forKey:@"total"];

    if (percentComplete !== nil)
        [progress setValue:FLOOR(percentComplete) forKey:@"percentComplete"];

    if (bitrate !== nil)
        [progress setValue:bitrate forKey:@"bitrate"];
}

- (void)resetProgress
{
    [self updateProgressWithUploadedBytes:0 total:[self totalSizeOfQueue] percentComplete:0 bitrate:0];
}

- (int)validateFile:(JSFile)file
{
    var flags = 0;

    if (filenameFilterRegex && !filenameFilterRegex.test(file.name))
        flags |= CupFilteredName;

    if (file.hasOwnProperty("size") && maxFileSize && file.size > maxFileSize)
        flags |= CupFilteredSize;

    return flags;
}

- (void)fileWasRejected:(CupFile)file because:(int)filterFlags
{
    var error = [CPString stringWithFormat:@"The file “%@” was rejected because the ", [file name]];

    if (filterFlags & CupFilteredName)
        error += @"filename did not match the filename filter.";

    if (filterFlags & CupFilteredSize)
    {
        if (filterFlags & CupFilteredName)
            error += @" In addition, the ";

        var fileSize = [CPNumberFormatter localizedStringFromNumber:[file size] numberStyle:CPNumberFormatterDecimalStyle],
            maxSize = [CPNumberFormatter localizedStringFromNumber:maxFileSize numberStyle:CPNumberFormatterDecimalStyle];

        error += [CPString stringWithFormat:@"size (%s bytes) is larger than the maximum file size (%s bytes).", fileSize, maxSize];
    }

    [[CPAlert alertWithMessageText:error
                     defaultButton:@"OK"
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:@""] runModal];
}

- (int)totalSizeOfQueue
{
    var total = 0,
        count = [queue count];

    while (count--)
        total += [queue[count] size];

    return total;
}

/// @endcond

@end


/*!
    @class CupFile

    A native XMLHttpRequest Level 2 implementation wrapper for the File API.
*/
@implementation CupFile : CPObject
{
    Cup             cup;
    CPString        name @accessors(readonly);
    int             size @accessors(readonly);
    CPString        type @accessors(readonly);
    int             status @accessors;
    BOOL            uploading @accessors;
    int             uploadedBytes @accessors;
    float           bitrate @accessors;
    BOOL            indeterminate @accessors(readonly);
    JSObject        data @accessors;

    JSObject        nativeFile;
    XMLHttpRequest  xhr;
    double          startTime;
}

+ (void)initialize
{
    if (self !== [CupFile class])
        return;

    FileStatuses[CupFileStatusPending]   = @"Pending";
    FileStatuses[CupFileStatusUploading] = @"Uploading";
    FileStatuses[CupFileStatusComplete]  = @"Complete";
}

+ (CPSet)keyPathsForValuesAffectingPercentComplete
{
    return [CPSet setWithObjects:@"uploadedBytes"];
}

/*!
    Designated initializer.
*/
- (id)initWithCup:(Cup)aCup file:(JSObject)file data:(JSObject)someData
{
    if (self = [super init])
    {
        file.CPUID = [self UID];
        cup = aCup;
        name = file.name;
        status = CupFileStatusPending;
        uploading = NO;
        bitrate = 0.0;
        data = someData;
        nativeFile = file;

        if (file.hasOwnProperty("size"))
        {
            size = file.size;
            type = file.type;
            indeterminate = NO;
        }
        else
        {
            size = 0;
            type = @"";
            indeterminate = YES;
        }
    }

    return self;
}

/*!
    Return the upload percentage as a number from 0-100.
    Returns zero if indeterminate == YES.
*/
- (int)percentComplete
{
    return indeterminate ? 0 : FLOOR(uploadedBytes / size * 100);
}

/*!
    Submit this file for uploading.
*/
- (void)submit
{
    [self setStatus:CupFileStatusPending];
    [self setUploadedBytes:0];

    if ([cup uploading] || [cup autoUpload])
    {
        [cup _processQueue];
    }
}

/*!
    Notifies the file that it has actually started uploading.
*/
- (void)start
{
    if (uploading)
        return;

    [self setStatus:CupFileStatusUploading];
    [self setUploading:YES];
    startTime = +new Date();

    [self _upload];
}

/*!
    Stops the upload for the file.
*/
- (void)stop
{
    if (xhr)
    {
        [xhr abort];
        xhr = nil;
    }

    [self setStatus:CupFileStatusPending];
    [self setUploading:NO];

    [cup uploadWasStoppedForFile:self];
}

- (void)_upload
{
    var maxChunkSize = [cup maxChunkSize];

    if (maxChunkSize > 0 && size > maxChunkSize)
    {
        [self _uploadNextChunk:0];
    }
    else
    {
        [self _uploadFull];
    }
}

- (void)_uploadFull
{
    xhr = new XMLHttpRequest();
    xhr.open("POST", [cup URL], true);

    xhr.upload.addEventListener("progress", function(e) {
        if (e.lengthComputable)
        {
            [self _onProgressWithLoaded:e.loaded total:e.total];
        }
    }, false);

    xhr.addEventListener("load", function(e) {
        if (xhr.status >= 200 && xhr.status < 300)
        {
            [self _onSuccess:xhr.responseText];
        }
        else
        {
            [self _onFailure];
        }
    }, false);

    xhr.addEventListener("error", function(e) {
        [self _onFailure];
    }, false);

    xhr.addEventListener("abort", function(e) {
        [self _onAbort];
    }, false);

    var formData = new FormData();
    formData.append("files[]", nativeFile, name);

    var canSend = [cup willSendFile:self];
    if (!canSend)
    {
        [self stop];
        return;
    }

    xhr.send(formData);
}

- (void)_uploadNextChunk:(int)startByte
{
    var maxChunkSize = [cup maxChunkSize],
        endByte = Math.min(startByte + maxChunkSize, size);

    xhr = new XMLHttpRequest();
    xhr.open("POST", [cup URL], true);

    var contentRange = "bytes " + startByte + "-" + (endByte - 1) + "/" + size;
    xhr.setRequestHeader("Content-Range", contentRange);

    xhr.upload.addEventListener("progress", function(e) {
        if (e.lengthComputable)
        {
            var totalLoaded = startByte + e.loaded;
            [self _onProgressWithLoaded:totalLoaded total:size];
        }
    }, false);

    xhr.addEventListener("load", function(e) {
        if (xhr.status >= 200 && xhr.status < 300)
        {
            [cup chunkDidSucceedForFile:self];

            if (endByte < size)
            {
                [self _uploadNextChunk:endByte];
            }
            else
            {
                [self _onSuccess:xhr.responseText];
            }
        }
        else
        {
            [cup chunkDidFailForFile:self];
            [self _onFailure];
        }

        [cup chunkDidCompleteForFile:self];
    }, false);

    xhr.addEventListener("error", function(e) {
        [cup chunkDidFailForFile:self];
        [self _onFailure];
        [cup chunkDidCompleteForFile:self];
    }, false);

    xhr.addEventListener("abort", function(e) {
        [cup chunkDidFailForFile:self];
        [self _onAbort];
        [cup chunkDidCompleteForFile:self];
    }, false);

    var chunkBlob = nativeFile.slice(startByte, endByte);
    var formData = new FormData();
    formData.append("files[]", chunkBlob, name);

    var canSend = [cup chunkWillSendForFile:self];
    if (!canSend)
    {
        [self stop];
        return;
    }

    xhr.send(formData);
}

- (void)_onProgressWithLoaded:(int)loaded total:(int)total
{
    [self setUploadedBytes:loaded];

    var currentTime = +new Date(),
        timeElapsed = (currentTime - startTime) / 1000;

    if (timeElapsed > 0)
    {
        var currentBitrate = (loaded * 8) / timeElapsed;
        [self setBitrate:currentBitrate];
    }

    var progressData = {
        uploadedBytes: loaded,
        total: total,
        bitrate: bitrate
    };

    var mockData = {
        loaded: loaded,
        total: total,
        bitrate: bitrate,
        files: [nativeFile]
    };
    [cup setCurrentData:mockData];

    [cup uploadForFile:self didProgress:progressData];
}

- (void)_onSuccess:(CPString)responseText
{
    xhr = nil;
    [self setStatus:CupFileStatusComplete];
    [self setUploading:NO];

    var mockData = {
        loaded: size,
        total: size,
        bitrate: bitrate,
        result: responseText,
        files: [nativeFile]
    };
    [cup setCurrentData:mockData];

    [cup uploadDidSucceedForFile:self withResponse:responseText];
    [cup uploadDidCompleteForFile:self];
}

- (void)_onFailure
{
    xhr = nil;
    [self setStatus:CupFileStatusPending];
    [self setUploading:NO];

    [cup uploadDidFailForFile:self];
    [cup uploadDidCompleteForFile:self];
}

- (void)_onAbort
{
    xhr = nil;
    [self setStatus:CupFileStatusPending];
    [self setUploading:NO];

    [cup uploadDidCompleteForFile:self];
}

- (CPString)description
{
    return [CPString stringWithFormat:@"%@ \"%@\", size=%d, type=%s, uploadedBytes=%d, status=%s", [super description], name, size, type, uploadedBytes, FileStatuses[status]];
}

@end


/*!
    This class is designed to replace the standard NSTableCellView used in a view-based table
    within Xcode. It provides an action method which can be used to stop a single file's upload.
*/
@implementation CupTableCellView : CPTableCellView

- (@action)stopUpload:(id)sender
{
    [[self objectValue] stop];
}

@end
