#!/usr/bin/osascript
-- ──────────────────────────────────────────────────────────────
-- macOS OCX — Native WebView Window (AppleScript)
--
-- Zero dependencies. Every Mac has osascript.
-- No Xcode, Swift compiler, or Python needed.
--
-- 1. Launches backend via launch-backend.sh
-- 2. Waits for localhost:8818 to respond
-- 3. Opens system browser with native experience
--    (Safari has best macOS integration)
--
-- For TRUE embedded WebView, compile MacOSOCXWebView.swift
-- (requires Xcode CLI tools: xcode-select --install)
-- ──────────────────────────────────────────────────────────────

use framework "Foundation"
use framework "WebKit"
use framework "AppKit"
use scripting additions

property NSWindow : class "NSWindow"
property NSApplication : class "NSApplication"
property WKWebView : class "WKWebView"
property WKWebViewConfiguration : class "WKWebViewConfiguration"
property NSURL : class "NSURL"
property NSURLRequest : class "NSURLRequest"
property NSRunLoop : class "NSRunLoop"
property NSDate : class "NSDate"
property NSApp : missing value

property SERVER_PORT : 8818
property APP_URL : "http://localhost:8818"
property backendPID : missing value

on run
    -- Get bundle path
    set bundlePath to POSIX path of (path to me)
    set resourcesPath to bundlePath & "Contents/Resources/"
    set macOSPath to bundlePath & "Contents/MacOS/"
    
    -- Launch backend
    set shellScript to "cd '" & macOSPath & "' && './launch-backend.sh' > '" & resourcesPath & "data/logs/backend.log' 2>&1 & echo $!"
    set backendPID to do shell script shellScript
    
    -- Initialize NSApplication
    set NSApp to NSApplication's sharedApplication()
    NSApp's setActivationPolicy:0 -- NSApplicationActivationPolicyRegular
    
    -- Create window
    set {screenWidth, screenHeight} to getCurrentScreenSize()
    set winWidth to 1280
    set winHeight to 800
    set winX to (screenWidth - winWidth) / 2
    set winY to (screenHeight - winHeight) / 2
    
    set mainWindow to NSWindow's alloc()'s initWithContentRect:{origin:{x:winX, y:winY}, |size|:{width:winWidth, height:winHeight}} styleMask:(15) backing:2 defer:false
    -- styleMask 15 = titled + closable + miniaturizable + resizable
    -- backing 2 = NSBackingStoreBuffered
    
    mainWindow's setTitle:"macOS OCX"
    mainWindow's setTitlebarAppearsTransparent:true
    mainWindow's setTitleVisibility:1 -- NSWindowTitleHidden
    mainWindow's setReleasedWhenClosed:false
    mainWindow's makeKeyAndOrderFront:null
    
    -- Create WebView
    set webConfig to WKWebViewConfiguration's alloc()'s init()
    set webView to WKWebView's alloc()'s initWithFrame:{origin:{x:0, y:0}, |size|:{width:winWidth, height:winHeight}} configuration:webConfig
    
    -- Loading page
    set loadingHTML to "<!DOCTYPE html><html><head><meta charset='utf-8'><style>*{margin:0;padding:0;box-sizing:border-box}body{display:flex;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;background:#1a1a2e;color:#eee;flex-direction:column;gap:16px}.spinner{width:40px;height:40px;border:3px solid rgba(255,255,255,0.2);border-top-color:#4fc3f7;border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}h2{font-weight:500}p{color:#999;font-size:14px}</style></head><body><div class='spinner'></div><h2>macOS OCX</h2><p>正在启动服务...</p></body></html>"
    webView's loadHTMLString:loadingHTML baseURL:missing value
    
    mainWindow's setContentView:webView
    
    -- Activate app
    NSApp's activateIgnoringOtherApps:true
    
    -- Wait for backend in background, then load URL
    my waitForBackendAndLoad(webView)
    
    -- Run event loop
    NSApp's run()
end run

on waitForBackendAndLoad(webView)
    -- Run backend check on background thread
    do shell script "
        # Wait 3 seconds for JVM to start
        sleep 3
        
        # Poll until server responds (max 60 attempts)
        ATTEMPTS=0
        MAX_ATTEMPTS=60
        while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if curl -s -o /dev/null -w '%{http_code}' http://localhost:8818 2>/dev/null | grep -qE '^[23]'; then
                echo 'READY'
                exit 0
            fi
            sleep 1
        done
        echo 'TIMEOUT'
        exit 1
    " in background
    
    -- Use delayed perform to check periodically
    my checkBackendStatus(webView)
end waitForBackendAndLoad

on checkBackendStatus(webView)
    -- Simple: wait then load URL (shell script in background handles the waiting)
    delay 5
    set attempts to 0
    repeat while attempts < 55
        try
            do shell script "curl -s -o /dev/null -w '%{http_code}' http://localhost:8818 2>/dev/null"
            -- Server responded — load the URL
            set appURL to NSURL's URLWithString:APP_URL
            set request to NSURLRequest's requestWithURL:appURL
            webView's loadRequest:request
            return
        end try
        set attempts to attempts + 1
        delay 1
    end repeat
    
    -- Timeout — show error
    set errorHTML to "<!DOCTYPE html><html><head><meta charset='utf-8'><style>*{margin:0;padding:0}body{display:flex;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,sans-serif;background:#1a1a2e;color:#ff5252;flex-direction:column;gap:12px;text-align:center;padding:40px}h2{font-weight:600}p{color:#ccc;font-size:14px}</style></head><body><h2>⚠️ 启动失败</h2><p>服务启动超时</p></body></html>"
    webView's loadHTMLString:errorHTML baseURL:missing value
end checkBackendStatus

on getCurrentScreenSize()
    try
        set screenSize to do shell script "python3 -c \"import AppKit; s=AppKit.NSScreen.mainScreen().visibleFrame(); print(f'{s.size.width} {s.size.height}')\""
        set AppleScript's text item delimiters to " "
        set width to (text item 1 of screenSize) as number
        set height to (text item 2 of screenSize) as number
        return {width, height}
    on error
        return {1440, 900}
    end try
end getCurrentScreenSize
