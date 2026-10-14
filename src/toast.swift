import AppKit
import QuartzCore

// Pill-shaped HUD toast at the bottom center of the screen under the mouse.
//   toast --pane ID --status blocked|done [--color RRGGBB] [--duration SEC] [--click true|false]
//   toast --title TEXT [--subtitle TEXT] [--color RRGGBB] [--duration SEC]
// With --pane, looks up the agent and workspace names through the herdr CLI,
// and clicking the toast focuses that pane.

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
let mouse = NSEvent.mouseLocation
let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
let maxLabel = screen.visibleFrame.width * 0.6
// intrinsicContentSize runs a few points short and clips the last word, so add slack.
let statusWidth = ceil(statusLabel.intrinsicContentSize.width) + 4
let labelWidth = min(ceil(label.intrinsicContentSize.width) + 4, maxLabel - statusWidth)
let width = padding + dotSize + gap + labelWidth + gap / 2 + statusWidth + padding
let vf = screen.visibleFrame
let frame = NSRect(x: vf.midX - width / 2, y: vf.minY + 48, width: width, height: height)

/// Clicking the pill runs `onClick` without activating this app.
final class ClickableBlur: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard onClick != nil else { return }
        // activeAlways: this accessory app is never frontmost, so the default would never fire.
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
w.level = .statusBar
w.isOpaque = false
w.backgroundColor = .clear
w.hasShadow = true
// Only toasts for a real pane are clickable; the rest stay click-through.
w.ignoresMouseEvents = fixedTitle != nil || !clickable
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

// A comet of the status color circling the rim. Stacked dashes of growing length share one head
// and fade out behind it; animating each dash phase moves them at a constant speed along the path
// (a rotating conic gradient would speed up on the straights and look like it stretches).
let rimWidth: CGFloat = 3
let rim = CALayer()
rim.frame = NSRect(origin: .zero, size: frame.size)
let rimRect = rim.bounds.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)
let rimRadius = rimRect.height / 2
let ringPath = CGPath(roundedRect: rimRect, cornerWidth: rimRadius, cornerHeight: rimRadius, transform: nil)
let perimeter = 2 * (rimRect.width - 2 * rimRadius) + 2 * CGFloat.pi * rimRadius
let tailLength = perimeter * 0.45
let tailSteps = 18
for i in 1...tailSteps {
    let length = tailLength * CGFloat(i) / CGFloat(tailSteps)
    let dash = CAShapeLayer()
    dash.frame = rim.bounds
    dash.path = ringPath
    dash.fillColor = nil
    dash.strokeColor = color.withAlphaComponent(0.12).cgColor
    dash.lineWidth = rimWidth
    dash.lineDashPattern = [NSNumber(value: Double(length)), NSNumber(value: Double(perimeter - length))]
    let spin = CABasicAnimation(keyPath: "lineDashPhase")
    spin.fromValue = 0
    spin.toValue = Double(perimeter)
    spin.duration = 2.4
    spin.repeatCount = .infinity
    dash.add(spin, forKey: "spin")
    rim.addSublayer(dash)
}
rim.opacity = 0.75
blur.layer?.addSublayer(rim)

let labelHeight = ceil(label.intrinsicContentSize.height)
label.frame = NSRect(x: padding + dotSize + gap, y: (height - labelHeight) / 2, width: labelWidth, height: labelHeight)
blur.addSubview(label)
statusLabel.frame = NSRect(x: label.frame.maxX + gap / 2, y: label.frame.minY, width: statusWidth, height: labelHeight)
blur.addSubview(statusLabel)

w.contentView = blur
if fixedTitle == nil && clickable {
    blur.onClick = {
        _ = herdr(["agent", "focus", paneID])
        dismiss()
    }
    // Hovering keeps the toast up and lights the rim; leaving gives a short grace period.
    // Polled rather than tracked: an accessory app never gets mouse-moved events while inactive.
    var hovering = false
    Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
        let inside = NSMouseInRect(NSEvent.mouseLocation, w.frame, false)
        guard inside != hovering else { return }
        hovering = inside
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(inside ? 0.6 : 0.15).cgColor
        rim.opacity = inside ? 1 : 0.75
        if inside { dismissTimer?.cancel() } else { scheduleDismiss(after: min(duration, 1.5)) }
    }
    blur.updateTrackingAreas()
}
w.alphaValue = 0
w.orderFrontRegardless()
w.invalidateShadow()

func fade(to alpha: CGFloat) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        w.animator().alphaValue = alpha
    }
}

// The animation's completion handler doesn't always fire, so quit on a timer instead.
func dismiss() {
    dismissTimer?.cancel()
    fade(to: 0)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
}

var dismissTimer: DispatchWorkItem?
func scheduleDismiss(after delay: Double) {
    dismissTimer?.cancel()
    let item = DispatchWorkItem { dismiss() }
    dismissTimer = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
}

fade(to: 1)
scheduleDismiss(after: duration)

var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { dismiss() }
    src.resume()
    sources.append(src)
}
app.run()
