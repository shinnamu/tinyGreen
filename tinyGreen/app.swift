import AppKit
import IOKit.hid
import os

private let log = Logger.tinyGreen("AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionsTimer: Timer?
    private var isCoreRunning = false
    private let router = Router()
    private let watcher = Watcher()
    private let priority = Priority()
    private let capsLockLED = CapsLockLED()
    private let menuBarLED = MenuBarLED()
    private let shiftLock = ShiftLock()
    private let morse = Morse()
    private lazy var statusMenu = StatusMenu(shiftLock: shiftLock, led: menuBarLED)
    private let observers = ObserverBag()
    private var isKoreanCache: Bool = false
    private var coreActivity: NSObjectProtocol?
    private var lastRestartAt = Date.distantPast
    private var rapidRestartCount = 0

    #if DEBUG
    private var gallery: DebugGallery?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarLED.start()
        statusMenu.start()
        bootstrap()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            gallery = DebugGallery()
            gallery?.show()
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenu.showMenuBarIcon()
        return true
    }

    private func bootstrap() {
        let imOk = Permissions.requestInputMonitoring() || Permissions.checkInputMonitoring()
        let axOk = Permissions.checkAccessibility()

        if axOk && imOk {
            startCore()
            return
        }

        var missing: [String] = []
        if !axOk { missing.append("손쉬운 사용 (Accessibility)") }
        if !imOk { missing.append("입력 모니터링 (Input Monitoring)") }
        Notification.postTinyGreenCoreError("권한 필요: \(missing.joined(separator: ", "))", category: .permissions)

        if !axOk && !Settings.hasShownPermissionAlert {
            if Permissions.showMissingAlert(missing: ["손쉬운 사용 (Accessibility)"]) {
                Permissions.openAccessibilitySettings()
            }
            Settings.hasShownPermissionAlert = true
        }

        startPermissionsPolling()
    }

    private func startPermissionsPolling() {
        permissionsTimer?.invalidate()
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            guard Permissions.checkAccessibility(), Permissions.checkInputMonitoring() else { return }
            timer.invalidate()
            self.permissionsTimer = nil
            log.info("권한 둘 다 허용됨")
            Notification.postTinyGreenCoreError(nil)
            self.startCore()
        }
    }

    private func startCore() {
        guard !isCoreRunning else { return }

        guard Remap.apply() else {
            log.error("hidutil 매핑 적용 실패")
            Notification.postTinyGreenCoreError("키 매핑 적용 실패", category: .mappingApply)
            return
        }
        if let mapping = Remap.currentMapping() {
            log.info("매핑 적용 — UserKeyMapping:\n\(mapping, privacy: .public)")
        }

        isKoreanCache = watcher.currentIsKorean()

        router.shiftLock = shiftLock
        router.update(isKorean: isKoreanCache)
        router.onShiftCapsKorean = { [weak self] in
            self?.morse.trigger()
        }
        router.onTapNeedsRecreate = { [weak self] in
            guard let self = self, self.isCoreRunning else { return }
            log.notice("tap 죽은 포트 감지 — 재생성")
            self.restartRouter()
        }
        guard router.start() else {
            log.error("Router 시작 실패 — 매핑 해제 후 중단")
            _ = Remap.revert()
            Notification.postTinyGreenCoreError("키 입력 감지 실패", category: .routerStart)
            return
        }

        capsLockLED.start()

        priority.onChange = { [weak self] intent in
            guard let self = self else { return }
            self.capsLockLED.indicate(intent)
            self.menuBarLED.indicate(intent)
        }
        priority.start()

        observers.add(name: .tinyGreenInputSourceChanged) { [weak self] notif in
            guard let self = self else { return }
            let isKor = (notif.userInfo?[Notification.isKoreanKey] as? Bool)
                ?? self.watcher.currentIsKorean()
            self.isKoreanCache = isKor
            self.router.update(isKorean: isKor)
            self.shiftLock.reset()
        }
        observers.add(name: .tinyGreenShiftLockChanged) { [weak self] notif in
            guard let self = self else { return }
            let active = (notif.userInfo?[Notification.shiftLockActiveKey] as? Bool) ?? false
            self.router.update(shiftLockActive: active)
        }
        watcher.start()

        observers.add(name: NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] _ in
            guard let self = self, self.isCoreRunning else { return }
            log.info("wake — standby 복구")
            if !self.router.revalidate() {
                self.restartRouter()
            }
            self.isKoreanCache = self.watcher.currentIsKorean()
            NotificationCenter.default.post(
                name: .tinyGreenInputSourceChanged,
                object: nil,
                userInfo: [Notification.isKoreanKey: self.isKoreanCache]
            )
            self.capsLockLED.reassert()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.isCoreRunning else { return }
                if !self.router.revalidate() {
                    self.restartRouter()
                }
            }
        }

        NotificationCenter.default.post(
            name: .tinyGreenInputSourceChanged,
            object: nil,
            userInfo: [Notification.isKoreanKey: isKoreanCache]
        )

        coreActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Caps Lock 키 입력 즉시 응답 — idle 중 App Nap throttle 방지"
        )

        isCoreRunning = true
        log.info("코어 시작 — 매핑 + 라우터 + LED + 메뉴바 + 관찰자 활성")

        statusMenu.askAboutLoginItemIfFirstRun()
    }

    private func restartRouter() {
        guard isCoreRunning else { return }
        let now = Date()
        rapidRestartCount = now.timeIntervalSince(lastRestartAt) < 2.0 ? rapidRestartCount + 1 : 0
        lastRestartAt = now
        guard rapidRestartCount < 5 else {
            log.error("tap 재생성 반복 한계 — churn 중단")
            Notification.postTinyGreenCoreError("키 입력 감지 불안정 — 앱 재시작 또는 권한 확인 필요", category: .routerStart)
            return
        }
        guard router.recreate() else {
            log.error("tap 재생성 실패 — Accessibility / Input Monitoring 권한 확인 필요")
            Notification.postTinyGreenCoreError("키 입력 감지 끊김 — 권한 확인 필요", category: .routerStart)
            return
        }
        log.info("tap 재생성 — 자가치유 완료")
    }

    private func teardown() {
        permissionsTimer?.invalidate()
        permissionsTimer = nil
        statusMenu.stop()
        menuBarLED.stop()
        morse.stop()
        shiftLock.reset()
        guard isCoreRunning else {
            _ = Remap.revert()
            return
        }
        if let activity = coreActivity {
            ProcessInfo.processInfo.endActivity(activity)
            coreActivity = nil
        }
        observers.removeAll()
        priority.stop()
        watcher.stop()
        capsLockLED.stop()
        router.stop()
        _ = Remap.revert()
        isCoreRunning = false
        log.info("정리 완료")
    }
}
