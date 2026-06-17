#!/usr/bin/osascript
-- ──────────────────────────────────────────────────────────────
-- macOS OCX — Native Window Edition (AppleScriptObjC)
--
-- Pure AppleScript + WebKit. NO compilation. NO Xcode.
-- Works on every Mac macOS 10.10+.
--
-- Double-click app → native window opens → use directly.
-- Close window = quit app + kill backend.
-- ──────────────────────────────────────────────────────────────

use framework "Foundation"
use framework "AppKit"
use framework "WebKit"
use scripting additions

property SERVER_PORT : 8818
property NSApp : missing value
property mainWindow : missing value
property webView : missing value
property backendPID : missing value
property pollCount : 0

on run
    -- ── Get bundle paths ──────────────────────────────────────
    set bundlePath to POSIX path of (path to me)
    set macOSPath to bundlePath & "Contents/MacOS/"
    set resourcesPath to bundlePath & "Contents/Resources/"
    set logDir to resourcesPath & "data/logs/"
    
    -- Create log directory
    do shell script "mkdir -p '" & logDir & "' 2>/dev/null; chmod 700 '" & resourcesPath & "data/' 2>/dev/null; true"
    
    -- ── Launch Spring Boot backend ─────────────────────────────
    try
        set backendPID to do shell script "cd '" & macOSPath & "' && nohup ./launch-backend.sh >> '" & logDir & "backend.log' 2>&1 & echo $!"
    on error
        set backendPID to "0"
    end try
    
    -- ── Setup NSApplication ────────────────────────────────────
    set NSApp to current application's NSApplication's sharedInstance()
    NSApp's setActivationPolicy:(current application's NSApplicationActivationPolicyRegular) -- show in Dock
    NSApp's setDelegate:me
    NSApp's activateIgnoringOtherApps:true
    
    -- ── Create menu bar ────────────────────────────────────────
    my createMenuBar()
    
    -- ── Create main window ─────────────────────────────────────
    set screenFrame to current application's NSScreen's mainScreen()'s visibleFrame()
    set scrW to (screenFrame's |size|()'s width) as real
    set scrH to (screenFrame's |size|()'s height) as real
    set scrX to (screenFrame's origin()'s x) as real
    set scrY to (screenFrame's origin()'s y) as real
    
    set w to 1280
    set h to 800
    if w > scrW - 40 then set w to scrW - 40
    if h > scrH - 40 then set h to scrH - 40
    set x to scrX + (scrW - w) / 2
    set y to scrY + (scrH - h) / 2
    
    set styleMask to (current application's NSTitledWindowMask) + ¬
        (current application's NSClosableWindowMask) + ¬
        (current application's NSMiniaturizableWindowMask) + ¬
        (current application's NSResizableWindowMask)
    
    set mainWindow to current application's NSWindow's alloc()'s ¬
        initWithContentRect:(current application's NSMakeRect(x, y, w, h)) ¬
        styleMask:styleMask ¬
        backing:(current application's NSBackingStoreBuffered) ¬
        defer:false
    
    mainWindow's setTitle:"macOS OCX"
    mainWindow's setTitlebarAppearsTransparent:true
    mainWindow's setTitleVisibility:(current application's NSHidden)
    mainWindow's setReleasedWhenClosed:false
    mainWindow's setDelegate:me
    mainWindow's makeKeyAndOrderFront:null
    
    -- ── Create WKWebView ──────────────────────────────────────
    set webConfig to current application's WKWebViewConfiguration's alloc()'s init()
    set webView to current application's WKWebView's alloc()'s ¬
        initWithFrame:(current application's NSMakeRect(0, 0, w, h)) ¬
        configuration:webConfig
    
    -- Show loading spinner
    set loadingHTML to "<!DOCTYPE html><html><head><meta charset='utf-8'>" & ¬
        "<style>*{margin:0;padding:0;box-sizing:border-box}" & ¬
        "body{display:flex;align-items:center;justify-content:center;height:100vh;" & ¬
        "font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;" & ¬
        "background:#1a1a2e;color:#eee;flex-direction:column;gap:16px}" & ¬
        ".spinner{width:40px;height:40px;border:3px solid rgba(255,255,255,0.2);" & ¬
        "border-top-color:#4fc3f7;border-radius:50%;animation:spin .8s linear infinite}" & ¬
        "@keyframes spin{to{transform:rotate(360deg)}}" & ¬
        "h2{font-weight:500}p{color:#999;font-size:14px}</style></head>" & ¬
        "<body><div class='spinner'></div><h2>macOS OCX</h2><p>正在启动服务…</p></body></html>"
    
    webView's loadHTMLString:loadingHTML baseURL:(missing value)
    mainWindow's setContentView:webView
    
    -- ── Start polling backend (after 3s delay for JVM startup) ─
    set pollCount to 0
    current application's NSTimer's scheduledTimerWithTimeInterval:3.0 ¬
        target:me ¬
        selector:"pollBackend:" ¬
        userInfo:(missing value) ¬
        repeats:false
    
    -- ── Run event loop (blocks until app quits) ────────────────
    NSApp's run()
end run

-- ── Poll backend: called by timer every 1s ─────────────────────
on pollBackend:theTimer
    set pollCount to pollCount + 1
    
    if pollCount > 60 then
        -- Timeout after 60s
        set errorHTML to "<!DOCTYPE html><html><head><meta charset='utf-8'>" & ¬
            "<style>*{margin:0;padding:0}body{display:flex;align-items:center;" & ¬
            "justify-content:center;height:100vh;font-family:-apple-system,sans-serif;" & ¬
            "background:#1a1a2e;color:#ff5252;flex-direction:column;gap:12px;" & ¬
            "text-align:center;padding:40px}h2{font-weight:600}p{color:#ccc;font-size:14px}</style></head>" & ¬
            "<body><h2>⚠️ 启动失败</h2><p>服务启动超时 (60s)</p></body></html>"
        webView's loadHTMLString:errorHTML baseURL:(missing value)
        return
    end if
    
    -- Check if server responds
    try
        set httpCode to do shell script "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 http://localhost:" & SERVER_PORT & " 2>/dev/null || echo '000'"
        
        if httpCode is in {"200", "201", "301", "302"} then
            -- ✅ Backend ready! Load the real URL
            set appURL to current application's NSURL's URLWithString:("http://localhost:" & SERVER_PORT)
            set request to current application's NSURLRequest's requestWithURL:appURL
            webView's loadRequest:request
            return
        end if
    end try
    
    -- Not ready yet — schedule next check in 1s
    current application's NSTimer's scheduledTimerWithTimeInterval:1.0 ¬
        target:me ¬
        selector:"pollBackend:" ¬
        userInfo:(missing value) ¬
        repeats:false
end pollBackend:

-- ── Window delegate: close window → quit app ──────────────────
on windowWillClose:notification
    my killBackend()
    -- Small delay then quit
    delay 0.2
    NSApp's terminate:(missing value)
end windowWillClose:

-- ── App delegate: last window closed → quit ───────────────────
on applicationShouldTerminateAfterLastWindowClosed:theApplication
    return true
end applicationShouldTerminateAfterLastWindowClosed:

on applicationShouldTerminate:theApplication
    my killBackend()
    return current application's NSTerminateNow
end applicationShouldTerminate:

-- ── Kill backend process ──────────────────────────────────────
on killBackend()
    try
        do shell script "pkill -f 'ocx-worker.jar' 2>/dev/null; pkill -f 'launch-backend.sh' 2>/dev/null; true"
    end try
end killBackend

-- ── Create minimal menu bar ───────────────────────────────────
on createMenuBar()
    set mainMenu to current application's NSMenu's alloc()'s init()
    
    -- Application submenu
    set subMenu to current application's NSMenu's alloc()'s init()
    set topItem to current application's NSMenuItem's alloc()'s initWithTitle:"macOS OCX" action:(missing value) keyEquivalent:""
    topItem's setSubmenu:subMenu
    
    subMenu's addItem:((current application's NSMenuItem's alloc()'s initWithTitle:"关于 macOS OCX" action:"orderFrontStandardAboutPanel:" keyEquivalent:""))
    subMenu's addItem:(current application's NSMenuItem's separatorItem())
    subMenu's addItem:((current application's NSMenuItem's alloc()'s initWithTitle:"隐藏 macOS OCX" action:"hide:" keyEquivalent:"h"))
    subMenu's addItem:((current application's NSMenuItem's separatorItem()))
    subMenu's addItem:((current application's NSMenuItem's alloc()'s initWithTitle:"退出 macOS OCX" action:"terminate:" keyEquivalent:"q"))
    
    mainMenu's addItem:topItem
    NSApp's setMainMenu:mainMenu
end createMenuBar
