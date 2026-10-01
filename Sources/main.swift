// Claude Traffic Light — a floating macOS widget that shows what Claude Code is doing,
// styled like the built-in desktop widgets (translucent material, rounded corners).
//
//   🔴 Ready        Claude is idle and waiting for you
//   🟡 Thinking…    Claude is working (thinking / running tools / processing)
//   🟢 Done         Claude just finished — stays green for 10 s, then back to red (and a sound plays)
//
// A very faint Claude starburst is drawn behind everything as a watermark.
//
// The footer ("Last Run") shows the last run the way Claude's app does: "4m 44s · 4.6k tokens".
// After 10 minutes without any Claude activity the widget dims ("sleep"); hovering wakes it.
//
// State comes from ~/.claude/traffic-light/sessions/<session>.json, written by the
// Claude Code hook script (claude-status-hook.sh). One file per Claude Code session.

import Cocoa
import ServiceManagement

// MARK: - Model

enum Light: CaseIterable, Equatable {
    case red, yellow, green

    var color: NSColor {
        switch self {
        case .red:    return NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        }
    }

    var defaultLabel: String {
        switch self {
        case .red:    return "Ready"
        case .yellow: return "Thinking…"
        case .green:  return "Done"
        }
    }
}

struct RunStats: Equatable {
    var context: Int    // tokens in the context window after the run — what Claude Code shows as "tokens used"
    var delta: Int      // change in context tokens during the run
    var output: Int     // output tokens generated during the run
    var model: String
    var seconds: Int
    var finished: Date

    /// Context window size for the model, when known (Claude 5 family and [1m] models: 1M; Claude 4: 200k).
    var windowSize: Int? {
        let m = model.lowercased()
        if m.contains("[1m]") || m.contains("fable") || m.contains("mythos") { return 1_000_000 }
        if m.range(of: #"-5(-|$|\.)"#, options: .regularExpression) != nil { return 1_000_000 }
        if m.range(of: #"-4(-|$|\.)"#, options: .regularExpression) != nil { return 200_000 }
        return nil
    }
}

struct Resolved: Equatable {
    var light: Light
    var label: String
    var tokens: RunStats?
}

struct SessionFile {
    let status: String      // "ready" | "working" | "done"
    let label: String
    let modified: Date
    let pid: pid_t?
    let tokens: RunStats?
}

enum Format {
    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000:     return "\(n)"
        case ..<10_000:    return String(format: "%.1fk", Double(n) / 1_000)
        case ..<1_000_000: return String(format: "%.0fk", Double(n) / 1_000)
        default:           return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }

    static func duration(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    static func window(_ n: Int) -> String {
        if n % 1_000_000 == 0 { return "\(n / 1_000_000)M" }
        if n % 1_000 == 0 { return "\(n / 1_000)k" }
        return tokens(n)
    }

    /// Longest-first list of footer texts; the view picks the first one that fits.
    ///   "4m 44s · 4.6k tokens"  (duration of the run · output tokens, like Claude's own run summary)
    static func footerCandidates(_ r: RunStats?) -> [String] {
        guard let r = r else { return ["—"] }
        let out = "\(tokens(r.output)) tokens"
        if r.seconds > 0 { return ["\(duration(r.seconds)) · \(out)", out] }
        return [out]
    }

    /// "329k / 1M (33%)" — context window usage after the run (shown in the menu).
    static func contextSummary(_ r: RunStats?) -> String {
        guard let r = r else { return "—" }
        guard let w = r.windowSize, w > 0 else { return tokens(r.context) }
        let pct = Int((Double(r.context) / Double(w) * 100).rounded())
        return "\(tokens(r.context)) / \(window(w)) (\(pct)%)"
    }
}

final class StateStore {
    /// Green stays this long after a Stop event, then the light goes back to red.
    static let doneHoldSeconds: TimeInterval = 10
    /// A "working" file older than this is ignored (session probably died without SessionEnd).
    static let workingStaleSeconds: TimeInterval = 15 * 60
    /// Session files older than this are deleted.
    static let purgeAfterSeconds: TimeInterval = 24 * 3600

    let directory: URL
    /// Newest modification time among the session files (any hook event), for the sleep mode.
    private(set) var lastActivity: Date?

    init() {
        directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("traffic-light", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Aggregates all sessions: working beats done, done (within 10 s) beats ready.
    /// "Last Run" figures come from the most recently finished run in any session.
    func resolve(now: Date = Date()) -> Resolved {
        let files = load(now: now)
        let tokens = files.compactMap { $0.tokens }.max(by: { $0.finished < $1.finished })

        let working = files.filter {
            $0.status == "working"
                && now.timeIntervalSince($0.modified) < Self.workingStaleSeconds
                && isAlive($0.pid)
        }
        if let w = working.max(by: { $0.modified < $1.modified }) {
            return Resolved(light: .yellow, label: w.label.isEmpty ? Light.yellow.defaultLabel : w.label, tokens: tokens)
        }

        let done = files.filter {
            $0.status == "done" && now.timeIntervalSince($0.modified) < Self.doneHoldSeconds
        }
        if let d = done.max(by: { $0.modified < $1.modified }) {
            return Resolved(light: .green, label: d.label.isEmpty ? Light.green.defaultLabel : d.label, tokens: tokens)
        }

        let ready = files.filter { $0.status == "ready" && isAlive($0.pid) }
        if let r = ready.max(by: { $0.modified < $1.modified }), !r.label.isEmpty {
            return Resolved(light: .red, label: r.label, tokens: tokens)
        }
        return Resolved(light: .red, label: Light.red.defaultLabel, tokens: tokens)
    }

    private func load(now: Date) -> [SessionFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [SessionFile] = []
        var newest: Date? = nil
        for url in urls where url.pathExtension == "json" {
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > Self.purgeAfterSeconds {
                try? fm.removeItem(at: url)
                continue
            }
            if newest == nil || modified > newest! { newest = modified }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = obj["status"] as? String else { continue }
            let label = obj["label"] as? String ?? ""
            let pid = (obj["pid"] as? NSNumber).map { pid_t($0.int32Value) }

            var tokens: RunStats? = nil
            if let t = obj["tokens"] as? [String: Any], let ctx = (t["ctx"] as? NSNumber)?.intValue {
                let finished = (obj["turn_done_ts"] as? NSNumber)
                    .map { Date(timeIntervalSince1970: $0.doubleValue) } ?? modified
                tokens = RunStats(context: ctx,
                                  delta: (t["delta"] as? NSNumber)?.intValue ?? ctx,
                                  output: (t["out"] as? NSNumber)?.intValue ?? 0,
                                  model: t["model"] as? String ?? "",
                                  seconds: (t["seconds"] as? NSNumber)?.intValue ?? 0,
                                  finished: finished)
            }
            result.append(SessionFile(status: status, label: label, modified: modified, pid: pid, tokens: tokens))
        }
        lastActivity = newest
        return result
    }

    /// Unknown pid → assume alive. Known pid → check with kill(pid, 0).
    private func isAlive(_ pid: pid_t?) -> Bool {
        guard let pid = pid, pid > 1 else { return true }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

// MARK: - View

final class TrafficLightView: NSView {
    // Roughly the size of a "medium" macOS desktop widget.
    static let size = NSSize(width: 340, height: 158)
    static let cornerRadius: CGFloat = 22
    static let lightDiameter: CGFloat = 86
    static let sidePadding: CGFloat = 22
    static let topPadding: CGFloat = 20
    /// Opacity of the Claude starburst watermark behind the lights (idle / while working).
    static let logoAlpha: CGFloat = 0.10
    static let logoAlphaWorking: CGFloat = 0.18

    var resolved = Resolved(light: .red, label: Light.red.defaultLabel, tokens: nil) { didSet { needsDisplay = true } }
    var pulsePhase: Double = 0 { didSet { needsDisplay = true } }
    /// Preview mode only: paint an opaque stand-in for the blur material.
    var drawsBackdrop = false
    var contextMenuProvider: (() -> NSMenu)?
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let frame = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)

        if drawsBackdrop {
            NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 0.92).setFill()
            frame.fill()
        }

        // Watermark, clipped to the card
        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        drawLogo(in: b)
        NSGraphicsContext.restoreGraphicsState()

        // Hairline edge, like the system widgets
        NSColor(white: 1, alpha: 0.12).setStroke()
        frame.lineWidth = 1
        frame.stroke()

        // Lights: red · yellow · green, each with its caption inside
        let d = Self.lightDiameter
        let gap = (b.width - 2 * Self.sidePadding - 3 * d) / 2
        let y = b.height - Self.topPadding - d
        for (i, light) in Light.allCases.enumerated() {
            let x = Self.sidePadding + CGFloat(i) * (d + gap)
            let active = light == resolved.light
            drawLight(light, in: NSRect(x: x, y: y, width: d, height: d),
                      active: active, label: active ? resolved.label : light.defaultLabel)
        }

        // Footer: "Last Run" token figures
        drawFooter(in: b, lightsBottom: y)
    }

    /// The Claude starburst: 12 tapered rays of slightly uneven length, drawn as one path
    /// so the low alpha stays uniform where rays meet. It takes the colour of the active light,
    /// and while Claude works it breathes and slowly spins, like the logo in Claude's app.
    private func drawLogo(in b: NSRect) {
        let center = NSPoint(x: b.midX, y: b.midY)
        let working = resolved.light == .yellow
        let breath = working ? CGFloat(sin(pulsePhase * 0.7)) : 0
        let radius = b.height * 0.47 * (1 + 0.04 * breath)
        let spin: CGFloat = working ? CGFloat(pulsePhase) * 0.12 : 0
        let alpha = working ? Self.logoAlphaWorking : Self.logoAlpha
        let lengths: [CGFloat] = [1.00, 0.80, 0.94, 0.76, 1.00, 0.82, 0.90, 0.78, 0.97, 0.84, 0.92, 0.80]
        let jitter: [CGFloat]  = [0, 3, -2, 4, -3, 2, 0, -4, 3, -2, 2, -3]   // degrees

        let path = NSBezierPath()
        for i in 0..<12 {
            let angle = (CGFloat(i) * 30 + 12 + jitter[i]) * .pi / 180 + spin
            let dir = NSPoint(x: cos(angle), y: sin(angle))
            let perp = NSPoint(x: -dir.y, y: dir.x)
            var len = radius * lengths[i]
            if working { len *= 1 + 0.10 * CGFloat(sin(pulsePhase * 1.6 + Double(i) * 0.9)) }
            let innerR = radius * 0.05, innerHalf = radius * 0.022
            let outerHalf = radius * 0.072, bevel = radius * 0.07

            func pt(_ r: CGFloat, _ side: CGFloat) -> NSPoint {
                NSPoint(x: center.x + dir.x * r + perp.x * side, y: center.y + dir.y * r + perp.y * side)
            }
            path.move(to: pt(innerR, -innerHalf))
            path.line(to: pt(len - bevel, -outerHalf))
            path.line(to: pt(len, outerHalf * 0.9))
            path.line(to: pt(innerR, innerHalf))
            path.close()
        }
        path.windingRule = .nonZero
        resolved.light.color.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    private func drawLight(_ light: Light, in rect: NSRect, active: Bool, label: String) {
        let color = light.color
        let oval = NSBezierPath(ovalIn: rect)

        if active {
            // Yellow pulses while Claude works; red and green are steady.
            let intensity: CGFloat = light == .yellow ? CGFloat(0.72 + 0.28 * sin(pulsePhase)) : 1.0

            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = color.withAlphaComponent(0.85 * intensity)
            glow.shadowBlurRadius = 18
            glow.shadowOffset = .zero
            glow.set()
            color.withAlphaComponent(0.40 + 0.60 * intensity).setFill()
            oval.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Soft highlight towards the top
            let highlightRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
                .offsetBy(dx: 0, dy: rect.height * 0.16)
            if let gradient = NSGradient(starting: NSColor(white: 1, alpha: 0.40 * intensity),
                                         ending: NSColor(white: 1, alpha: 0)) {
                gradient.draw(in: NSBezierPath(ovalIn: highlightRect), relativeCenterPosition: .zero)
            }

            let textColor = light == .red ? NSColor.white : NSColor(white: 0.08, alpha: 0.88)
            drawCentered(label, in: rect, maxWidth: rect.width - 16, baseSize: 15, weight: .bold, color: textColor)
        } else {
            color.withAlphaComponent(0.14).setFill()
            oval.fill()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            color.withAlphaComponent(0.35).setStroke()
            ring.stroke()

            drawCentered(label, in: rect, maxWidth: rect.width - 16, baseSize: 14, weight: .semibold,
                         color: color.withAlphaComponent(0.72))
        }
    }

    /// Draws `string` centered in `rect`, shrinking the font until it fits `maxWidth`.
    private func drawCentered(_ string: String, in rect: NSRect, maxWidth: CGFloat,
                              baseSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
        var size = baseSize
        var text = NSAttributedString()
        while true {
            text = NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
            ])
            if text.size().width <= maxWidth || size <= 9 { break }
            size -= 0.5
        }
        let s = text.size()
        text.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
    }

    private func drawFooter(in b: NSRect, lightsBottom: CGFloat) {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let caption = NSAttributedString(string: "Last Run", attributes: [
            .font: font, .foregroundColor: NSColor(white: 1, alpha: 0.50),
        ])
        let available = b.width - 2 * Self.sidePadding - caption.size().width - 12

        var value = NSAttributedString()
        for candidate in Format.footerCandidates(resolved.tokens) {
            value = NSAttributedString(string: candidate, attributes: [
                .font: font, .foregroundColor: NSColor(white: 1, alpha: 0.88),
            ])
            if value.size().width <= available { break }
        }

        let centerY = lightsBottom / 2
        caption.draw(at: NSPoint(x: Self.sidePadding, y: centerY - caption.size().height / 2))
        value.draw(at: NSPoint(x: b.width - Self.sidePadding - value.size().width,
                               y: centerY - value.size().height / 2))
    }
}

// MARK: - App

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/traffic-light/widget.log")
    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 256_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// No Claude activity for this long → the widget dims.
    static let sleepAfterSeconds: TimeInterval = 10 * 60
    static let sleepAlpha: CGFloat = 0.35

    private let store = StateStore()
    private var panel: NSPanel!
    private var lightView: TrafficLightView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var current = Resolved(light: .red, label: Light.red.defaultLabel, tokens: nil)

    private let originKey = "widgetOrigin"
    private let hiddenKey = "widgetHidden"
    private let soundKey = "doneSound"
    private let defaultSound = "Glass"
    private var hasTicked = false
    private var lastSoundAt = Date.distantPast
    private var currentSound: NSSound?      // keeps the sound alive while it plays
    private let launchedAt = Date()
    private var isHovering = false
    private var isDimmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildStatusItem()
        if !UserDefaults.standard.bool(forKey: hiddenKey) {
            panel.orderFrontRegardless()
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: Panel

    private func buildPanel() {
        let size = TrafficLightView.size
        let origin = savedOrigin(for: size) ?? defaultOrigin(for: size)

        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.appearance = NSAppearance(named: .darkAqua)

        // Translucent "widget" material with rounded corners
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = TrafficLightView.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let view = TrafficLightView(frame: effect.bounds)
        view.autoresizingMask = [.width, .height]
        view.onHoverChange = { [weak self] hovering in
            self?.isHovering = hovering
            self?.updateSleep(force: true)
        }
        view.contextMenuProvider = { [weak self] in
            let menu = NSMenu()
            self?.populate(menu)
            return menu
        }
        effect.addSubview(view)
        p.contentView = effect

        lightView = view
        panel = p

        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: p)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12)
    }

    /// Saved origin, nudged back on-screen if the widget grew or the display changed.
    private func savedOrigin(for size: NSSize) -> NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: originKey) as? [Double], arr.count == 2 else {
            return nil
        }
        var rect = NSRect(x: arr[0], y: arr[1], width: size.width, height: size.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else { return nil }
        let v = screen.visibleFrame
        rect.origin.x = min(max(rect.origin.x, v.minX), v.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, v.minY), v.maxY - rect.height)
        return rect.origin
    }

    @objc private func panelMoved() {
        let o = panel.frame.origin
        UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: originKey)
    }

    // MARK: Status bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func updateStatusIcon() {
        let color = current.light.color
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            return true
        }
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Claude: \(current.label)"
    }

    // MARK: Menu

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        info("Claude Traffic Light")
        info("Status: \(current.label)" + (isDimmed ? " (sleeping)" : ""))
        info("Last Run: \(Format.footerCandidates(current.tokens).first ?? "—")")
        info("Context: \(Format.contextSummary(current.tokens))")
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: panel.isVisible ? "Hide Widget" : "Show Widget",
                                action: #selector(toggleWidget), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let soundItem = NSMenuItem(title: "Done Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = makeSoundMenu()
        menu.addItem(soundItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Sound

    private var chosenSound: String {
        UserDefaults.standard.string(forKey: soundKey) ?? defaultSound
    }

    /// Names of the system sounds in /System/Library/Sounds (Glass, Pop, Hero, …).
    private func systemSounds() -> [String] {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    private func makeSoundMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ name: String) {
            let item = NSMenuItem(title: name, action: #selector(chooseSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == chosenSound ? .on : .off
            menu.addItem(item)
        }
        add("Off")
        add("System Alert")
        menu.addItem(.separator())
        systemSounds().forEach(add)
        return menu
    }

    @objc private func chooseSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        UserDefaults.standard.set(name, forKey: soundKey)
        lastSoundAt = .distantPast
        playDoneSound()   // preview the choice
    }

    private func playDoneSound() {
        let name = chosenSound
        guard name != "Off" else { return }
        guard Date().timeIntervalSince(lastSoundAt) > 1.5 else { return }
        lastSoundAt = Date()
        if name == "System Alert" {
            NSSound.beep()
            Log.write("sound: system alert")
        } else if let sound = NSSound(named: NSSound.Name(name)) {
            currentSound?.stop()
            currentSound = sound          // NSSound stops if it is deallocated mid-play
            let ok = sound.play()
            Log.write("sound: \(name) play=\(ok)")
        } else {
            Log.write("sound: \(name) not found")
        }
    }

    // MARK: Sleep

    /// Dims the widget after 10 minutes without Claude activity; hovering or any event wakes it.
    private func updateSleep(force: Bool = false) {
        let lastActivity = max(store.lastActivity ?? .distantPast, launchedAt)
        let idle = Date().timeIntervalSince(lastActivity) > Self.sleepAfterSeconds
        let shouldDim = idle && current.light == .red && !isHovering
        guard force || shouldDim != isDimmed else { return }
        isDimmed = shouldDim
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            panel.animator().alphaValue = shouldDim ? Self.sleepAlpha : 1.0
        }
    }

    @objc private func toggleWidget() {
        if panel.isVisible {
            panel.orderOut(nil)
            UserDefaults.standard.set(true, forKey: hiddenKey)
        } else {
            panel.orderFrontRegardless()
            UserDefaults.standard.set(false, forKey: hiddenKey)
        }
    }

    @objc private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: originKey)
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        panel.orderFrontRegardless()
        UserDefaults.standard.set(false, forKey: hiddenKey)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change “Launch at Login”"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Tick

    private func tick() {
        let resolved = store.resolve()
        if resolved != current {
            // A run just finished: play the notification sound (not on the very first tick after launch)
            if hasTicked && resolved.light == .green && current.light != .green {
                playDoneSound()
            }
            if resolved.light != current.light { Log.write("state: \(resolved.light) \(resolved.label)") }
            current = resolved
            lightView.resolved = resolved
            updateStatusIcon()
        }
        hasTicked = true
        updateSleep()
        if resolved.light == .yellow {
            // 0.05 s tick → ~0.8 Hz pulse
            lightView.pulsePhase += 0.05 * 2 * Double.pi * 0.8
        }
    }
}

// MARK: - CLI helpers
//
//   ClaudeTrafficLight --preview out.png   renders the three states to a PNG (for docs / verification)
//   ClaudeTrafficLight --status            prints the state the widget would show right now

func renderPreview(to path: String) -> Bool {
    let scale: CGFloat = 2
    let size = TrafficLightView.size
    let sample = RunStats(context: 302_596, delta: 61_500, output: 4_600, model: "claude-fable-5-1", seconds: 284, finished: Date())
    let states: [Resolved] = [
        Resolved(light: .red, label: Light.red.defaultLabel, tokens: sample),
        Resolved(light: .yellow, label: Light.yellow.defaultLabel, tokens: sample),
        Resolved(light: .green, label: Light.green.defaultLabel, tokens: sample),
    ]
    let pad: CGFloat = 20
    let total = NSSize(width: size.width + pad * 2,
                       height: CGFloat(states.count) * (size.height + pad) + pad)

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(total.width * scale),
                                     pixelsHigh: Int(total.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
    rep.size = total

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    // Wallpaper-ish backdrop so the translucent stand-in reads correctly
    if let bg = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.33, blue: 0.56, alpha: 1),
                           ending: NSColor(srgbRed: 0.05, green: 0.10, blue: 0.22, alpha: 1)) {
        bg.draw(in: NSRect(origin: .zero, size: total), angle: -70)
    }
    for (i, state) in states.enumerated() {
        let view = TrafficLightView(frame: NSRect(origin: .zero, size: size))
        view.drawsBackdrop = true
        view.resolved = state
        view.pulsePhase = .pi / 2
        let y = total.height - pad - CGFloat(i + 1) * size.height - CGFloat(i) * pad
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: pad, yBy: y)
        t.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--preview"), i + 1 < arguments.count {
    exit(renderPreview(to: arguments[i + 1]) ? 0 : 1)
}
if arguments.contains("--status") {
    let r = StateStore().resolve()
    print("\(r.light) \(r.label) | Last Run: \(Format.footerCandidates(r.tokens).first ?? "—") | Context: \(Format.contextSummary(r.tokens))")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
