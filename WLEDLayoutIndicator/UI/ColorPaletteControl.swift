import SwiftUI

/// Replaces the old "Pick" overlay hack: a 2×4 preset grid plus a Custom…
/// button that opens `NSColorPanel` for arbitrary colours. Each preset is
/// a real `Button` — the entire swatch is hit-testable, no transparency
/// trick.
struct ColorPaletteControl: View {

    @Binding var color: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        let currentRGB = color.rgb
        let isCustom = !ColorPalette.presets.contains(currentRGB)

        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(ColorPalette.presets.enumerated()), id: \.offset) { _, preset in
                    swatch(preset, currentRGB: currentRGB)
                }
            }
            Button {
                ColorPanelBridge.shared.activate(initial: color) { new in
                    color = new
                }
            } label: {
                HStack(spacing: 3) {
                    if isCustom {
                        Image(systemName: "checkmark")
                    }
                    Text("Custom…")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func swatch(_ rgb: RGB, currentRGB: RGB) -> some View {
        let presetColor = rgb.swiftUI
        let isSelected = currentRGB == rgb
        return Button {
            color = presetColor
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(presetColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(contrastTextColor(for: presetColor))
                }
            }
            .frame(height: 18)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Picks black or white text against the swatch background using
    /// luminance. Same heuristic as the old `colorPickerButton` overlay.
    private func contrastTextColor(for color: Color) -> Color {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return .primary }
        let luminance =
            0.2126 * rgb.redComponent +
            0.7152 * rgb.greenComponent +
            0.0722 * rgb.blueComponent
        return luminance > 0.6 ? .black.opacity(0.85) : .white
    }
}
