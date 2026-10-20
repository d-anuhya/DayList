import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum DayListMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Where the widget sits relative to other windows.
enum Placement: String, CaseIterable {
    case desktop, normal, onTop

    var title: String {
        switch self {
        case .desktop: "On the Desktop (behind windows)"
        case .normal: "Like a Normal Window"
        case .onTop: "Always on Top"
        }
    }

    var level: NSWindow.Level {
        switch self {
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal: .normal
        case .onTop: .floating
        }
    }
}

/// Borderless panels refuse keyboard focus by default; the "Add a task" field needs it.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = TaskStore()
    private let calendarStore = CalendarStore()
    private var panel: WidgetPanel!
    private var weekWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    private var placement: Placement {
        get { Placement(rawValue: UserDefaults.standard.string(forKey: "placement") ?? "") ?? .desktop }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "placement"); applyPlacement() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        makePanel()
        makeStatusItem()
        calendarStore.requestAccess()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.rollOverIfNeeded() }
        }
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusBadge() }
            .store(in: &cancellables)
        updateStatusBadge()
    }

    // MARK: - Widget window

    private func makePanel() {
        panel = WidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 440),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(width: 260, height: 300)

        let host = NSHostingView(rootView: DayListView(store: store, calendarStore: calendarStore) { [weak self] in
            self?.showWeek()
        })
        host.sizingOptions = []
        panel.contentView = host

        if !panel.setFrameUsingName("DayListWidget"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 300 - 24, y: screen.maxY - 440 - 24))
        }
        panel.setFrameAutosaveName("DayListWidget")

        applyPlacement()
        panel.orderFrontRegardless()
    }

    private func applyPlacement() {
        panel.level = placement.level
        panel.collectionBehavior = placement == .normal
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    // MARK: - Menu bar

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "DayList")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Shows how many tasks are left next to the menu bar icon.
    private func updateStatusBadge() {
        let left = store.remainingCount
        statusItem?.button?.title = left > 0 ? " \(left)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: panel.isVisible ? "Hide Widget" : "Show Widget", action: #selector(toggleWidget), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let week = NSMenuItem(title: "Show Week…", action: #selector(showWeek), keyEquivalent: "")
        week.target = self
        menu.addItem(week)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for option in Placement.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(choosePlacement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == placement ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit DayList", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    // MARK: - Week window

    @objc private func showWeek() {
        if weekWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "DayList — Week"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WeekView(store: store, calendarStore: calendarStore))
            window.minSize = NSSize(width: 800, height: 560)
            if !window.setFrameUsingName("DayListWeek") { window.center() }
            window.setFrameAutosaveName("DayListWeek")
            weekWindow = window
        }
        // DayList has no Dock icon, so bring it forward explicitly.
        NSApp.activate()
        weekWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func choosePlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = Placement(rawValue: raw) else { return }
        placement = option
        panel.orderFrontRegardless()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTry moving DayList to your Applications folder, or add it under System Settings → General → Login Items."
            alert.runModal()
        }
    }
}
