import AppKit

// Pill-shaped HUD toast at the bottom center of the screen under the mouse.
//   toast --pane ID --status blocked|done [--color RRGGBB] [--duration SEC]
// Looks up the agent and workspace names through the herdr CLI.

var paneID = ""
var status = ""
var colorHex = "FF8A1F"
var duration = 4.0

var args = Array(CommandLine.arguments.dropFirst())
while args.count >= 2 {
    let flag = args.removeFirst()
    let value = args.removeFirst()
    switch flag {
    case "--pane": paneID = value
    case "--status": status = value
    case "--color": colorHex = value
    case "--duration": duration = Double(value) ?? duration
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

let agent = herdr(["agent", "get", paneID])?["agent"] as? [String: Any]
let workspaceID = agent?["workspace_id"] as? String
let workspace = workspaceID.flatMap { herdr(["workspace", "get", $0])?["workspace"] as? [String: Any] }

let agentName = (agent?["agent"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Agent"
let workspaceName = workspace?["label"] as? String
let verb = status == "blocked" ? "needs your input" : "is done"
let title = workspaceName.map { "\($0) · \(agentName)" } ?? agentName
let subtitle = verb

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
let subFont = NSFont.systemFont(ofSize: 15, weight: .regular)
let text = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.white])
text.append(NSAttributedString(string: "  \(subtitle)", attributes: [.font: subFont, .foregroundColor: NSColor.white.withAlphaComponent(0.7)]))

let label = NSTextField(labelWithAttributedString: text)
label.lineBreakMode = .byTruncatingMiddle
let dotSize: CGFloat = 12
let height: CGFloat = 52
let padding: CGFloat = 22
let gap: CGFloat = 12
let mouse = NSEvent.mouseLocation
let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
let maxLabel = screen.visibleFrame.width * 0.6
let labelWidth = min(ceil(label.intrinsicContentSize.width), maxLabel)
let width = padding + dotSize + gap + labelWidth + padding
let vf = screen.visibleFrame
let frame = NSRect(x: vf.midX - width / 2, y: vf.minY + 48, width: width, height: height)

let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
w.level = .statusBar
w.isOpaque = false
w.backgroundColor = .clear
w.hasShadow = true
w.ignoresMouseEvents = true
w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
blur.material = .hudWindow
blur.appearance = NSAppearance(named: .vibrantDark)
blur.blendingMode = .behindWindow
blur.state = .active
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

let labelHeight = ceil(label.intrinsicContentSize.height)
label.frame = NSRect(x: padding + dotSize + gap, y: (height - labelHeight) / 2, width: labelWidth, height: labelHeight)
blur.addSubview(label)

w.contentView = blur
w.alphaValue = 0
w.orderFrontRegardless()

func fade(to alpha: CGFloat) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        w.animator().alphaValue = alpha
    }
}

// The animation's completion handler doesn't always fire, so quit on a timer instead.
func dismiss() {
    fade(to: 0)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
}

fade(to: 1)
DispatchQueue.main.asyncAfter(deadline: .now() + duration) { dismiss() }

var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { dismiss() }
    src.resume()
    sources.append(src)
}
app.run()
