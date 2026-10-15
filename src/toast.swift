import AppKit
import QuartzCore

// Pill-shaped HUD toast at the bottom center of the screen under the mouse.
//   toast --pane ID --status blocked|done [--color RRGGBB] [--duration SEC] [--click true|false]
//   toast --title TEXT [--subtitle TEXT] [--color RRGGBB] [--duration SEC] [--pane ID]
// With --pane, looks up the agent and workspace names through the herdr CLI,
// and clicking the toast body focuses that pane. Both body clicks and X acknowledge the glow.

var paneID = ""
var status = ""
var colorHex = "FF8A1F"
var duration = 4.0
var fixedTitle: String?
var clickable = true
var fixedSubtitle = ""

var args = Array(CommandLine.arguments.dropFirst())
while args.count >= 2 {
    let flag = args.removeFirst()
    let value = args.removeFirst()
    switch flag {
    case "--pane": paneID = value
    case "--status": status = value
    case "--color": colorHex = value
    case "--duration": duration = Double(value) ?? duration
    case "--click": clickable = value != "false"
    case "--title": fixedTitle = value
    case "--subtitle": fixedSubtitle = value
    default: break
    }
}

func parseColor(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
    return NSColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

/// Runs `herdr <args>` and returns its `result` object.
func herdr(_ args: [String]) -> [String: Any]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["herdr"] + args
    var env = ProcessInfo.processInfo.environment
    let home = NSHomeDirectory()
    env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return json?["result"] as? [String: Any]
}

// Herdr's focus API switches panes inside the TUI. Activating its host terminal
// is a separate macOS operation, needed when the toast is clicked from another app.
func terminalBundleIdentifiers(_ environment: [String: String]) -> [String] {
    var identifiers: [String] = []
    if let identifier = environment["TERM_PROGRAM_BUNDLE_IDENTIFIER"], !identifier.isEmpty {
        identifiers.append(identifier)
    }
    // Resolve the enclosing bundle rather than assuming a WezTerm-based terminal's name.
    for key in ["WEZTERM_EXECUTABLE", "GHOSTTY_RESOURCES_DIR"] {
        guard let path = environment[key], !path.isEmpty else { continue }
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" {
                if let identifier = Bundle(url: url)?.bundleIdentifier { identifiers.append(identifier) }
                break
            }
            url.deleteLastPathComponent()
        }
    }
    if let identifier = environment["__CFBundleIdentifier"], !identifier.isEmpty {
        identifiers.append(identifier)
    }
    return identifiers
}

func hostTerminalApplication(_ environment: [String: String]) -> NSRunningApplication? {
    for identifier in terminalBundleIdentifiers(environment) {
        if let application = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.activationPolicy == .regular }) {
            return application
        }
    }
    // TERM_PROGRAM may be "herdr" inside panes; only match a named, running GUI app.
    guard let program = environment["TERM_PROGRAM"], !program.isEmpty, program.lowercased() != "herdr" else { return nil }
    let name = program == "Apple_Terminal" ? "Terminal" : program.replacingOccurrences(of: ".app", with: "")
    return NSWorkspace.shared.runningApplications.first {
        $0.activationPolicy == .regular && $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
    }
}

@discardableResult
func activateHostTerminal() -> Bool {
    guard let terminal = hostTerminalApplication(ProcessInfo.processInfo.environment) else { return false }
    terminal.unhide()
    if #available(macOS 14.0, *) {
        NSApp.yieldActivation(to: terminal)
        return terminal.activate(from: .current, options: [])
    }
    return terminal.activate(options: [.activateIgnoringOtherApps])
}

func acknowledgeGlow() {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("devookim.herdr-glow.acknowledge"), object: nil,
        userInfo: nil, deliverImmediately: true
    )
}

let agent = fixedTitle == nil ? herdr(["agent", "get", paneID])?["agent"] as? [String: Any] : nil
let workspaceID = agent?["workspace_id"] as? String
let workspace = workspaceID.flatMap { herdr(["workspace", "get", $0])?["workspace"] as? [String: Any] }

let agentName = (agent?["agent"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Agent"
let workspaceName = workspace?["label"] as? String
let verb: String
switch status {
case "blocked": verb = "needs your input"
case "done": verb = "is done"
case "working": verb = "is working"
case "idle": verb = "is idle"
default: verb = status
}
let title = fixedTitle ?? workspaceName.map { "\($0) · \(agentName)" } ?? agentName
let subtitle = fixedTitle == nil ? verb : fixedSubtitle

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
let subFont = NSFont.systemFont(ofSize: 15, weight: .regular)
// Separate labels so a long title truncates in the middle while the status stays whole.
let label = NSTextField(labelWithString: title)
label.font = font
label.textColor = .white
label.lineBreakMode = .byTruncatingMiddle
let statusLabel = NSTextField(labelWithString: subtitle)
statusLabel.font = subFont
statusLabel.textColor = NSColor.white.withAlphaComponent(0.7)
let dotSize: CGFloat = 12
let height: CGFloat = 52
let padding: CGFloat = 22
let gap: CGFloat = 12
let closeSize: CGFloat = 24
let mouse = NSEvent.mouseLocation
let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
let maxLabel = screen.visibleFrame.width * 0.6
// intrinsicContentSize runs a few points short and clips the last word, so add slack.
let statusWidth = ceil(statusLabel.intrinsicContentSize.width) + 4
let labelWidth = min(ceil(label.intrinsicContentSize.width) + 4, maxLabel - statusWidth)
let width = padding + dotSize + gap + labelWidth + gap / 2 + statusWidth + gap + closeSize + padding
let vf = screen.visibleFrame
let frame = NSRect(x: vf.midX - width / 2, y: vf.minY + 48, width: width, height: height)

/// Clicking the pill runs `onClick` without activating this app.
final class ClickableBlur: NSVisualEffectView {
    var onClick: (() -> Void)?
    var closeButton: NSButton?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    // Route labels and decorative views to the body action, while keeping X independent.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let button = closeButton, hit === button || hit.isDescendant(of: button) { return hit }
        return self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard onClick != nil || closeButton != nil else { return }
        // activeAlways: this accessory app is never frontmost, so the default would never fire.
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }
    private func updateCursor() {
        guard let window = window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if onClick != nil || closeButton?.frame.contains(point) == true { NSCursor.pointingHand.set() }
        else { NSCursor.arrow.set() }
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseEntered(with event: NSEvent) { updateCursor() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

/// Accept the first click even though the toast never activates its app.
final class ToastCloseButton: NSButton {
    var onClose: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    @objc func closeToast(_ sender: Any?) { onClose?() }
}

let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
w.level = .statusBar
w.isOpaque = false
w.backgroundColor = .clear
w.hasShadow = true
// Every toast has a close button, even when body navigation is disabled.
w.ignoresMouseEvents = false
w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

let blur = ClickableBlur(frame: NSRect(origin: .zero, size: frame.size))
blur.material = .hudWindow
blur.appearance = NSAppearance(named: .vibrantDark)
blur.blendingMode = .behindWindow
blur.state = .active
// The blur samples a rectangle behind the window; clipping the layer alone leaves its corners faintly
// visible, so mask the effect itself.
blur.maskImage = NSImage(size: frame.size, flipped: false) { rect in
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
    return true
}
blur.wantsLayer = true
blur.layer?.cornerRadius = height / 2
blur.layer?.masksToBounds = true
blur.layer?.borderWidth = 1
blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

let color = parseColor(colorHex)
let dot = NSView(frame: NSRect(x: padding, y: (height - dotSize) / 2, width: dotSize, height: dotSize))
dot.wantsLayer = true
dot.layer?.backgroundColor = color.cgColor
dot.layer?.cornerRadius = dotSize / 2
dot.layer?.shadowColor = color.cgColor
dot.layer?.shadowOpacity = 0.9
dot.layer?.shadowRadius = 6
dot.layer?.shadowOffset = .zero
dot.layer?.masksToBounds = false
blur.addSubview(dot)

// Fill the rim clockwise from the top center over the toast's visible lifetime.
let rimWidth: CGFloat = 3
let rim = CAShapeLayer()
rim.frame = NSRect(origin: .zero, size: frame.size)
let rimRect = rim.bounds.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)
let rimRadius = rimRect.height / 2
let ringPath = CGMutablePath()
ringPath.move(to: CGPoint(x: rimRect.midX, y: rimRect.maxY))
ringPath.addLine(to: CGPoint(x: rimRect.maxX - rimRadius, y: rimRect.maxY))
ringPath.addArc(center: CGPoint(x: rimRect.maxX - rimRadius, y: rimRect.midY), radius: rimRadius,
                startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
ringPath.addLine(to: CGPoint(x: rimRect.minX + rimRadius, y: rimRect.minY))
ringPath.addArc(center: CGPoint(x: rimRect.minX + rimRadius, y: rimRect.midY), radius: rimRadius,
                startAngle: -.pi / 2, endAngle: -3 * .pi / 2, clockwise: true)
ringPath.closeSubpath()
rim.path = ringPath
rim.fillColor = nil
rim.strokeColor = color.cgColor
rim.lineWidth = rimWidth
rim.lineCap = .round
rim.strokeEnd = 0
rim.opacity = 0.75
blur.layer?.addSublayer(rim)

let labelHeight = ceil(label.intrinsicContentSize.height)
label.frame = NSRect(x: padding + dotSize + gap, y: (height - labelHeight) / 2, width: labelWidth, height: labelHeight)
blur.addSubview(label)
statusLabel.frame = NSRect(x: label.frame.maxX + gap / 2, y: label.frame.minY, width: statusWidth, height: labelHeight)
blur.addSubview(statusLabel)

let closeTitle = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "닫기" : "Close"
let closeButton = ToastCloseButton(frame: NSRect(x: statusLabel.frame.maxX + gap,
                                               y: (height - closeSize) / 2, width: closeSize, height: closeSize))
closeButton.title = ""
closeButton.isBordered = false
closeButton.imagePosition = .imageOnly
closeButton.focusRingType = .none
closeButton.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 2, y: 2))
    path.line(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
    path.move(to: CGPoint(x: 2, y: rect.maxY - 2))
    path.line(to: CGPoint(x: rect.maxX - 2, y: 2))
    path.lineWidth = 1.6
    path.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.85).setStroke()
    path.stroke()
    return true
}
closeButton.toolTip = closeTitle
closeButton.setAccessibilityLabel(closeTitle)
closeButton.target = closeButton
closeButton.action = #selector(ToastCloseButton.closeToast(_:))
closeButton.onClose = {
    guard !dismissing else { return }
    acknowledgeGlow()
    dismiss()
}
closeButton.wantsLayer = true
closeButton.layer?.cornerRadius = closeSize / 2
blur.addSubview(closeButton)
blur.closeButton = closeButton

w.contentView = blur
var hovering = false
if !paneID.isEmpty && clickable {
    blur.onClick = {
        guard !dismissing, herdr(["agent", "focus", paneID]) != nil else { return }
        acknowledgeGlow()
        activateHostTerminal()
        dismiss()
    }
}
// Hovering anywhere, including X, pauses the gauge and timer on every toast.
// Poll because the accessory app does not receive mouse-moved events while inactive.
Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
    guard !dismissing else { return }
    updateHover(NSMouseInRect(NSEvent.mouseLocation, w.frame, false))
    let point = blur.convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(closeButton.frame.contains(point) ? 0.18 : 0).cgColor
}
blur.updateTrackingAreas()
w.alphaValue = 0
w.orderFrontRegardless()
w.invalidateShadow()

func fade(to alpha: CGFloat) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        w.animator().alphaValue = alpha
    }
}

// Use one monotonic countdown for the gauge and dismissal, including hover pauses.
var dismissTimer: DispatchWorkItem?
var remainingDuration = duration.isFinite ? max(0, duration) : 4
var progress: CGFloat = 0
var segmentStarted: CFTimeInterval?
var dismissing = false

func updateHover(_ inside: Bool) {
    guard !dismissing, inside != hovering else { return }
    hovering = inside
    blur.layer?.borderColor = NSColor.white.withAlphaComponent(inside ? 0.6 : 0.15).cgColor
    rim.opacity = inside ? 1 : 0.75
    if inside { pauseCountdown() } else { resumeCountdown() }
}

func setProgress(_ value: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rim.strokeEnd = value
    CATransaction.commit()
}

func pauseCountdown() {
    dismissTimer?.cancel()
    dismissTimer = nil
    guard let start = segmentStarted else { return }
    let elapsed = min(max(0, CACurrentMediaTime() - start), remainingDuration)
    if remainingDuration > 0 {
        progress += (1 - progress) * CGFloat(elapsed / remainingDuration)
    }
    remainingDuration -= elapsed
    segmentStarted = nil
    setProgress(progress)
    rim.removeAnimation(forKey: "countdown")
}

func resumeCountdown() {
    guard !dismissing, segmentStarted == nil else { return }
    guard remainingDuration > 0 else {
        progress = 1
        setProgress(1)
        dismiss()
        return
    }
    segmentStarted = CACurrentMediaTime()
    setProgress(1)
    let fill = CABasicAnimation(keyPath: "strokeEnd")
    fill.fromValue = progress
    fill.toValue = 1
    fill.duration = remainingDuration
    fill.timingFunction = CAMediaTimingFunction(name: .linear)
    // Anchor the animation to the same clock as the expiry timer.
    fill.beginTime = rim.convertTime(segmentStarted!, from: nil)
    rim.add(fill, forKey: "countdown")

    let item = DispatchWorkItem {
        // Also check at expiry so entering just before the next hover poll keeps it open.
        if !w.ignoresMouseEvents && NSMouseInRect(NSEvent.mouseLocation, w.frame, false) {
            updateHover(true)
            return
        }
        segmentStarted = nil
        remainingDuration = 0
        progress = 1
        setProgress(1)
        rim.removeAnimation(forKey: "countdown")
        dismiss()
    }
    dismissTimer = item
    DispatchQueue.main.asyncAfter(deadline: .now() + remainingDuration, execute: item)
}

// The animation's completion handler doesn't always fire, so quit on a timer instead.
func dismiss() {
    guard !dismissing else { return }
    dismissing = true
    pauseCountdown()
    fade(to: 0)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
}

fade(to: 1)
resumeCountdown()

var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { dismiss() }
    src.resume()
    sources.append(src)
}
app.run()
