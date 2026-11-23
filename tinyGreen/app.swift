import AppKit
import IOKit.hid
import os

private let log = Logger.tinyGreen("AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionsTimer: Timer?
    private var isCoreRunning = false
    private let router = Router()
    private let watcher = Watcher()
    /// 무엇을 비출지 판가름 — easterEgg>shiftLock>base → DisplayIntent. 두 표면이 콜백 구독.
    private let priority = Priority()
    private let capsLockLED = CapsLockLED()
    private let menuBarLED = MenuBarLED()
    private let shiftLock = ShiftLock()
    private let morse = Morse()
    /// 창 배치(ADR-0009) — 단축키(Router)와 URL 스킴 두 입구가 같은 것을 부른다.
    private lazy var statusMenu = StatusMenu(shiftLock: shiftLock, led: menuBarLED)
    private let observers = ObserverBag()
    /// 현재 입력 소스 한/영 캐시 — 시작 sync 알림·wake 재동기화의 원천. TIS 직접 조회 회피.
    /// .tinyGreenInputSourceChanged 알림으로 갱신되며, 같은 자리에서 Router.tapState 로도 push
    /// (tap 콜백은 전용 스레드라 이 프로퍼티를 직접 못 읽는다 — router.swift "스레딩").
    private var isKoreanCache: Bool = false
    /// App Nap 방어. LSUIElement 메뉴바 앱은 idle 중 throttle 대상 — 키보드 오래 안 쓰다
    /// 첫 입력 시 CGEventTap 콜백 + LED 가 굼뜸. 코어 동작 구간에만 assertion 보유,
    /// teardown 시 해제. .allowingIdleSystemSleep — 시스템 sleep 은 정상 허용 (didWake 가 별도 복구).
    private var coreActivity: NSObjectProtocol?
    /// tap 자가치유 churn 방지 — 재생성한 포트도 즉시 죽는 환경(권한 영구 박탈 등)에서
    /// disable 이벤트마다 stop()/start() 무한 반복 차단. 둘 다 main 에서만 접근 (wake 핸들러
    /// + onTapNeedsRecreate 의 main.async) 이라 동기화 불필요.
    private var lastRestartAt = Date.distantPast
    private var rapidRestartCount = 0

    #if DEBUG
    /// Debug 빌드 전용 UI 갤러리 — 모든 사용자 대면 표면을 한 윈도우에. Release 미포함 (#if DEBUG).
    private var gallery: DebugGallery?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 먼저 — 권한 없을 때도 사용자가 도트 + 메뉴 (에러 표시) 볼 수 있게
        menuBarLED.start()
        // 메뉴의 라디오 선택은 매핑 소유자인 AppDelegate를 거친다. 코어가 아직 권한
        // 대기 중이면 설정만 저장하고, 다음 startCore()가 새 키를 적용한다.
        statusMenu.onTransitionKeyChange = { [weak self] key in
            self?.changeTransitionKey(to: key) ?? false
        }
        statusMenu.onExtraChange = { [weak self] key, enabled in
            self?.changeExtra(key, enabled: enabled) ?? false
        }
        statusMenu.start()
        bootstrap()
        #if DEBUG
        // 자동으로 안 띄움 — 보고 싶을 때만 `open tinyGreen.app --args -gallery`.
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            gallery = DebugGallery()
            gallery?.show()
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    /// Spotlight 등에서 이미 실행 중인 tinyGreen 을 다시 열 때 — 숨김 상태였으면 메뉴바 아이콘 복원.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenu.showMenuBarIcon()
        return true
    }

    private func bootstrap() {
        // IOHIDRequestAccess 를 *AXIsProcessTrustedWithOptions 보다 먼저* 호출.
        // OpenRadar #7381305: AX 가 먼저 호출되면 IOHIDRequestAccess 가 prompt 안 띄움
        // + 시스템 설정 입력 모니터링 list 에 자동 등록 안 됨 (tccd silent fail).
        // 첫 호출이면 시스템 prompt 동기 표시 + list 자동 등록.
        let imOk = Permissions.requestInputMonitoring() || Permissions.checkInputMonitoring()
        let axOk = Permissions.checkAccessibility()

        if axOk && imOk {
            startCore()
            return
        }

        // 메뉴바 errorState — 두 권한 모두 표시 (재발생 시 안내 path 유지).
        var missing: [String] = []
        if !axOk { missing.append("손쉬운 사용 (Accessibility)") }
        if !imOk { missing.append("입력 모니터링 (Input Monitoring)") }
        Notification.postTinyGreenCoreError("권한 필요: \(missing.joined(separator: ", "))", category: .permissions)

        // NSAlert 안내는 *Accessibility 만*. Input Monitoring 은 IOHIDRequestAccess 가
        // 자체 시스템 prompt 띄우니 별도 안내 불필요 — 두 modal 충돌 회피 + 각 권한의
        // 자연스러운 path 따라감 (AX = list 자동 등록 후 토글 ON / IM = 시스템 prompt).
        // 모달 alert 은 첫 실행 시 한 번만 — 이후엔 메뉴바 빨간 도트 + 에러 항목으로 안내.
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
            Notification.postTinyGreenCoreError(nil)  // 권한 에러 메시지 clear
            self.startCore()
        }
    }

    private func startCore() {
        guard !isCoreRunning else { return }

        // 두 모드 다 Caps를 hidutil로 떼어내므로, 매핑이 서면 native alpha-shift를 끌 키가
        // 사라진다. 앱 밖에서 켜진 채 남은 상태(구버전·외부 도구)를 적용 전에 해제한다.
        if !NativeCapsLock.turnOffIfNeeded() {
            log.error("native Caps Lock 해제 실패 — 매핑 적용 중단")
            Notification.postTinyGreenCoreError("Caps Lock 상태 해제 실패", category: .mappingApply)
            return
        }

        guard Remap.apply() else {
            log.error("hidutil 매핑 적용 실패")
            Notification.postTinyGreenCoreError("키 매핑 적용 실패", category: .mappingApply)
            return
        }
        if let mapping = Remap.currentMapping() {
            log.info("매핑 적용 — UserKeyMapping:\n\(mapping, privacy: .public)")
        }

        isKoreanCache = watcher.currentIsKorean()
        let transitionKey = Settings.transitionKey

        // Router 배선은 전부 start() *전에* — tap 콜백(전용 스레드)이 이 프로퍼티들을 lock 없이
        // 읽는 안전이 "start 전 설정 후 불변" 규약에 기댄다 (router.swift 클래스 주석 "스레딩").
        router.shiftLock = shiftLock
        router.update(isKorean: isKoreanCache)
        router.update(transitionKey: transitionKey)
        router.update(searchKeyEnabled: Settings.extraEnabled(.search))
        router.onShiftCapsKorean = { [weak self] in
            self?.morse.trigger()
        }
        // tap 죽은 포트 감지 시 자가치유 — handleTapDisabled(main) 에서 올라오므로 바로 재생성.
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

        // 무엇을 비출지(우선순위 easterEgg>shiftLock>base + 점멸 타이밍) = Priority.
        // 두 표면(LED·메뉴바)이 콜백 구독해 렌더만 — Menu→Indication 방향 유지, 새 알림 안 깖(직접 콜백).
        // 표면의 게이트(LED 점멸 항상·capsLock 사용 / 메뉴바 error 단락·점멸 게이트·menuBar 사용)는 각자.
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
            // 비춤(LED·메뉴바)은 Priority→indicate 담당. 여기선 앱 캐시 + Router tapState push +
            // 한영 전환 시 Shift Lock 자동 해제 — 보이는 것 = 실제 상태 일치 (사용자 모델 우선).
            // 시작 시점 sync 알림도 거치지만 isActive=false 라 noop, 안전.
            self.router.update(isKorean: isKor)
            self.shiftLock.reset()
        }
        // Shift Lock 상태 → Router tapState push — 콜백(tap 스레드)의 Shift 끼얹기 판정용.
        // Priority 와 같은 알림을 구독하되 여기선 스냅샷 동기화만 (비춤은 Priority 몫).
        observers.add(name: .tinyGreenShiftLockChanged) { [weak self] notif in
            guard let self = self else { return }
            let active = (notif.userInfo?[Notification.shiftLockActiveKey] as? Bool) ?? false
            self.router.update(shiftLockActive: active)
        }
        watcher.start()

        // Sleep/wake 후 standby 복구 — 첫 Caps 입력 lag 방지.
        // hidutil 매핑은 sleep 살아남는 가정 (peer 5개 도구 — FOCD/HyperCaps/macism/kawa/Gureum
        // 모두 명시 핸들러 없음). CGEventTap re-enable + 입력 소스 캐시 재동기화만 수행.
        observers.add(name: NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] _ in
            guard let self = self, self.isCoreRunning else { return }
            log.info("wake — standby 복구")
            // revalidate 가 false = CFMachPort 무효화 (죽은 포트) → 재생성으로 에스컬레이션.
            if !self.router.revalidate() {
                self.restartRouter()
            }
            self.isKoreanCache = self.watcher.currentIsKorean()
            NotificationCenter.default.post(
                name: .tinyGreenInputSourceChanged,
                object: nil,
                userInfo: [Notification.isKoreanKey: self.isKoreanCache]
            )
            // BT/외장 키보드는 sleep 중 LED 를 제 상태로 리셋함 — 위 post 가 Priority→indicate 로
            // base 를 다시 그리지만(indicate 의 0.3s 안전망 포함), 하드웨어 강제 재동기화로 한 번 더 확실히.
            self.capsLockLED.reassert()
            // 깊은 sleep 직후 WindowServer/IOHID re-init race — 첫 revalidate 후 tap 이
            // 조용히 다시 disable 되는 케이스 관찰됨 (AltTab 본가 경험). 두 번째 revalidate 가
            // 여전히 false 면 tapEnable 로는 못 살리는 죽은 포트 → 재생성.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.isCoreRunning else { return }
                if !self.router.revalidate() {
                    self.restartRouter()
                }
            }
        }

        // 시작 시점 sync — Priority 의 isKorean 이 initial false 인 채로 한국어 모드 진입 시
        // 잘못 비춤 방지 (→ indicate 로 두 표면 base 갱신). watcher.start() 가 이미 publish 하지만 명시적 안전망.
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

        // 첫 실행 (권한 grant 완료 후 코어 시작 시점) 에 한 번만 로그인 자동 시작 묻기.
        // 권한 alert 와 spacing — 사용자가 권한 grant 끝낸 후 자연스럽게 next-step.
        statusMenu.askAboutLoginItemIfFirstRun()
    }

    /// 메뉴에서 전환 키를 바꾸는 단일 이음매. 활성 코어에서는 hidutil array를 한 번
    /// 읽어 이전 키의 원본 복원과 새 키 충돌 stash를 함께 처리한다. 실패 시 설정값도
    /// 바꾸지 않아 메뉴 라디오와 실제 입력 경로가 갈라지지 않는다.
    private func changeTransitionKey(to key: TransitionKey) -> Bool {
        guard key != Settings.transitionKey else { return true }

        // 앱 밖에서 켜진 채 남은 native alpha-shift가 있으면 재배선 전에 해제한다
        // (두 모드 다 Caps를 떼어내므로 매핑이 선 뒤엔 끌 키가 없다). 코어가 아직
        // 시작되지 않았어도 메뉴 선택 시 이 안전망은 적용한다.
        if !NativeCapsLock.turnOffIfNeeded() {
            log.error("native Caps Lock 해제 실패 — 전환 키 변경 중단")
            Notification.postTinyGreenCoreError("Caps Lock 상태 해제 실패", category: .mappingApply)
            return false
        }

        // 권한 대기/코어 미가동 상태에서는 mapping을 건드리지 않는다. 다음 bootstrap이
        // Settings.transitionKey를 읽어 선택 키에만 매핑을 적용한다.
        guard isCoreRunning else {
            Settings.transitionKey = key
            return true
        }

        guard Remap.switchTransitionKey(to: key) else {
            log.error("전환 키 변경 실패 — 기존 키 유지")
            Notification.postTinyGreenCoreError("전환 키 변경 실패", category: .mappingApply)
            return false
        }
        Settings.transitionKey = key
        router.update(transitionKey: key)
        // 모드 전환은 대문자 잠금을 깨끗한 상태에서 다시 시작한다 — 방아쇠가 바뀌는데
        // 잠금이 이월되면 어느 키가 켰는지 모호해진다.
        shiftLock.reset()
        Notification.postTinyGreenCoreError(nil)
        log.info("전환 키 변경 완료 — \(key.menuTitle, privacy: .public)")
        return true
    }

    /// 메뉴에서 기능 키 옵션을 켜고 끄는 이음매 — changeTransitionKey와 같은 계약:
    /// 코어가 돌면 hidutil 재배선이 성공한 뒤에만 설정을 커밋하고 Router에 알린다.
    private func changeExtra(_ key: ExtraKey, enabled: Bool) -> Bool {
        guard isCoreRunning else {
            Settings.setExtraEnabled(key, enabled)
            return true
        }
        var next = Settings.enabledExtras
        if enabled { next.insert(key) } else { next.remove(key) }
        guard Remap.switchExtras(to: next) else {
            log.error("기능 키 변경 실패 — 기존 배선 유지")
            Notification.postTinyGreenCoreError("기능 키 변경 실패", category: .mappingApply)
            return false
        }
        Settings.setExtraEnabled(key, enabled)
        if key == .search { router.update(searchKeyEnabled: enabled) }
        Notification.postTinyGreenCoreError(nil)
        log.info("기능 키 변경 완료 — \(key.rawValue, privacy: .public)=\(enabled, privacy: .public)")
        return true
    }

    /// tap 자가치유 — 죽은 CFMachPort 는 tapEnable 로 못 살리니 stop()+start() 로 새 tap 생성.
    /// router 의 콜백 프로퍼티(onShiftCapsKorean 등)는 stop/start 에 보존되니 재주입 불필요 —
    /// start() 는 CFMachPort + runLoopSource 만 다시 만듦.
    private func restartRouter() {
        guard isCoreRunning else { return }
        // churn 안전망: 2초 내 연속 재생성이 5회 넘으면 중단 + 에러 표시.
        // 재생성한 tap 도 즉시 죽는 만성 결함을 silent 무한 churn 대신 진단 가능한 상태로.
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
        // statusMenu·menuBarLED 는 권한 무관 항상 start 됨 — guard 밖에서 stop.
        statusMenu.stop()
        menuBarLED.stop()
        morse.stop()
        shiftLock.reset()
        guard isCoreRunning else {
            // 부분 시작 실패(매핑 적용 성공 + 코어 미가동 + 즉석 revert 일시 실패) 잔존 정리 재시도.
            // 정상 미가동 경로에선 didAddOurMapping=false 라 no-op.
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
