import AppKit

private enum SignalGuard {
    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        for sig in [SIGTERM, SIGINT, SIGHUP] as [Int32] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                _ = Remap.revert()
                NSApp.terminate(nil)
            }
            src.resume()
            sources.append(src)
        }
    }
}

if let bundleID = Bundle.main.bundleIdentifier {
    let me = NSRunningApplication.current.processIdentifier
    if let existing = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleID)
        .first(where: { $0.processIdentifier != me }) {
        existing.activate(options: [])
        exit(0)
    }
}

SignalGuard.install()
Settings.registerDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
