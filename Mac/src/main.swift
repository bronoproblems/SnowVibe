import AppKit
import Darwin

private func handOffToExistingInstance() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    let currentPID = ProcessInfo.processInfo.processIdentifier
    guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated })
    else { return }
    existing.activate(options: [.activateIgnoringOtherApps])
    exit(EXIT_SUCCESS)
}

final class OverlayController {
    private(set) var windows: [NSWindow] = []
    private var views: [SnowView] { windows.compactMap { $0.contentView as? SnowView } }
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func rebuild() {
        windows.forEach {
            ($0.contentView as? SnowView)?.stopAnimation()
            $0.orderOut(nil)
            $0.contentView = nil
        }
        windows.removeAll()
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = SnowView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame
            )
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func settingsDidChange() { views.forEach { $0.settingsDidChange() } }
    func clearSnow() { views.forEach { $0.clearSnow() } }
    func summonPlow() { views.forEach { $0.summonPlow() } }

    func startPointerMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async { self?.dispatchPointer(event.type) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dispatchPointer(event.type)
            return event
        }
    }

    private func dispatchPointer(_ type: NSEvent.EventType) {
        let point = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown: views.forEach { $0.handlePointerDown(globalPoint: point) }
        case .leftMouseDragged: views.forEach { $0.handlePointerDragged(globalPoint: point) }
        case .leftMouseUp: views.forEach { $0.handlePointerUp(globalPoint: point) }
        default: break
        }
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SnowSettings.shared
    private let overlays = OverlayController()
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlays.rebuild()
        overlays.startPointerMonitoring()
        settings.didChange = { [weak self] in self?.settingsChanged() }
        settingsController = SettingsWindowController(
            onClear: { [weak self] in self?.overlays.clearSnow() },
            onPlow: { [weak self] in self?.overlays.summonPlow() }
        )
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if ProcessInfo.processInfo.environment["SNOWVIBE_TEST_HIDE_SETTINGS"] != "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.settingsController.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "SnowVibe")
            button.image?.isTemplate = true
            button.toolTip = "SnowVibe"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Открыть SnowVibe…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Включить снег", action: #selector(toggleSnow), keyEquivalent: "s"))
        let fullscreenItem = NSMenuItem(title: "Пауза в полноэкранных приложениях", action: #selector(togglePauseFullscreen), keyEquivalent: "")
        fullscreenItem.tag = 50
        menu.addItem(fullscreenItem)
        menu.addItem(.separator())
        for style in SnowStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.tag = 100 + style.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Очистить весь снег", action: #selector(clearSnow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Запустить снегоуборщик", action: #selector(summonPlow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu.items.count > 1 {
            menu.items[1].title = settings.enabled ? "Выключить снег" : "Включить снег"
        }
        menu.items.first(where: { $0.tag == 50 })?.state = settings.pauseFullscreen ? .on : .off
        for item in menu.items where (100..<(100 + SnowStyle.allCases.count)).contains(item.tag) {
            item.state = item.tag == 100 + settings.style.rawValue ? .on : .off
        }
    }

    private func settingsChanged() {
        overlays.settingsDidChange()
        settingsController?.syncFromSettings()
    }

    @objc private func screensChanged() { overlays.rebuild() }
    @objc private func showSettings() { settingsController.show() }
    @objc private func toggleSnow() { settings.enabled.toggle() }
    @objc private func togglePauseFullscreen() { settings.pauseFullscreen.toggle() }
    @objc private func clearSnow() { overlays.clearSnow() }
    @objc private func summonPlow() { overlays.summonPlow() }
    @objc private func selectStyle(_ sender: NSMenuItem) {
        settings.style = SnowStyle(rawValue: sender.tag - 100) ?? .crystal
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

private let app = NSApplication.shared
handOffToExistingInstance()
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
