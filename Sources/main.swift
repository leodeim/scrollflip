import AppKit

enum Device: String, CaseIterable {
    case mouse, trackpad

    // Wheel mice emit discrete events; trackpads and Magic Mouse emit continuous ones.
    init(_ event: CGEvent) {
        self = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ? .trackpad : .mouse
    }

    var defaultsKey: String { "reverse.\(rawValue)" }
}

func flip(_ event: CGEvent) {
    // Read everything before writing: setting one delta field can make macOS recompute the others.
    let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let d2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let f2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let p2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -d1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -d2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -f1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -f2)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -p1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -p2)
}

private let callback: CGEventTapCallBack = { _, type, event, info in
    let controller = Unmanaged<Controller>.fromOpaque(info!).takeUnretainedValue()
    controller.handle(type, event)
    return Unmanaged.passUnretained(event)
}

final class Controller: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let accessItem = NSMenuItem(title: "Needs Accessibility access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var deviceItems: [Device: NSMenuItem] = [:]
    private var tap: CFMachPort?
    private var reversed: Set<Device> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second instance would flip events back, cancelling the first.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.contains(where: { $0 != .current }) {
            print("scrollflip: already running, exiting")
            exit(0)
        }

        UserDefaults.standard.register(defaults: [Device.mouse.defaultsKey: true])
        reversed = Set(Device.allCases.filter { UserDefaults.standard.bool(forKey: $0.defaultsKey) })

        accessItem.target = self
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(accessItem)
        for device in Device.allCases {
            let item = NSMenuItem(title: "Reverse \(device.rawValue)", action: #selector(toggle), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            deviceItems[device] = item
            menu.addItem(item)
        }
        menu.addItem(.separator())
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
        case .scrollWheel where reversed.contains(Device(event)):
            flip(event)
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
            FileHandle.standardError.write("scrollflip: failed to create event tap\n".data(using: .utf8)!)
            exit(1)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: !reversed.isEmpty)
        print("scrollflip: tap installed")
        refresh()
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? Device else { return }
        if reversed.remove(device) == nil { reversed.insert(device) }
        UserDefaults.standard.set(reversed.contains(device), forKey: device.defaultsKey)
        if let tap { CGEvent.tapEnable(tap: tap, enable: !reversed.isEmpty) }
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func refresh() {
        accessItem.isHidden = tap != nil
        for (device, item) in deviceItems {
            item.state = reversed.contains(device) ? .on : .off
        }

        let active = tap != nil && !reversed.isEmpty
        let symbol = active ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScrollFlip")
        statusItem.button?.appearsDisabled = !active
    }
}

setlinebuf(stdout)
let controller = Controller()
let app = NSApplication.shared
app.delegate = controller
app.run()
