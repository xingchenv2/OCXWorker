import Cocoa
import WebKit

// ──────────────────────────────────────────────────────────────
// macOS OCX — Native WebView Wrapper
//
// Launches Spring Boot backend, then opens a native macOS window
// with WKWebView pointing at localhost:8818.
// No browser needed — operates entirely within the app window.
// ──────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var process: Process?
    let serverPort = 8818

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start Spring Boot backend
        launchBackend()

        // Create native window with WebView
        let screenRect = NSScreen.main!.visibleFrame
        let windowWidth = min(1280, screenRect.width - 40)
        let windowHeight = min(800, screenRect.height - 40)
        let windowX = (screenRect.width - windowWidth) / 2 + screenRect.origin.x
        let windowY = (screenRect.height - windowHeight) / 2 + screenRect.origin.y

        window = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "macOS OCX"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Configure WebView
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "macOS-OCX-WebView/2.0.1"
        webView.setValue(false, forKey: "drawsBackground") // transparent until loaded

        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        // Show loading page immediately
        let loadingHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><style>
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
        </body></html>
        """
        webView.loadHTMLString(loadingHTML, baseURL: nil)

        // Wait for backend, then load the real URL
        waitForBackendAndLoad()
    }

    // ── Launch Spring Boot backend via launch.sh ──────────────
    func launchBackend() {
        let bundle = Bundle.main.bundlePath
        let launchScript = bundle + "/Contents/MacOS/launch-backend.sh"

        process = Process()
        process!.executableURL = URL(fileURLWithPath: "/bin/bash")
        process!.arguments = [launchScript]
        process!.environment = ProcessInfo.processInfo.environment

        // Pipe backend output to log file (not terminal)
        let logDir = bundle + "/Contents/Resources/data/logs"
        let logPath = logDir + "/backend.log"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        if let logFile = FileHandle(forUpdatingAtPath: logPath) ?? FileHandle(forWritingAtPath: logPath) {
            process!.standardOutput = logFile
            process!.standardError = logFile
        }

        try? process!.run()
    }

    // ── Poll localhost until backend is ready ──────────────────
    func waitForBackendAndLoad() {
        let url = URL(string: "http://localhost:\(serverPort)")!
        var attempts = 0
        let maxAttempts = 60 // 60 seconds max

        func tryConnect() {
            attempts += 1
            if attempts > maxAttempts {
                showError("服务启动超时，请检查日志：\nContents/Resources/data/logs/backend.log")
                return
            }

            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                if let response = response as? HTTPURLResponse, response.statusCode == 200 || response.statusCode == 302 {
                    // Backend is ready — load in WebView
                    DispatchQueue.main.async {
                        self?.webView.load(URLRequest(url: url))
                    }
                } else {
                    // Not ready yet — retry after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        tryConnect()
                    }
                }
            }
            task.resume()
        }

        // Start checking after 3 seconds (give JVM time to start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            tryConnect()
        }
    }

    // ── Show error in WebView ──────────────────────────────────
    func showError(_ message: String) {
        let errorHTML = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { display: flex; align-items: center; justify-content: center;
               height: 100vh; font-family: -apple-system, sans-serif;
               background: #1a1a2e; color: #ff5252; flex-direction: column; gap: 12px; text-align: center; padding: 40px; }
        h2 { font-weight: 600; }
        p { color: #ccc; font-size: 14px; white-space: pre-line; }
        </style></head>
        <body>
          <h2>⚠️ 启动失败</h2>
          <p>\(message)</p>
        </body></html>
        """
        webView.loadHTMLString(errorHTML, baseURL: nil)
    }

    // ── Handle window close → kill backend ─────────────────────
    func applicationWillTerminate(_ notification: Notification) {
        process?.terminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Closing the window quits the app
    }
}

// ── Entry point ────────────────────────────────────────────────
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
