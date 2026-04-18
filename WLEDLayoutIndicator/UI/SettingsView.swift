import SwiftUI
import ServiceManagement
import Combine

struct SettingsView: View {

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator

    @StateObject private var discovery = WLEDDiscovery()
    @State private var testResult: TestResult = .none
    @State private var newSourceID: String = ""

    enum TestResult: Equatable {
        case none, running, ok, failed(String)
    }

    var body: some View {
        Form {
            Section("WLED device") {
                TextField("Host (IP or .local)", text: hostBinding)
                    .textFieldStyle(.roundedBorder)

                // Auto-discover devices whose mDNS name contains "wled" + "key".
                HStack {
                    Button("Discover on network") { discovery.start() }
                        .disabled(discovery.isSearching)
                    if discovery.isSearching {
                        ProgressView().controlSize(.small)
                    }
                }
                ForEach(discovery.devices) { device in
                    Button {
                        settings.update { $0.wled.host = device.hostname }
                    } label: {
                        Label(device.hostname, systemImage: "wifi")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Text("Brightness")
                    Slider(value: brightnessBinding, in: 0...255)
                    Text("\(settings.config.wled.brightness)").monospacedDigit().frame(width: 36)
                }

                Stepper("LED count: \(settings.config.wled.ledCount)",
                        value: ledCountBinding, in: 1...1000)
                Stepper("Segment id: \(settings.config.wled.segmentId)",
                        value: segmentIdBinding, in: 0...31)

                HStack {
                    Button("Test connection") {
                        Task { await runTest() }
                    }
                    testStatusView
                }
            }

            Section("Matrix orientation") {
                Picker("Rotation", selection: rotationBinding) {
                    Text("0°").tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                .pickerStyle(.segmented)
                Text("Rotates the pattern on the physical device. Does not change stored patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Layout → Color & Pattern")
            {
                ForEach(sortedSourceIDs, id: \.self)
                {
                    id in
                    VStack(alignment: .leading, spacing: 12)
                    {
                        HStack(alignment: .top)
                        {
                            Text(id).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(role: .destructive) {
                                removeMapping(id)
                            } label: {
                                Label("", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack(alignment: .top)
                        {
                            HStack(alignment: .top)
                            {
                                PatternEditor(
                                    pattern: patternBinding(for: id),
                                    color: (settings.config.mapping[id]?.color ?? settings.config.defaultEntry.color).swiftUI
                                )
                               
                                Section {
                                    VStack(alignment: .leading, spacing: 12) {
                                        colorPickerButton(for: id)

                                        Spacer(minLength: 0)

                                        actionButton("Fill") {
                                            settings.update {
                                                $0.mapping[id, default: $0.defaultEntry].pattern = .solid
                                            }
                                        }

                                        actionButton("Clear") {
                                            settings.update {
                                                $0.mapping[id, default: $0.defaultEntry].pattern = .blank
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                }
                                .controlSize(.small)
                                .frame(width: 86)
                                
                            }
                        }
                    }
                }
            }
            
  
            Section("Reset") {
                Button("Re-detect layouts & WLED device") {
                    resetAutoConfig()
                }
                .foregroundStyle(.red)
                Text("Re-scans installed keyboard layouts and searches for a WLED device on the network. Replaces current host and layout mappings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Per-app layout memory") {
                Toggle("Remember and restore layout per app", isOn: autoSwitchBinding)
                Text("When enabled, the app records which keyboard layout is active in each foreground app and switches back to it whenever you focus that app again. First-time apps are not changed — current layout is just remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Remembered: \(settings.config.appLayoutMemory.count) app\(settings.config.appLayoutMemory.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Forget all") {
                        settings.update { $0.appLayoutMemory = [:] }
                    }
                    .disabled(settings.config.appLayoutMemory.isEmpty)
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)

                HStack {
                    Text("Current input source:")
                    Text(coordinator.currentSourceID)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build:")
                    Text(buildInfo)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }


    @ViewBuilder
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func colorPickerButton(for id: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorBinding(for: id).wrappedValue)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }

            Text("Pick")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(contrastTextColor(for: colorBinding(for: id).wrappedValue))
                .allowsHitTesting(false)

            ColorPicker("", selection: colorBinding(for: id), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.075)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func contrastTextColor(for color: Color) -> Color {
        #if canImport(AppKit)
        let nsColor = NSColor(color)

        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            return .primary
        }

        let luminance =
            0.2126 * rgb.redComponent +
            0.7152 * rgb.greenComponent +
            0.0722 * rgb.blueComponent

        return luminance > 0.6 ? .black.opacity(0.75) : .white.opacity(0.92)
        #else
        return .primary
        #endif
    }


    // MARK: - Computed

    private var sortedSourceIDs: [String] {
        settings.config.mapping.keys.sorted()
    }

    /// Version + executable mtime. The bundle version rarely bumps in dev,
    /// but the mtime is always the last rebuild — reliable "is my fix running".
    private var buildInfo: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var stamp = ""
        if let exe = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: exe.path),
           let mtime = attrs[.modificationDate] as? Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            stamp = " · \(f.string(from: mtime))"
        }
        return "v\(version) (\(build))\(stamp)"
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testResult {
        case .none:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Bindings

    private var hostBinding: Binding<String> {
        Binding(
            get: { settings.config.wled.host },
            set: { v in settings.update { $0.wled.host = v } }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(settings.config.wled.brightness) },
            set: { v in settings.update { $0.wled.brightness = Int(v) } }
        )
    }

    private var ledCountBinding: Binding<Int> {
        Binding(
            get: { settings.config.wled.ledCount },
            set: { v in settings.update { $0.wled.ledCount = v } }
        )
    }

    private var segmentIdBinding: Binding<Int> {
        Binding(
            get: { settings.config.wled.segmentId },
            set: { v in settings.update { $0.wled.segmentId = v } }
        )
    }

    private var defaultColorBinding: Binding<Color> {
        Binding(
            get: { settings.config.defaultEntry.color.swiftUI },
            set: { v in settings.update { $0.defaultEntry.color = v.rgb } }
        )
    }

    private var defaultPatternBinding: Binding<Pattern> {
        Binding(
            get: { settings.config.defaultEntry.pattern },
            set: { v in settings.update { $0.defaultEntry.pattern = v } }
        )
    }

    private func colorBinding(for id: String) -> Binding<Color> {
        Binding(
            get: { (settings.config.mapping[id]?.color ?? settings.config.defaultEntry.color).swiftUI },
            set: { v in settings.update {
                $0.mapping[id, default: $0.defaultEntry].color = v.rgb
            }}
        )
    }

    private func patternBinding(for id: String) -> Binding<Pattern> {
        Binding(
            get: { settings.config.mapping[id]?.pattern ?? .solid },
            set: { v in settings.update {
                $0.mapping[id, default: $0.defaultEntry].pattern = v
            }}
        )
    }

    private var rotationBinding: Binding<Int> {
        Binding(
            get: { settings.config.matrixRotation },
            set: { v in settings.update { $0.matrixRotation = v } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.config.launchAtLogin },
            set: { v in
                settings.update { $0.launchAtLogin = v }
                applyLaunchAtLogin(v)
            }
        )
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { settings.config.autoSwitchOnAppFocus },
            set: { v in settings.update { $0.autoSwitchOnAppFocus = v } }
        )
    }

    // MARK: - Actions

    private func resetAutoConfig() {
        // 1. Re-detect keyboard layouts
        let ids = LayoutMonitor.enabledKeyboardSourceIDs()
        settings.update { config in
            config.mapping = Config.buildMapping(for: ids)
        }

        // 2. Re-discover WLED device
        discovery.start()
        var observer: AnyCancellable?
        observer = discovery.$devices
            .filter { !$0.isEmpty }
            .first()
            .sink { [settings] devices in
                if let first = devices.first {
                    settings.update { $0.wled.host = first.hostname }
                }
                observer?.cancel()
            }
    }

    private func addMapping() {
        let id = newSourceID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        settings.update { $0.mapping[id] = $0.defaultEntry }
        newSourceID = ""
    }

    private func removeMapping(_ id: String) {
        settings.update { $0.mapping.removeValue(forKey: id) }
    }

    private func runTest() async {
        testResult = .running
        switch await coordinator.testConnection() {
        case .success:
            testResult = .ok
        case .failure(let err):
            testResult = .failed(String(describing: err))
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Intentionally silent; surface via a toast in a future iteration.
        }
    }
}

// MARK: - Color bridging

extension RGB {
    var swiftUI: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension Color {
    /// Extracts sRGB components. Falls back to black on failure (unreachable
    /// in practice since `ColorPicker` always yields a valid colour).
    var rgb: RGB {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = UInt8(max(0, min(255, Int(ns.redComponent * 255))))
        let g = UInt8(max(0, min(255, Int(ns.greenComponent * 255))))
        let b = UInt8(max(0, min(255, Int(ns.blueComponent * 255))))
        return RGB(r: r, g: g, b: b)
    }
}


