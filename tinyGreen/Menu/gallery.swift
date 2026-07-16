#if DEBUG
import AppKit

final class DebugGallery: NSObject {
    private var window: NSWindow?
    private lazy var demo = StatusMenu(shiftLock: ShiftLock(), led: MenuBarLED())

    func show() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        stack.addArrangedSubview(sectionHeader("메뉴바 아이콘 — Render"))
        stack.addArrangedSubview(cardRow([
            iconCard("도트 active", Render.menuBarDot(active: true)),
            iconCard("도트 inactive", Render.menuBarDot(active: false)),
            iconCard("도트 error", Render.menuBarDot(active: false, error: true)),
        ]))
        stack.addArrangedSubview(cardRow([
            iconCard("한 narrow", Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: true)),
            iconCard("A narrow", Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: false)),
            iconCard("한 wide unlit", Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: true)),
            iconCard("A wide unlit", Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: false)),
        ]))
        stack.addArrangedSubview(cardRow([
            iconCard("한 wide lit", Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: true)),
            iconCard("A wide lit", Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: false)),
            iconCard("한 green", Render.menuBarInputSourceImageGreen(isKorean: true)),
            iconCard("A green", Render.menuBarInputSourceImageGreen(isKorean: false)),
        ]))

        stack.addArrangedSubview(sectionHeader("메뉴 글리프 — Glyphs"))
        var symbols: [NSView] = []
        for name in ["info.circle", "lock.fill", "eye.slash", "menubar.rectangle", "keyboard"] {
            if let img = Glyphs.symbol(name) { symbols.append(iconCard(name, img)) }
        }
        if let cm = Glyphs.checkmark { symbols.append(iconCard("checkmark", cm)) }
        stack.addArrangedSubview(cardRow(symbols))
        stack.addArrangedSubview(cardRow([
            iconCard("stateDot", Glyphs.stateDot),
            iconCard("errorDot", Glyphs.errorDot),
            iconCard("quitDot", Glyphs.quitDot),
        ]))
        stack.addArrangedSubview(cardRow([
            titleCard("hanTitle", Glyphs.hanTitle),
            titleCard("aTitle", Glyphs.aTitle),
        ]))

        stack.addArrangedSubview(sectionHeader("메뉴 — 펼친 모습 (에러·보안 줄 포함, 실제 buildMenu 항목)"))
        stack.addArrangedSubview(menuPreview())

        stack.addArrangedSubview(sectionHeader("창 · 모달"))
        stack.addArrangedSubview(cardRow([
            button("실제 메뉴 모양 (popUp)", #selector(popUpMenu(_:))),
            button("About 패널", #selector(openAbout)),
        ]))
        stack.addArrangedSubview(cardRow([
            button("권한 안내 alert", #selector(openPermAlert)),
            button("실패: 키 매핑", #selector(openMappingAlert)),
            button("실패: 입력 감지", #selector(openRouterAlert)),
            button("실패: LED 연결", #selector(openLEDAlert)),
        ]))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        win.title = "tinyGreen — UI 갤러리 (DEBUG)"
        win.contentView = scroll
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }


    private func cardRow(_ cards: [NSView]) -> NSView {
        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        return row
    }

    private func sectionHeader(_ text: String) -> NSView {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func iconCard(_ label: String, _ image: NSImage) -> NSView {
        let well = makeWell()
        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleNone
        iv.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(iv)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            well.heightAnchor.constraint(equalToConstant: 38),
            iv.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])
        return labeledCard(well, label)
    }

    private func titleCard(_ label: String, _ attr: NSAttributedString) -> NSView {
        let well = makeWell()
        let field = NSTextField(labelWithAttributedString: attr)
        field.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(field)
        NSLayoutConstraint.activate([
            well.heightAnchor.constraint(equalToConstant: 38),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
        ])
        return labeledCard(well, label)
    }

    private func makeWell() -> NSView {
        let well = NSView()
        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
        well.layer?.cornerRadius = 6
        well.translatesAutoresizingMaskIntoConstraints = false
        return well
    }

    private func labeledCard(_ well: NSView, _ label: String) -> NSView {
        let lab = NSTextField(labelWithString: label)
        lab.font = .systemFont(ofSize: 10)
        lab.textColor = .secondaryLabelColor
        lab.alignment = .center
        let v = NSStackView(views: [well, lab])
        v.orientation = .vertical
        v.spacing = 4
        v.alignment = .centerX
        return v
    }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        return b
    }


    private func menuPreview() -> NSView {
        let menu = demo.buildMenu()
        demo.errorItem?.attributedTitle = StatusMenu.secondaryMenuTitle("키 매핑 적용 실패 (데모)")
        demo.errorItem?.isHidden = false
        demo.secureInputItem?.attributedTitle = StatusMenu.secondaryMenuTitle("보안 입력 중 — 한영 전환 일시정지")
        demo.secureInputItem?.isHidden = false

        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 3
        col.translatesAutoresizingMaskIntoConstraints = false
        col.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        appendItems(menu.items, to: col, indent: 0)

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: box.topAnchor),
            col.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            col.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            box.widthAnchor.constraint(equalToConstant: 300),
        ])
        return box
    }

    private func appendItems(_ items: [NSMenuItem], to col: NSStackView, indent: CGFloat) {
        for item in items where !item.isHidden {
            col.addArrangedSubview(menuItemRow(item, indent: indent))
            if let sub = item.submenu {
                appendItems(sub.items, to: col, indent: indent + 22)
            }
        }
    }

    private func menuItemRow(_ item: NSMenuItem, indent: CGFloat) -> NSView {
        if item.isSeparatorItem {
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
            sep.widthAnchor.constraint(equalToConstant: 250).isActive = true
            return sep
        }
        let icon = NSImageView()
        icon.image = item.image
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let title: NSTextField
        if let attr = item.attributedTitle, attr.length > 0 {
            title = NSTextField(labelWithAttributedString: attr)
        } else {
            title = NSTextField(labelWithString: item.title)
            title.font = .menuFont(ofSize: 0)
        }

        let row = NSStackView(views: [icon, title])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 1, left: indent, bottom: 1, right: 0)
        return row
    }


    @objc private func popUpMenu(_ sender: NSButton) {
        let menu = demo.buildMenu()
        menu.delegate = nil
        disarm(menu)
        demo.errorItem?.attributedTitle = StatusMenu.secondaryMenuTitle("키 매핑 적용 실패 (데모)")
        demo.errorItem?.isHidden = false
        demo.secureInputItem?.attributedTitle = StatusMenu.secondaryMenuTitle("보안 입력 중 — 한영 전환 일시정지")
        demo.secureInputItem?.isHidden = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    private func disarm(_ menu: NSMenu) {
        menu.autoenablesItems = false
        for item in menu.items {
            item.action = nil
            item.target = nil
            if let sub = item.submenu { disarm(sub) }
        }
    }

    @objc private func openAbout() { demo.showAbout() }
    @objc private func openPermAlert() {
        _ = Permissions.showMissingAlert(missing: ["손쉬운 사용 (Accessibility)", "입력 모니터링 (Input Monitoring)"])
    }
    @objc private func openMappingAlert() { demo.showSystemLevelFailureAlert(category: .mappingApply) }
    @objc private func openRouterAlert() { demo.showSystemLevelFailureAlert(category: .routerStart) }
    @objc private func openLEDAlert() { demo.showSystemLevelFailureAlert(category: .ledOpen) }
}
#endif
