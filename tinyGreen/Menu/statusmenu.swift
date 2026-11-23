import AppKit
import os

private let log = Logger.tinyGreen("StatusMenu")

/// 메뉴바 NSStatusItem·NSMenu 조정자. 메뉴 빌드·delegate·액션·About·코어에러 UI·생명주기를 쥔다.
/// 책임은 도메인 파일로 분리 — builder / action / error / about.
/// 표시(메뉴바 도트 렌더)는 형제 MenuBarLED 가 소유 — 조정자는 statusItem.button 을 attach 로 빌려준다.
/// 이 파일은 statusItem 소유 · 상태 holder · 의존성 holder · 옵저버 dispatcher · 생명주기만.
/// 저장 프로퍼티가 internal 인 이유: 같은 모듈 extension(분해 파일)에서 접근. 단일 앱 타깃이라 외부 노출 0.
final class StatusMenu: NSObject {
    var statusItem: NSStatusItem?
    let observers = ObserverBag()
    var errorItem: NSMenuItem?
    /// 보안 입력 안내 줄 — 평소 hidden. menuWillOpen 에서 IsSecureEventInputEnabled 검사로 표시.
    weak var secureInputItem: NSMenuItem?
    weak var loginMenuItem: NSMenuItem?
    weak var transitionKeyMenuItem: NSMenuItem?
    /// 전환 키를 바꾸는 코어 이음매. 메뉴는 설정/매핑의 소유자가 아니므로,
    /// AppDelegate가 Remap.switchTransitionKey(to:)를 배선하고 성공 여부만 돌려준다.
    var onTransitionKeyChange: ((TransitionKey) -> Bool)?
    /// 메뉴가 다시 만들어질 때마다 현재 라디오 항목을 보관한다.
    /// (숨기기 후 복원하면 NSMenuItem 인스턴스가 바뀐다.)
    var transitionKeyItems: [NSMenuItem] = []
    /// 기능 키 옵션을 켜고 끄는 코어 이음매 — onTransitionKeyChange와 같은 계약(성공 여부만).
    var onExtraChange: ((ExtraKey, Bool) -> Bool)?
    /// "기능 키" 서브메뉴의 토글 항목 — 숨기기 후 복원하면 인스턴스가 바뀐다.
    var extraItems: [NSMenuItem] = []
    weak var shiftLock: ShiftLock?
    /// 메뉴바 도트 표면 — 표시는 MenuBarLED 가 소유. 조정자는 makeStatusItem 시 button 을 attach,
    /// hide/stop 시 detach, 에러·게이트 변화 시 setError/refresh 로 먹인다 (단방향 — 도트는 statusItem 못 봄).
    let led: MenuBarLED
    /// 마지막 코어 에러 메시지 (nil = 에러 없음). hide 중 발생한 에러도 store 에 누적되어
    /// showMenuBarIcon 시 errorItem 재구성 + 도트 errorActive 복구에 사용.
    var lastErrorMessage: String?
    /// 마지막 에러 카테고리 — errorItem 클릭 분기 (시스템 설정 vs 자세한 alert).
    var lastErrorCategory: CoreErrorCategory?

    /// 메뉴 타이틀에 attributedTitle 사용 시 시스템이 자동 추가하는 leading padding 보정.
    /// 분해 파일(action·error extension)에서 참조하므로 internal (line 9 규약).
    static let menuTitleHeadIndent: CGFloat = -3

    /// 메뉴 정보줄(에러줄·보안입력줄)의 회색 보조 라벨 — 공통 시각 계약(menuTitleHeadIndent 보정 +
    /// secondary 색 + 메뉴 폰트). a11y 라벨은 호출처가 각자 단다.
    static func secondaryMenuTitle(_ string: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = menuTitleHeadIndent
        return NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para
            ]
        )
    }

    init(shiftLock: ShiftLock, led: MenuBarLED) {
        self.shiftLock = shiftLock
        self.led = led
        super.init()
    }

    func start() {
        guard statusItem == nil else { return }  // 중복 호출 방어
        makeStatusItem()

        // 무엇을 비출지(입력 소스·Shift Lock·Easter Egg 우선순위)는 Priority 가 정해 indicate(intent)
        // 로 준다 (AppDelegate 배선). 설정 변경 재렌더는 MenuBarLED 자가구독. 여기선 에러·F5 만 직접 구독.
        observers.add(name: .tinyGreenCoreError) { [weak self] notif in
            self?.updateError(notif)
        }
        observers.add(name: .tinyGreenAutoShowLEDOpenAlert) { [weak self] _ in
            // F5 — CapsLockLED IOHIDManagerOpen 실패 시 자동 표시 (suppressed=false 일 때만).
            // 메인 thread + 약간 delay — 다른 startup alert (권한) 와 겹치지 않게.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.showSystemLevelFailureAlert(category: .ledOpen)
            }
        }
    }

    /// 숨김 후 Spotlight 재실행 시 메뉴바 아이콘만 다시 표시.
    /// hide 중에도 Priority 콜백(indicate)이 도트의 lastIntent 를 계속 갱신해 왔으니 재sync 불필요 —
    /// makeStatusItem 의 led.attach 가 마지막 intent 를 그대로 그린다.
    func showMenuBarIcon() {
        guard statusItem == nil else { return }
        makeStatusItem()
        // hide 중 누적된 코어 에러 — lastErrorMessage 가 있으면 errorItem 재구성 + 도트 errorActive 복구.
        // category 도 같이 패스 — errorItemClicked 분기 보존.
        applyErrorMessage(lastErrorMessage, category: lastErrorCategory)
        led.refresh()
    }

    func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.menu = buildMenu()
        statusItem = item
        led.attach(item.button)
    }

    func stop() {
        observers.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        errorItem = nil
        transitionKeyMenuItem = nil
        transitionKeyItems.removeAll()
        extraItems.removeAll()
        led.detach()
        lastErrorMessage = nil
        lastErrorCategory = nil
    }
}
