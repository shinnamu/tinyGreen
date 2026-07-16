import AppKit
import os

private let log = Logger.tinyGreen("StatusMenu")

final class StatusMenu: NSObject {
    var statusItem: NSStatusItem?
    let observers = ObserverBag()
    var errorItem: NSMenuItem?
    weak var secureInputItem: NSMenuItem?
    weak var loginMenuItem: NSMenuItem?
    weak var shiftLockMenuItem: NSMenuItem?
    weak var shiftLockMenuBarIndicatorItem: NSMenuItem?
    weak var shiftLock: ShiftLock?
    let led: MenuBarLED
    var lastErrorMessage: String?
    var lastErrorCategory: CoreErrorCategory?

    static let menuTitleHeadIndent: CGFloat = -3

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
        guard statusItem == nil else { return }
        makeStatusItem()

        observers.add(name: .tinyGreenCoreError) { [weak self] notif in
            self?.updateError(notif)
        }
        observers.add(name: .tinyGreenAutoShowLEDOpenAlert) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.showSystemLevelFailureAlert(category: .ledOpen)
            }
        }
    }

    func showMenuBarIcon() {
        guard statusItem == nil else { return }
        makeStatusItem()
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
        led.detach()
        lastErrorMessage = nil
        lastErrorCategory = nil
    }
}
