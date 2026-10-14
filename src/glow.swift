import AppKit
import QuartzCore

// Ambient edge glow overlay.
//   glow [--color RRGGBB] [--width PT] [--duration SEC] [--screen active|all]
//   glow --watch [--idle SEC] [--intro SEC]
// --screen active  glow only on the display under the mouse when it lights up (default); all = every display.
// --duration SEC  one-shot pulse, then exit (0 = glow until SIGTERM).
// --watch         short intro pulse, then glow again whenever the user has been idle
//                 for --idle seconds; any input fades it out. Runs until SIGTERM/SIGINT.

var colorHex = "FF8A1F"
var duration = 3.0
var width: CGFloat = 140
var watch = false
var idleThreshold = 30.0
var intro = 5.6
var activeScreenOnly = true

var args = Array(CommandLine.arguments.dropFirst())
while let flag = args.first {
    args.removeFirst()
    if flag == "--watch" { watch = true; continue }
    guard let value = args.first else { break }
    args.removeFirst()
    switch flag {
    case "--color": colorHex = value
    case "--duration": duration = Double(value) ?? duration
    case "--width": width = CGFloat(Double(value) ?? Double(width))
    case "--idle": idleThreshold = Double(value) ?? idleThreshold
    case "--intro": intro = Double(value) ?? intro
    case "--screen": activeScreenOnly = value != "all"
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

func edgeLayer(_ color: NSColor, start: CGPoint, end: CGPoint, frame: CGRect) -> CAGradientLayer {
    let g = CAGradientLayer()
    g.frame = frame
    g.colors = [color.withAlphaComponent(0.6).cgColor, color.withAlphaComponent(0.0).cgColor]
    g.startPoint = start
    g.endPoint = end
    return g
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let color = parseColor(colorHex)
var windows: [NSWindow] = []
var rootLayers: [CALayer] = []
var rootScreens: [NSScreen] = []
var sources: [DispatchSourceSignal] = []

for screen in NSScreen.screens {
    let f = screen.frame
    let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    let view = NSView(frame: NSRect(origin: .zero, size: f.size))
    view.wantsLayer = true
    let root = CALayer()
    root.frame = view.bounds
    root.opacity = 0
    let s = f.size
    // CALayer origin is bottom-left on macOS.
    root.addSublayer(edgeLayer(color, start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1), frame: CGRect(x: 0, y: 0, width: s.width, height: width)))
    root.addSublayer(edgeLayer(color, start: CGPoint(x: 0.5, y: 1), end: CGPoint(x: 0.5, y: 0), frame: CGRect(x: 0, y: s.height - width, width: s.width, height: width)))
    root.addSublayer(edgeLayer(color, start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5), frame: CGRect(x: 0, y: 0, width: width, height: s.height)))
    root.addSublayer(edgeLayer(color, start: CGPoint(x: 1, y: 0.5), end: CGPoint(x: 0, y: 0.5), frame: CGRect(x: s.width - width, y: 0, width: width, height: s.height)))
    view.layer = root
    w.contentView = view
    w.orderFrontRegardless()
    windows.append(w)
    rootLayers.append(root)
    rootScreens.append(screen)
}

/// The layers to light now: the display under the mouse, or all of them.
func targetLayers() -> [CALayer] {
    guard activeScreenOnly else { return rootLayers }
    let mouse = NSEvent.mouseLocation
    let active = rootLayers.indices.filter { NSMouseInRect(mouse, rootScreens[$0].frame, false) }
    return (active.isEmpty ? Array(rootLayers.indices) : active).map { rootLayers[$0] }
}

/// One-shot with the same pacing as showPersistent(): 0.4s fade in, two 2.4s breaths, 0.4s fade out.
let oneShotSeconds = 5.6
func playOneShot(_ seconds: Double = oneShotSeconds) {
    let stops: [(t: Double, v: Float)] = [(0, 0), (0.4, 1), (1.6, 0.45), (2.8, 1), (4.0, 0.45), (5.2, 1), (5.6, 0)]
    for layer in targetLayers() {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = stops.map { $0.v }
        anim.keyTimes = stops.map { NSNumber(value: $0.t / oneShotSeconds) }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.timingFunctions = Array(repeating: ease, count: stops.count - 1)
        anim.duration = seconds
        layer.add(anim, forKey: "oneShot")
    }
}

/// Fade in once, then breathe until hide().
func showPersistent() {
    for layer in targetLayers() {
        layer.removeAllAnimations()
        layer.opacity = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.4
        layer.add(fade, forKey: "fadeIn")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 1.2
        pulse.beginTime = CACurrentMediaTime() + 0.4
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }
}

func hide() {
    for layer in rootLayers {
        let current = layer.presentation()?.opacity ?? 0
        layer.removeAllAnimations()
        layer.opacity = 0
        guard current > 0 else { continue }
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = current
        out.toValue = 0
        out.duration = 0.4
        layer.add(out, forKey: "fadeOut")
    }
}

func idleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

enum State { case intro, waiting, glowing }
var state = State.waiting

if watch {
    func tick() {
        let idle = idleSeconds()
        switch state {
        case .intro: break
        case .waiting:
            if idle >= idleThreshold { showPersistent(); state = .glowing }
        case .glowing:
            if idle < 1.5 { hide(); state = .waiting }
        }
    }
    if idleSeconds() >= idleThreshold {
        showPersistent()
        state = .glowing
    } else if intro > 0 {
        state = .intro
        playOneShot(intro)
        DispatchQueue.main.asyncAfter(deadline: .now() + intro) { state = .waiting }
    }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
} else if duration > 0 {
    playOneShot(duration)
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { NSApp.terminate(nil) }
} else {
    showPersistent()
}

if watch || duration <= 0 {
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { NSApp.terminate(nil) }
        }
        src.resume()
        sources.append(src)
    }
}
app.run()
