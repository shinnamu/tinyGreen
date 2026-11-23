import Carbon.HIToolbox
import Foundation

/// 시스템 입력 소스의 상태를 *읽고* 변화를 *관찰*한다. 전환은 OS 위임(C②) — 여기선
/// 운전석(전환)을 내려놓고 관찰석만 남는다. 읽기와 관찰 둘을 한 자리에.
///
/// 1) 읽기 — `currentIsKorean()`: 메뉴바·LED·캐시가 현재 한/영을 물을 때.
/// 2) 관찰 — DistributedNotificationCenter 의 입력 소스 변경 알림을 받아 내부
///    `.tinyGreenInputSourceChanged` 로 재발행 (userInfo 에 isKorean 동봉 — 관찰자가 TIS 재조회 안 하게).
///
/// 한국어 판정: kTISPropertyInputSourceLanguages 첫 항목이 "ko*", 폴백으로 sourceID 패턴.
final class Watcher {
    private let observers = ObserverBag()
    private(set) var isStarted = false

    func start() {
        guard !isStarted else { return }
        let name = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observers.add(name: name, center: DistributedNotificationCenter.default()) { [weak self] _ in
            self?.publish()
        }
        isStarted = true
        publish()  // 초기 상태 한 번 — 첫 UI 렌더 트리거
    }

    func stop() {
        observers.removeAll()
        isStarted = false
    }

    private func publish() {
        let isKor = currentIsKorean()
        NotificationCenter.default.post(
            name: .tinyGreenInputSourceChanged,
            object: nil,
            userInfo: [Notification.isKoreanKey: isKor]
        )
    }

    /// 현재 시스템 입력 소스가 한국어인지 (외부 조회용).
    func currentIsKorean() -> Bool {
        guard let ref = TISCopyCurrentKeyboardInputSource() else { return false }
        return isKorean(ref.takeRetainedValue())
    }

    private func isKorean(_ source: TISInputSource) -> Bool {
        // 1순위: kTISPropertyInputSourceLanguages 첫 항목 "ko*"
        if let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let langs = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
            if let first = langs.first, first.lowercased().hasPrefix("ko") {
                return true
            }
        }
        // 2순위 fallback: sourceID 패턴 (구름 등 lang 정보 부실한 IME 대비)
        if let id = sourceID(of: source)?.lowercased() {
            let patterns = ["korean", "hangul", "gureum"]
            if patterns.contains(where: id.contains) {
                return true
            }
        }
        return false
    }

    private func sourceID(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let any = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
        return any as? String
    }
}
