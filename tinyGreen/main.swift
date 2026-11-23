import AppKit

// 비정상 종료 안전망 — SIGTERM/SIGINT/SIGHUP 시 선택한 전환 키의 hidutil 매핑 복구 후
// 정상 종료 트리거.
// SIGSEGV/SIGABRT 같은 fatal 은 잡을 수 없어 매핑 잔존 → 다음 로그아웃에 복구.
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

// 단일 인스턴스 가드 — 이 블록(아래 NSRunningApplication 체크)이 유일 소유자.
// 중복/수동(Xcode Run·open) 실행은 기존 것 활성화 후 즉시 종료. 메뉴바 둘·CGEventTap 둘·
// hidutil 매핑 충돌 방지.
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
