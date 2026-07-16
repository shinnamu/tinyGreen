import Foundation

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
