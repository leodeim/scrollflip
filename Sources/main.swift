import AppKit
import ServiceManagement
import os

let log = Logger(subsystem: "com.leodeim.scrollflip", category: "app")

enum Device: String, CaseIterable {
    case mouse, trackpad

    // Wheel mice emit discrete events; trackpads and Magic Mouse emit continuous ones.
    init(_ event: CGEvent) {
        self = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ? .trackpad : .mouse
    }
}

enum Axis: String, CaseIterable {
    case vertical, horizontal

    var fields: (delta: CGEventField, fixedPt: CGEventField, point: CGEventField) {
        switch self {
        case .vertical: (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        case .horizontal: (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        }
    }
}

struct Toggle: Hashable {
    static let all = Device.allCases.flatMap { device in Axis.allCases.map { Toggle(device: device, axis: $0) } }

    let device: Device
    let axis: Axis

    var defaultsKey: String { "reverse.\(device.rawValue).\(axis.rawValue)" }
}

func flip(_ event: CGEvent, _ axes: [Axis]) {
    // Read everything before writing: setting one delta field can make macOS recompute the others.
    let values = Axis.allCases.map { axis in
        let f = axis.fields
        return (f, axes.contains(axis) ? -1 : 1 as Int64,
                event.getIntegerValueField(f.delta), event.getDoubleValueField(f.fixedPt), event.getIntegerValueField(f.point))
    }
    for (f, sign, delta, _, _) in values { event.setIntegerValueField(f.delta, value: sign * delta) }
    for (f, sign, _, fixedPt, _) in values { event.setDoubleValueField(f.fixedPt, value: Double(sign) * fixedPt) }
    for (f, sign, _, _, point) in values { event.setIntegerValueField(f.point, value: sign * point) }
}

private let callback: CGEventTapCallBack = { _, type, event, info in
    let controller = Unmanaged<Controller>.fromOpaque(info!).takeUnretainedValue()
    controller.handle(type, event)
    return Unmanaged.passUnretained(event)
}

final class Controller: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let accessItem = NSMenuItem(title: "Needs Accessibility access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private var toggleItems: [Toggle: NSMenuItem] = [:]
    private var tap: CFMachPort?
    private var reversed: Set<Toggle> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second instance would flip events back, cancelling the first.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.contains(where: { $0 != .current }) {
            log.notice("already running, exiting")
            exit(0)
        }

        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues:
            Axis.allCases.map { (Toggle(device: .mouse, axis: $0).defaultsKey, true) }))
        reversed = Set(Toggle.all.filter { UserDefaults.standard.bool(forKey: $0.defaultsKey) })

        accessItem.target = self
        loginItem.target = self
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(accessItem)
        for device in Device.allCases {
            menu.addItem(.sectionHeader(title: device.rawValue.capitalized))
            for axis in Axis.allCases {
                let toggle = Toggle(device: device, axis: axis)
                let item = NSMenuItem(title: "Reverse \(axis.rawValue)", action: #selector(toggle(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = toggle
                toggleItems[toggle] = item
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit ScrollFlip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            installTap()
        } else {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.installTap()
            }
        }
        refresh()
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if !reversed.isEmpty, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .scrollWheel:
            let device = Device(event)
            let axes = Axis.allCases.filter { reversed.contains(Toggle(device: device, axis: $0)) }
            if !axes.isEmpty { flip(event, axes) }
        default:
            break
        }
    }

    private func installTap() {
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            log.error("failed to create event tap")
            exit(1)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: !reversed.isEmpty)
        log.notice("tap installed")
        refresh()
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let toggle = sender.representedObject as? Toggle else { return }
        if reversed.remove(toggle) == nil { reversed.insert(toggle) }
        UserDefaults.standard.set(reversed.contains(toggle), forKey: toggle.defaultsKey)
        if let tap { CGEvent.tapEnable(tap: tap, enable: !reversed.isEmpty) }
        refresh()
    }

    @objc private func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("open at login: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func refresh() {
        accessItem.isHidden = tap != nil
        for (toggle, item) in toggleItems {
            item.state = reversed.contains(toggle) ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let active = tap != nil && !reversed.isEmpty
        let symbol = active ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScrollFlip")
        statusItem.button?.appearsDisabled = !active
    }
}

let controller = Controller()
let app = NSApplication.shared
app.delegate = controller
app.run()
