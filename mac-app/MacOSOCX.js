#!/usr/bin/osascript -l JavaScript
// ──────────────────────────────────────────────────────────────
// macOS OCX — Native WebView Window (AppleScript JXA)
//
// Zero dependencies. Runs on every Mac (10.10+).
// No Xcode, no Swift compiler, no Python needed.
//
// This script:
//   1. Launches the Spring Boot backend via launch-backend.sh
//   2. Creates a native macOS window with WKWebView
//   3. Shows a loading spinner while backend starts
//   4. Loads localhost:8818 when backend is ready
//   5. Close window = quit app
// ──────────────────────────────────────────────────────────────

ObjC.import('Cocoa')
ObjC.import('WebKit')

const SERVER_PORT = 8818
const APP_URL = `http://localhost:${SERVER_PORT}`
const BUNDLE_PATH = $.NSBundle.mainBundle.bundlePath.js

// ── Launch backend ─────────────────────────────────────────────
function launchBackend() {
    const task = $.NSTask.alloc.init
    task.executableURL = $.NSURL.fileURLWithPath('/bin/bash')
    
    const launchScript = `${BUNDLE_PATH}/Contents/MacOS/launch-backend.sh`
    const args = $.NSMutableArray.alloc.initWithCapacity(2)
    args.addObject(launchScript)
    task.arguments = args
    
    // Redirect output to log file
    const logDir = `${BUNDLE_PATH}/Contents/Resources/data/logs`
    const fm = $.NSFileManager.defaultManager
    if (!fm.fileExistsAtPath(logDir)) {
        fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(logDir, true, $(), $())
    }
    
    const logPath = `${logDir}/backend.log`
    const logURL = $.NSURL.fileURLWithPath(logPath)
    
    // Try to create log file
    if (!fm.fileExistsAtPath(logPath)) {
        fm.createFileAtPathContentsAttributes(logPath, $(), $())
    }
    
    const outPipe = $.NSPipe.pipe
    const errPipe = $.NSPipe.pipe
    // Write pipe output to log file
    task.standardOutput = outPipe
    task.standardError = errPipe
    
    task.standardInput = $.NSPipe.pipe // disconnect stdin
    
    task.launchAndReturnError($())
    
    return task
}

// ── Poll backend until ready ───────────────────────────────────
function waitForBackend(callback) {
    let attempts = 0
    const maxAttempts = 60
    
    function tryConnect() {
        attempts++
        if (attempts > maxAttempts) {
            callback(false)
            return
        }
        
        const url = $.NSURL.URLWithString(APP_URL)
        const request = $.NSMutableURLRequest.requestWithURL(url)
        request.setTimeoutInterval(2)
        
        const config = $.NSURLSessionConfiguration.defaultSessionConfiguration
        config.setTimeoutIntervalForRequest(2)
        const session = $.NSURLSession.sessionWithConfigurationDelegate(config, $())
        
        const dataTask = session.dataTaskWithRequestCompletionHandler(request, (data, response, error) => {
            if (error && error.code === -1007) {
                // Redirect — server is up
                callback(true)
            } else if (response && response.statusCode >= 200 && response.statusCode < 400) {
                callback(true)
            } else {
                $.NSThread.sleepForTimeInterval(1.0)
                tryConnect()
            }
        })
        dataTask.resume()
    }
    
    // Give JVM 3 seconds to start
    $.NSThread.sleepForTimeInterval(3.0)
    tryConnect()
}

// ── Create native window with WebView ──────────────────────────
function createWindow() {
    const screenRect = $.NSScreen.mainScreen.visibleFrame
    
    // Window: 80% of screen, centered
    const width = Math.min(1280, screenRect.size.width * 0.8)
    const height = Math.min(800, screenRect.size.height * 0.8)
    const x = screenRect.origin.x + (screenRect.size.width - width) / 2
    const y = screenRect.origin.y + (screenRect.size.height - height) / 2
    
    const windowRect = $.NSMakeRect(x, y, width, height)
    
    const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
        windowRect,
        $.NSTitledWindowMask | $.NSClosableWindowMask | $.NSMiniaturizableWindowMask | $.NSResizableWindowMask | $.NSFullSizeContentViewWindowMask,
        $.NSBackingStoreBuffered,
        false
    )
    
    window.title = "macOS OCX"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = $.NSHidden
    window.setReleasedWhenClosed(false)
    
    // Create WKWebView
    const config = $.WKWebViewConfiguration.alloc.init
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    
    const webView = $.WKWebView.alloc.initWithFrameConfiguration(
        $.NSMakeRect(0, 0, width, height),
        config
    )
    
    // Show loading page first
    const loadingHTML = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { display: flex; align-items: center; justify-content: center;
       height: 100vh; font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
       background: #1a1a2e; color: #eee; flex-direction: column; gap: 16px; }
.spinner { width: 40px; height: 40px; border: 3px solid rgba(255,255,255,0.2);
           border-top-color: #4fc3f7; border-radius: 50%; animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
h2 { font-weight: 500; }
p { color: #999; font-size: 14px; }
</style></head>
<body>
  <div class="spinner"></div>
  <h2>macOS OCX</h2>
  <p>正在启动服务...</p>
</body></html>`
    
    webView.loadHTMLStringBaseURL(loadingHTML, $())
    
    window.contentView = webView
    window.makeKeyAndOrderFront(null)
    
    return { window, webView }
}

// ── Main ───────────────────────────────────────────────────────
const backendTask = launchBackend()
const { window: mainWindow, webView: mainWebView } = createWindow()

// Start polling for backend
waitForBackend((ready) => {
    if (ready) {
        const url = $.NSURL.URLWithString(APP_URL)
        const request = $.NSURLRequest.requestWithURL(url)
        mainWebView.loadRequest(request)
    } else {
        const errorHTML = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* { margin: 0; padding: 0; }
body { display: flex; align-items: center; justify-content: center;
       height: 100vh; font-family: -apple-system, sans-serif;
       background: #1a1a2e; color: #ff5252; flex-direction: column; gap: 12px; text-align: center; padding: 40px; }
h2 { font-weight: 600; }
p { color: #ccc; font-size: 14px; }
</style></head>
<body>
  <h2>⚠️ 启动失败</h2>
  <p>服务启动超时，请检查日志</p>
</body></html>`
        mainWebView.loadHTMLStringBaseURL(errorHTML, $())
    }
})

// Keep running until window closes
while (true) {
    const event = $.NSApp.nextEventMatchingMaskUntilDateInModeDequeue(
        $.NSAnyEventMask,
        $.NSDate.distantFuture,
        $.NSDefaultRunLoopMode,
        true
    )
    if (event) {
        $.NSApp.sendEvent(event)
    }
    
    if (mainWindow.isClosed) {
        backendTask.terminate
        $.exit(0)
    }
}
