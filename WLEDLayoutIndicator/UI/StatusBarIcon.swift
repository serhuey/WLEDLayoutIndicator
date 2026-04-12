import SwiftUI

/// Menu-bar label: a filled 5×5 grid glyph tinted with the current colour,
/// or a warning triangle when the WLED link has failed.
///
/// Observing the coordinator via @EnvironmentObject ensures the label
/// refreshes on every colour / status change.
struct StatusBarIcon: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        default:
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(swiftUIColor)
        }
    }

    private var swiftUIColor: Color {
        let c = coordinator.currentColor
        return Color(
            red:   Double(c.r) / 255.0,
            green: Double(c.g) / 255.0,
            blue:  Double(c.b) / 255.0
        )
    }
}
