import SwiftUI
import ServiceManagement

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
                    Slider(value: brightnessBinding, in: 0...255, step: 1)
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

            Section("Layout → Color") {
                ForEach(sortedSourceIDs, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        ColorPicker("", selection: colorBinding(for: id), supportsOpacity: false)
                            .labelsHidden()
                        Button {
                            removeMapping(id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("com.apple.keylayout.…", text: $newSourceID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addMapping() }
                        .disabled(newSourceID.isEmpty)
                }

                HStack {
                    Text("Default (fallback)")
                    Spacer()
                    ColorPicker("", selection: defaultColorBinding, supportsOpacity: false)
                        .labelsHidden()
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
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Computed

    private var sortedSourceIDs: [String] {
        settings.config.mapping.keys.sorted()
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
            get: { settings.config.defaultColor.swiftUI },
            set: { v in settings.update { $0.defaultColor = v.rgb } }
        )
    }

    private func colorBinding(for id: String) -> Binding<Color> {
        Binding(
            get: { (settings.config.mapping[id] ?? settings.config.defaultColor).swiftUI },
            set: { v in settings.update { $0.mapping[id] = v.rgb } }
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

    // MARK: - Actions

    private func addMapping() {
        let id = newSourceID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        settings.update { $0.mapping[id] = $0.defaultColor }
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
