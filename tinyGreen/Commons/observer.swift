import Foundation

/// NotificationCenter observer 토큰 묶음 — start/stop pairing 자동화.
/// `DistributedNotificationCenter` 도 `NotificationCenter` 서브클래스라 동일 인터페이스로 처리.
/// 호출은 메인 스레드 가정 (NSApp lifecycle 에서만 사용 — entries 배열 lock 없음).
final class ObserverBag {
    private var entries: [(NotificationCenter, NSObjectProtocol)] = []

    func add(
        name: Notification.Name,
        center: NotificationCenter = .default,
        queue: OperationQueue? = .main,
        _ block: @escaping (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: queue, using: block)
        entries.append((center, token))
    }

    func removeAll() {
        entries.forEach { center, token in
            center.removeObserver(token)
        }
        entries.removeAll()
    }
}
