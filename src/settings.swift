import AppKit
import Darwin

// This helper is a standalone executable, so keep translations inline instead of
// relying on an app bundle's localized resources. Other languages use English.
let usesKorean = Locale.preferredLanguages.first?.hasPrefix("ko") == true

func localized(_ english: String, _ korean: String) -> String {
    usesKorean ? korean : english
}

func statusTitle(_ status: String) -> String {
    switch status {
    case "blocked": return localized("Blocked", "입력 대기")
    case "done": return localized("Done", "완료")
    case "working": return localized("Working", "작업 중")
    case "idle": return localized("Idle", "유휴")
    default: return status
    }
}

func settingsAlert(_ error: Error) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = localized("Herdr Glow Settings", "Herdr Glow 설정")
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: localized("OK", "확인"))
    return alert
}

// Native editor for the flat settings consumed by on-status-changed.sh.
struct Setting {
    let section: String
    let key: String
    let fallback: String
    var id: String { "\(section).\(key)" }
}

let statuses = ["blocked", "done", "working", "idle"]
let colors = ["FF8A1F", "34C759", "0A84FF", "8E8E93"]
let settings: [Setting] = statuses.enumerated().flatMap { index, status in
    [Setting(section: status, key: "pulse", fallback: index < 2 ? "5.6" : "0"),
     Setting(section: status, key: "idle", fallback: index == 0 ? "30" : "0"),
     Setting(section: status, key: "toast", fallback: index < 2 ? "true" : "false"),
     Setting(section: status, key: "color", fallback: colors[index])]
} + [Setting(section: "glow", key: "width", fallback: "60"),
     Setting(section: "glow", key: "screen", fallback: "active"),
     Setting(section: "toast", key: "duration", fallback: "4"),
     Setting(section: "toast", key: "click", fallback: "true")]

func problem(_ message: String) -> NSError {
    NSError(domain: "HerdrGlowSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// Find an inline comment without treating # inside a quoted string as a comment.
func commentIndex(in line: String) -> String.Index? {
    var quote: Character?
    var escaped = false
    for index in line.indices {
        let character = line[index]
        if escaped { escaped = false; continue }
        if quote == "\"" && character == "\\" { escaped = true; continue }
        if let current = quote {
            if character == current { quote = nil }
        } else if character == "\"" || character == "'" {
            quote = character
        } else if character == "#" {
            return index
        }
    }
    return nil
}

func content(of line: String) -> String {
    let end = commentIndex(in: line) ?? line.endIndex
    return line[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Configuration {
    let url: URL
    let original: Data?
    let lines: [String]
    var values: [String: String] = [:]
    var locations: [String: Int] = [:]

    init(url: URL) throws {
        self.url = url
        do { original = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            original = nil
        }
        guard let text = original == nil ? "" : String(data: original!, encoding: .utf8) else {
            throw problem(localized("The config file must use UTF-8 encoding.", "설정 파일은 UTF-8 인코딩이어야 합니다."))
        }
        lines = text.components(separatedBy: "\n")
        var section = ""
        for (index, line) in lines.enumerated() {
            let trimmed = content(of: line)
            if trimmed.hasPrefix("[") {
                section = trimmed.hasSuffix("]") ? String(trimmed.dropFirst().dropLast()) : ""
                continue
            }
            guard let equal = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
            let id = "\(section).\(key)"
            guard settings.contains(where: { $0.id == id }) else { continue }
            guard locations[id] == nil else {
                throw problem(localized("Duplicate setting: \(id). Please fix it in config.toml first.",
                                        "설정 항목 \(id)이 중복되어 있습니다. 먼저 config.toml에서 중복을 제거해 주세요."))
            }
            var value = trimmed[trimmed.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            values[id] = value
            locations[id] = index
        }
    }

    func save(_ values: [String: String]) throws {
        var output = lines
        // Replace known keys in place, keeping unrelated settings and comments.
        for setting in settings {
            guard let index = locations[setting.id], let value = values[setting.id] else { continue }
            let line = output[index]
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let comment = commentIndex(in: line).map { " " + line[$0...] } ?? ""
            output[index] = "\(indent)\(setting.key) = \(value)\(comment)"
        }
        // Add missing keys at the end of their section, or append a new section.
        for section in statuses + ["glow", "toast"] {
            let missing = settings.filter { $0.section == section && locations[$0.id] == nil }
            guard !missing.isEmpty else { continue }
            let additions = missing.map { "\($0.key) = \(values[$0.id]!)" }
            if let header = output.firstIndex(where: { content(of: $0) == "[\(section)]" }) {
                var end = header + 1
                while end < output.count && !content(of: output[end]).hasPrefix("[") { end += 1 }
                while end > header + 1 && output[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
                output.insert(contentsOf: additions, at: end)
            } else {
                if output.last != "" { output.append("") }
                output.append("[\(section)]")
                output.append(contentsOf: additions)
                output.append("")
            }
        }
        if output.last != "" { output.append("") }
        let current: Data?
        do { current = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            current = nil
        }
        guard current == original else {
            throw problem(localized("config.toml changed while this window was open. Reopen Settings to load the latest version before saving.",
                                    "창이 열린 동안 config.toml이 외부에서 변경되었습니다. 설정 창을 다시 열어 최신 내용을 불러온 뒤 저장해 주세요."))
        }
        try Data(output.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }
}

// Keep the native palette, hex input and quick presets in sync for one status.
final class ColorSettingView: NSStackView, NSTextFieldDelegate {
    let hexField: NSTextField
    private let well = NSColorWell()
    private let presets = [
        (hex: "FF453A", name: localized("Red", "빨강")),
        (hex: "0A84FF", name: localized("Blue", "파랑")),
        (hex: "FF8A1F", name: localized("Orange", "주황")),
        (hex: "34C759", name: localized("Green", "초록"))
    ]

    static func color(from hex: String) -> NSColor? {
        guard hex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    init(value: String, fallback: String, status: String) {
        hexField = NSTextField(string: value)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        well.color = Self.color(from: value) ?? Self.color(from: fallback)!
        well.target = self
        well.action = #selector(paletteChanged)
        well.toolTip = localized("Click to open the color palette", "클릭하여 색상 팔레트 열기")
        well.setAccessibilityLabel(localized("\(statusTitle(status)) color palette", "\(statusTitle(status)) 색상 팔레트"))
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 28).isActive = true
        addArrangedSubview(well)

        hexField.delegate = self
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.widthAnchor.constraint(equalToConstant: 84).isActive = true
        hexField.setAccessibilityLabel(localized("\(statusTitle(status)) hex color", "\(statusTitle(status)) 색상 코드"))
        addArrangedSubview(hexField)

        let swatches = NSStackView()
        swatches.spacing = 4
        for (index, preset) in presets.enumerated() {
            let color = Self.color(from: preset.hex)!
            let button = NSButton(image: NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                color.setFill()
                circle.fill()
                NSColor.labelColor.withAlphaComponent(0.3).setStroke()
                circle.lineWidth = 1
                circle.stroke()
                return true
            }, target: self, action: #selector(selectPreset(_:)))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.tag = index
            button.toolTip = "\(preset.name) · #\(preset.hex)"
            button.setAccessibilityLabel(localized("Use \(preset.name) for \(statusTitle(status))", "\(statusTitle(status)) 색상을 \(preset.name)으로 설정"))
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            swatches.addArrangedSubview(button)
        }
        addArrangedSubview(swatches)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func paletteChanged() {
        guard let color = well.color.usingColorSpace(.sRGB) else { return }
        hexField.stringValue = String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    private func setColor(_ color: NSColor) {
        well.color = color
        if well.isActive { NSColorPanel.shared.color = color }
    }

    @objc private func selectPreset(_ sender: NSButton) {
        let hex = presets[sender.tag].hex
        setColor(Self.color(from: hex)!)
        hexField.stringValue = hex
    }

    func controlTextDidChange(_ notification: Notification) {
        let hex = hexField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = Self.color(from: hex) { setColor(color) }
    }
}

final class SettingsController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let configuration: Configuration
    var window: NSWindow!
    var fields: [String: NSTextField] = [:]
    var toggles: [String: NSButton] = [:]
    let screen = NSPopUpButton()
    var observer: NSObjectProtocol?
    var previewProcess: Process?

    init(configuration: Configuration) { self.configuration = configuration }

    func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }

    func field(_ id: String, width: CGFloat = 80) -> NSTextField {
        let setting = settings.first { $0.id == id }!
        let field = NSTextField(string: configuration.values[id] ?? setting.fallback)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        fields[id] = field
        return field
    }

    func toggle(_ id: String, title: String = "") -> NSButton {
        let setting = settings.first { $0.id == id }!
        let value = configuration.values[id] ?? setting.fallback
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.allowsMixedState = value != "true" && value != "false"
        button.state = value == "true" ? .on : value == "false" ? .off : .mixed
        toggles[id] = button
        return button
    }

    func colorControl(_ status: String) -> ColorSettingView {
        let id = "\(status).color"
        let setting = settings.first { $0.id == id }!
        let control = ColorSettingView(value: configuration.values[id] ?? setting.fallback,
                                       fallback: setting.fallback, status: status)
        fields[id] = control.hexField
        return control
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSColorPanel.shared.title = localized("Colors", "색상")
        NSColorPanel.shared.showsAlpha = false
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // The preview helper may change the frontmost app. Keep this accessory
        // editor visible and above ordinary terminal windows when it deactivates.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        window = panel
        window.title = localized("Herdr Glow Settings", "Herdr Glow 설정")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])

        let heading = label(localized("Agent status", "에이전트 상태"))
        heading.font = .boldSystemFont(ofSize: 14)
        root.addArrangedSubview(heading)
        var rows: [[NSView]] = [[label(localized("Status", "상태")), label(localized("Pulse (s)", "알림 시간(초)")),
                                label(localized("Idle (s)", "유휴 시간(초)")), label(localized("Toast", "토스트")),
                                label(localized("Color · palette & presets", "색상 · 팔레트 및 프리셋")),
                                label(localized("Test glow", "글로우 테스트"))]]
        for (index, status) in statuses.enumerated() {
            let title = label(statusTitle(status))
            title.toolTip = status
            let test = NSButton(title: localized("Test", "테스트"), target: self, action: #selector(previewGlow(_:)))
            test.tag = index
            test.setAccessibilityLabel(localized("Test \(statusTitle(status)) glow", "\(statusTitle(status)) 글로우 테스트"))
            rows.append([title, field("\(status).pulse"), field("\(status).idle"),
                         toggle("\(status).toast"), colorControl(status), test])
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 20
        grid.rowSpacing = 10
        grid.yPlacement = .center
        root.addArrangedSubview(grid)
        let timingHelp = NSStackView()
        timingHelp.orientation = .vertical
        timingHelp.alignment = .leading
        timingHelp.spacing = 4
        timingHelp.addArrangedSubview(label(localized(
            "* Pulse: seconds of edge glow when the status changes (0 = off).",
            "* 알림 시간: 상태가 바뀔 때 화면 가장자리 글로우가 깜박이는 시간 (0 = 끄기)"
        ), secondary: true))
        timingHelp.addArrangedSubview(label(localized(
            "* Idle: seconds without input before glow returns while that status lasts (0 = off).",
            "* 유휴 시간: 같은 상태에서 입력이 없을 때 글로우가 다시 켜지는 기준 시간 (0 = 끄기)"
        ), secondary: true))
        timingHelp.addArrangedSubview(label(localized(
            "Test uses unsaved values. A pulse of 0 previews for 3 seconds.",
            "테스트는 현재 입력값을 사용하며, 알림 시간이 0이면 3초간 표시합니다."
        ), secondary: true))
        root.addArrangedSubview(timingHelp)

        let general = label(localized("Glow & toast", "글로우 및 토스트"))
        general.font = .boldSystemFont(ofSize: 14)
        root.addArrangedSubview(general)
        screen.addItems(withTitles: [localized("Active display (under mouse)", "마우스가 있는 디스플레이"), localized("All displays", "모든 디스플레이")])
        let selectedScreen = configuration.values["glow.screen"] ?? "active"
        if selectedScreen == "active" || selectedScreen == "all" {
            screen.selectItem(at: selectedScreen == "all" ? 1 : 0)
        } else {
            screen.addItem(withTitle: localized("Unknown: \(selectedScreen)", "알 수 없는 값: \(selectedScreen)"))
            screen.selectItem(at: 2)
        }
        let generalGrid = NSGridView(views: [
            [label(localized("Glow width (pt)", "글로우 두께(pt)")), field("glow.width"), label(localized("Displays", "디스플레이")), screen],
            [label(localized("Toast duration (s)", "토스트 표시 시간(초)")), field("toast.duration"), label(localized("Toast click", "토스트 클릭")),
             toggle("toast.click", title: localized("Focus agent pane", "에이전트 패널로 이동"))]
        ])
        generalGrid.columnSpacing = 12
        generalGrid.rowSpacing = 12
        generalGrid.yPlacement = .center
        root.addArrangedSubview(generalGrid)
        root.addArrangedSubview(label(localized("Saved changes apply from the next agent event.",
                                               "저장한 설정은 다음 에이전트 이벤트부터 적용됩니다."), secondary: true))

        let buttons = NSStackView()
        buttons.spacing = 8
        let cancel = NSButton(title: localized("Cancel", "취소"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: localized("Save", "저장"), target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(save)
        root.addArrangedSubview(buttons)
        buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true

        observer = DistributedNotificationCenter.default().addObserver(forName: showNotification, object: nil, queue: .main) { [weak self] _ in
            self?.show()
        }
        window.center()
        show()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func cancel() { NSApp.terminate(nil) }

    func numberValue(_ id: String, positive: Bool) throws -> Double {
        let field = fields[id]!
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(value), number.isFinite, positive ? number > 0 : number >= 0 else {
            window.makeFirstResponder(field)
            throw problem(localized("\(id) must be a \(positive ? "positive" : "non-negative") number.",
                                    "\(id)은 \(positive ? "0보다 큰" : "0 이상의") 숫자로 입력해 주세요."))
        }
        return number
    }

    func colorValue(_ status: String) throws -> String {
        let field = fields["\(status).color"]!
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ColorSettingView.color(from: value) != nil else {
            window.makeFirstResponder(field)
            throw problem(localized("\(statusTitle(status)) color must contain six hex digits, such as FF8A1F.",
                                    "\(statusTitle(status)) 색상은 FF8A1F처럼 16진수 여섯 자리로 입력해 주세요."))
        }
        return value.uppercased()
    }

    func displayValue() throws -> String {
        guard (0..<2).contains(screen.indexOfSelectedItem) else {
            throw problem(localized("Choose Active display or All displays.", "마우스가 있는 디스플레이 또는 모든 디스플레이를 선택해 주세요."))
        }
        return screen.indexOfSelectedItem == 1 ? "all" : "active"
    }

    func previewArguments(for status: String) throws -> [String] {
        let pulse = try numberValue("\(status).pulse", positive: false)
        return ["--color", try colorValue(status), "--duration", String(pulse > 0 ? pulse : 3),
                "--width", String(try numberValue("glow.width", positive: true)), "--screen", try displayValue()]
    }

    func stopPreview() {
        if let process = previewProcess, process.isRunning { process.terminate() }
        previewProcess = nil
    }

    @objc func previewGlow(_ sender: NSButton) {
        guard statuses.indices.contains(sender.tag) else { return }
        do {
            let arguments = try previewArguments(for: statuses[sender.tag])
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            let process = Process()
            process.executableURL = executable.deletingLastPathComponent().appendingPathComponent("glow")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] completed in
                DispatchQueue.main.async {
                    guard let self = self, self.previewProcess === completed else { return }
                    self.previewProcess = nil
                }
            }
            stopPreview()
            try process.run()
            previewProcess = process
        } catch {
            settingsAlert(error).beginSheetModal(for: window)
        }
    }

    @objc func save() {
        do {
            var values: [String: String] = [:]
            for setting in settings {
                if let toggle = toggles[setting.id] {
                    guard toggle.state != .mixed else {
                        throw problem(localized("Choose a value for \(setting.id).", "\(setting.id)의 사용 여부를 선택해 주세요."))
                    }
                    values[setting.id] = toggle.state == .on ? "true" : "false"
                } else if setting.id == "glow.screen" {
                    values[setting.id] = "\"\(try displayValue())\""
                } else if fields[setting.id] != nil {
                    if setting.key == "color" {
                        values[setting.id] = "\"\(try colorValue(setting.section))\""
                    } else {
                        let positive = setting.id == "glow.width" || setting.id == "toast.duration"
                        values[setting.id] = String(try numberValue(setting.id, positive: positive))
                    }
                }
            }
            try configuration.save(values)
            NSApp.terminate(nil)
        } catch {
            let alert = settingsAlert(error)
            alert.beginSheetModal(for: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === window {
            NSApp.terminate(nil)
        }
    }

    // Explicit Save, Cancel, Quit and main-window close actions own the editor's lifetime.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { stopPreview() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let configuredDirectory = ProcessInfo.processInfo.environment["HERDR_PLUGIN_CONFIG_DIR"] ?? ""
let directory = configuredDirectory.isEmpty
    ? NSHomeDirectory() + "/.config/herdr/plugins/config/devookim.herdr-glow"
    : configuredDirectory
let configURL = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("config.toml").standardizedFileURL
let showNotification = Notification.Name("devookim.herdr-glow.settings.show." + configURL.path)

// Keep a single settings editor per config directory; invoking again brings it forward.
var lockFD: Int32 = -1
var controller: SettingsController?
do {
    try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    lockFD = open(configURL.deletingLastPathComponent().appendingPathComponent(".settings.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard lockFD >= 0 else {
        throw problem(localized("Could not open the settings window lock: \(String(cString: strerror(errno)))",
                                "설정 창의 잠금 파일을 열 수 없습니다: \(String(cString: strerror(errno)))"))
    }
    if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        guard errno == EWOULDBLOCK else {
            throw problem(localized("Could not lock the settings window: \(String(cString: strerror(errno)))",
                                    "설정 창을 잠글 수 없습니다: \(String(cString: strerror(errno)))"))
        }
        DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
    controller = SettingsController(configuration: try Configuration(url: configURL))
    app.delegate = controller

    // Standard editing shortcuts for the settings text fields.
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: localized("Quit Herdr Glow Settings", "Herdr Glow 설정 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let fileItem = NSMenuItem(title: localized("File", "파일"), action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: localized("File", "파일"))
    fileMenu.addItem(withTitle: localized("Close", "닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileItem.submenu = fileMenu
    menu.addItem(fileItem)
    let editItem = NSMenuItem(title: localized("Edit", "편집"), action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: localized("Edit", "편집"))
    for (title, action, key) in [(localized("Cut", "오려두기"), "cut:", "x"), (localized("Copy", "복사"), "copy:", "c"),
                                 (localized("Paste", "붙여넣기"), "paste:", "v"), (localized("Select All", "모두 선택"), "selectAll:", "a")] {
        editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    editItem.submenu = editMenu
    menu.addItem(editItem)
    app.mainMenu = menu
    app.run()
} catch {
    app.activate(ignoringOtherApps: true)
    settingsAlert(error).runModal()
    exit(1)
}
