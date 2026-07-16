import Carbon.HIToolbox
import Foundation

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
        publish()
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

    func currentIsKorean() -> Bool {
        guard let ref = TISCopyCurrentKeyboardInputSource() else { return false }
        return isKorean(ref.takeRetainedValue())
    }

    private func isKorean(_ source: TISInputSource) -> Bool {
        if let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let langs = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
            if let first = langs.first, first.lowercased().hasPrefix("ko") {
                return true
            }
        }
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
