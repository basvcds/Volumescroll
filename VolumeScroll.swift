import Cocoa
import CoreAudio
import ApplicationServices

// MARK: - System volume via CoreAudio

enum SystemVolume {

    static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    /// Current volume in 0.0 ... 1.0, or nil if unavailable.
    static func get() -> Float32? {
        guard let device = defaultOutputDevice() else { return nil }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        // Master channel first
        if AudioObjectHasProperty(device, &addr) {
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }

        // Fall back to averaging the stereo channels
        var total: Float32 = 0
        var count: Float32 = 0
        for ch in [UInt32(1), UInt32(2)] {
            addr.mElement = ch
            if AudioObjectHasProperty(device, &addr) {
                var v = Float32(0)
                var s = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(device, &addr, 0, nil, &s, &v) == noErr {
                    total += v; count += 1
                }
            }
        }
        return count > 0 ? total / count : nil
    }

    static func set(_ value: Float32) {
        guard let device = defaultOutputDevice() else { return }
        let clamped = max(0, min(1, value))

        // Raising above zero should unmute, like the hardware keys do.
        if clamped > 0 { setMuted(false, device: device) }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        let size = UInt32(MemoryLayout<Float32>.size)

        // Master channel if settable
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &addr),
           AudioObjectIsPropertySettable(device, &addr, &settable) == noErr,
           settable.boolValue {
            var v = clamped
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v)
            return
        }

        // Otherwise set each channel individually
        for ch in [UInt32(1), UInt32(2)] {
            addr.mElement = ch
            var settableCh: DarwinBoolean = false
            if AudioObjectHasProperty(device, &addr),
               AudioObjectIsPropertySettable(device, &addr, &settableCh) == noErr,
               settableCh.boolValue {
                var vv = clamped
                AudioObjectSetPropertyData(device, &addr, 0, nil, size, &vv)
            }
        }
    }

    static func setMuted(_ muted: Bool, device: AudioDeviceID? = nil) {
        guard let dev = device ?? defaultOutputDevice() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var val: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr),
           AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
           settable.boolValue {
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &val)
        }
    }

    /// Whether the default output device exposes a settable hardware mute.
    static func muteIsSupported() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr)
            && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr
            && settable.boolValue
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &addr),
           AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return false
    }
}

// MARK: - Menu bar hit test

/// True when the cursor is in the menu-bar strip of any screen.
///
/// We test the rect by hand with an *inclusive* top edge. CGRect.contains and
/// NSMouseInRect treat maxY as exclusive, so when the pointer is jammed against
/// the very top of the screen — exactly where you reach for the menu bar —
/// NSEvent.mouseLocation.y equals frame.maxY and .contains() returns false,
/// leaving a dead strip along the top edge.
func mouseIsOverMenuBar() -> Bool {
    let loc = NSEvent.mouseLocation
    for screen in NSScreen.screens {
        let f = screen.frame
        let menuBarHeight = f.maxY - screen.visibleFrame.maxY
        if menuBarHeight <= 0 { continue }          // this screen shows no menu bar
        let inX = loc.x >= f.minX && loc.x < f.maxX
        // +1 tolerates the pointer being clamped exactly at the top edge.
        let inMenuBarY = loc.y >= f.maxY - menuBarHeight && loc.y <= f.maxY + 1
        if inX && inMenuBarY { return true }
    }
    return false
}

// MARK: - Brand icon (drawn from the menu-bar SVG path data)

enum AppIcon {
    /// The menu-bar glyph, drawn straight from the SVG's paths so it stays crisp
    /// at any size. Returned as a *template* image: macOS renders it dark in light
    /// mode and light in dark mode automatically, and tints it to match the bar.
    static func menuBar(pointSize: CGFloat = 18) -> NSImage {
        // Speaker body — filled.  M26,48 H44 L66,29 V91 L44,72 H26 Z
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 26, y: 48))
        body.line(to: NSPoint(x: 44, y: 48))
        body.line(to: NSPoint(x: 66, y: 29))
        body.line(to: NSPoint(x: 66, y: 91))
        body.line(to: NSPoint(x: 44, y: 72))
        body.line(to: NSPoint(x: 26, y: 72))
        body.close()

        // Up / down chevrons — stroked, round caps & joins.
        let chevrons = NSBezierPath()
        chevrons.lineWidth = 9.5
        chevrons.lineCapStyle = .round
        chevrons.lineJoinStyle = .round
        chevrons.move(to: NSPoint(x: 79, y: 50))
        chevrons.line(to: NSPoint(x: 90, y: 41))
        chevrons.line(to: NSPoint(x: 101, y: 50))
        chevrons.move(to: NSPoint(x: 79, y: 71))
        chevrons.line(to: NSPoint(x: 90, y: 80))
        chevrons.line(to: NSPoint(x: 101, y: 71))

        // Tight bounds of the artwork (chevron bounds widened for the stroke),
        // so the glyph fills the bar instead of inheriting the SVG's padding.
        let content = body.bounds.union(
            chevrons.bounds.insetBy(dx: -chevrons.lineWidth / 2,
                                    dy: -chevrons.lineWidth / 2))

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize),
                            flipped: false) { rect in
            let target = rect.insetBy(dx: 1.5, dy: 1.5)
            let scale = min(target.width / content.width,
                            target.height / content.height)

            // Fit and center the artwork, flipping y (SVG is y-down, AppKit y-up).
            let t = NSAffineTransform()
            t.translateX(by: target.midX, yBy: target.midY)
            t.scaleX(by: scale, yBy: -scale)
            t.translateX(by: -content.midX, yBy: -content.midY)
            t.concat()

            NSColor.black.set()
            body.fill()
            chevrons.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - About window

final class AboutWindowController: NSObject {

    private let repoURL = "https://github.com/basvcds/Volumescroll"
    private var window: NSWindow?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func logoImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "VolumeScroll", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    func show() {
        if window == nil { window = build() }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let logo = NSImageView()
        logo.image = logoImage()
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 120).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let name = NSTextField(labelWithString: "Volume Scroll")
        name.font = .systemFont(ofSize: 20, weight: .semibold)
        name.alignment = .center

        let tagline = NSTextField(labelWithString: "Volume control from the menu bar")
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center

        let version = NSTextField(labelWithString: "Version \(appVersion)")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        version.alignment = .center

        let link = NSButton(title: "", target: self, action: #selector(openLink))
        link.isBordered = false
        link.attributedTitle = NSAttributedString(
            string: "github.com/basvcds/Volumescroll",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12)
            ])

        let stack = NSStackView(views: [logo, name, tagline, version, link])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: logo)
        stack.setCustomSpacing(4, after: name)
        stack.setCustomSpacing(10, after: version)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let size = stack.fittingSize
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "About VolumeScroll"
        w.isReleasedWhenClosed = false
        w.contentView = container
        return w
    }

    @objc private func openLink() {
        if let url = URL(string: repoURL) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {

    // --- Tunables ---
    private let step: Float32 = 1.0 / 16.0     // one mouse notch = 1/16, matching the OS
    private let invert: Float32 = 1            // set to -1 if the direction feels wrong
    private let trackpadPointsPerStep: Double = 12
    // ----------------

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trackpadAccumulator: Double = 0
    private var preMuteVolume: Float32?   // only used when the device has no hardware mute
    private let aboutController = AboutWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if !setupEventTap() {
            promptForAccessibility()
        }
    }

    // MARK: Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppIcon.menuBar()     // template image → adapts to light & dark
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About VolumeScroll",
                                action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Scroll over the menu bar to change volume",
                                action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Middle-click the menu bar to mute / unmute",
                                action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshIcon()
    }

    @objc private func showAbout() { aboutController.show() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Event tap

    @discardableResult
    private func setupEventTap() -> Bool {
        let mask = (1 << CGEventType.scrollWheel.rawValue)
                 | (1 << CGEventType.otherMouseDown.rawValue)
                 | (1 << CGEventType.otherMouseUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap if it ever stalls; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Middle-click anywhere on the menu bar toggles mute (button 2 = the wheel click).
        if type == .otherMouseDown || type == .otherMouseUp {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard button == 2, mouseIsOverMenuBar() else {
                return Unmanaged.passUnretained(event)   // not a middle click on the bar
            }
            if type == .otherMouseDown { toggleMute() }
            return nil   // consume both down and up so nothing underneath reacts
        }

        guard type == .scrollWheel, mouseIsOverMenuBar() else {
            return Unmanaged.passUnretained(event)   // not our event — let it through
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        if isContinuous {
            // Trackpad / high-resolution wheels report fine-grained point deltas.
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            trackpadAccumulator += dy
            while abs(trackpadAccumulator) >= trackpadPointsPerStep {
                let dir: Float32 = trackpadAccumulator > 0 ? 1 : -1
                adjustVolume(by: dir * step * invert)
                trackpadAccumulator -= Double(dir) * trackpadPointsPerStep
            }
        } else {
            // A classic mouse wheel reports integer line counts; one notch per line.
            let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if lines != 0 {
                let dir: Float32 = lines > 0 ? 1 : -1
                adjustVolume(by: dir * step * invert)
            }
        }

        return nil   // consume, so nothing underneath scrolls
    }

    private func adjustVolume(by delta: Float32) {
        // Scrolling up clears a fallback mute (hardware mute is cleared by set()).
        if delta > 0 { preMuteVolume = nil }
        let current = SystemVolume.get() ?? 0
        let next = max(0, min(1, current + delta))
        SystemVolume.set(next)
        refreshIcon()
    }

    private func toggleMute() {
        if SystemVolume.muteIsSupported() {
            SystemVolume.setMuted(!SystemVolume.isMuted())
        } else if let saved = preMuteVolume {
            SystemVolume.set(saved)          // restore the level captured when muting
            preMuteVolume = nil
        } else {
            preMuteVolume = SystemVolume.get() ?? 0   // no hardware mute: remember and zero
            SystemVolume.set(0)
        }
        refreshIcon()
    }

    private func refreshIcon() {
        // The icon stays the brand glyph; dim it to signal mute or full silence.
        let volume = SystemVolume.get() ?? 1
        let muted = SystemVolume.isMuted() || preMuteVolume != nil || volume <= 0.001
        statusItem.button?.alphaValue = muted ? 0.4 : 1.0
    }

    // MARK: Permissions

    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
        VolumeScroll needs Accessibility access to watch scroll events over the menu bar.

        Open System Settings ▸ Privacy & Security ▸ Accessibility, enable VolumeScroll, \
        then quit and relaunch the app.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        // Also fire the native trust prompt.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // agent app: no Dock icon, no main window
app.run()
