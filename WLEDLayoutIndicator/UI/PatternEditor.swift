import SwiftUI

/// A 5×5 clickable grid for editing which LEDs are on/off.
/// Each cell is a square that toggles between the layout's colour (on)
/// and a dim background (off) on click. Drag across cells to paint.
struct PatternEditor: View {
    @Binding var pattern: Pattern
    var color: Color

    /// Track whether we're painting on or off during a drag gesture.
    @State private var paintValue: Bool?

    private let gridSize = 5
    private let cellSize: CGFloat = 24
    private let spacing: CGFloat = 2

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<gridSize, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<gridSize, id: \.self) { col in
                        cellView(row: row, col: col)
                    }
                }
            }
        }
        .padding(4)
        .background(Color(nsColor: .separatorColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let isOn = pattern[row, col]
        RoundedRectangle(cornerRadius: 2)
            .fill(isOn ? color : Color(nsColor: .quaternaryLabelColor))
            .frame(width: cellSize, height: cellSize)
            .onTapGesture {
                pattern[row, col].toggle()
            }
    }

    // MARK: - Presets

    /// Fill / Clear buttons stacked vertically, aligned to the trailing edge.
    struct Presets: View {
        @Binding var pattern: Pattern

        var body: some View {
            VStack(spacing: 4) {
                Button("Fill")  { pattern = .solid  }.frame(maxWidth: .infinity)
                Button("Clear") { pattern = .blank }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 76)
        }
    }
}

