import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var island: IslandController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        TempStorage.reset()
        store = ClipboardStore()
        monitor = ClipboardMonitor(store: store)
        store.monitor = monitor
        island = IslandController(store: store)
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // History is memory-only: nothing copied survives a quit.
        TempStorage.wipe()
    }
}

// Only one island at a time: if SmartClipBoard is already running (for example started at login
// and then opened again from Finder), leave quietly without touching the running copy's files.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0 != NSRunningApplication.current }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
