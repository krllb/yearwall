import PatternEngine
import SwiftUI
import WallpaperService

/// The settings as one glass bar, placed under the grid on the real desktop.
///
/// There is no preview: opening it clears the desktop, so the wallpaper being
/// edited is right there above it.
struct SettingsToolbar: View {
    /// Transparent room around the bar, so its shadow is not clipped by the
    /// window. Placement subtracts it to line up the visible edge.
    static let margin: CGFloat = 12

    @Bindable var store: ConfigStore
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Theme", selection: themeSelection) {
                ForEach(ThemeLibrary.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                if store.config.themePresetID == nil {
                    Text("Custom").tag("custom")
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Theme")

            separator

            Toggle(isOn: $store.config.connectsElapsedMarks) {
                Label("Join elapsed marks into a line", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .help("Join elapsed marks into a line")
            Toggle(isOn: $store.config.blacksOutMenuBar) {
                Label("Black out the menu bar strip", systemImage: "menubar.rectangle")
            }
            .help("Black out the menu bar strip")

            separator

            ToolbarSlider(
                title: "Mark size", systemImage: "circle.fill",
                value: $store.config.budget.maxMarkSizePoints, range: 2 ... 24, step: 0.5
            )
            ToolbarSlider(
                title: "Gap between columns", systemImage: "arrow.left.and.right",
                value: $store.config.budget.columnGapPoints, range: 0 ... 40, step: 0.5
            )
            ToolbarSlider(
                title: "Gap between rows", systemImage: "arrow.up.and.down",
                value: $store.config.budget.rowGapPoints, range: 0 ... 60, step: 0.5
            )

            separator

            Button { store.resetBudget() } label: {
                Label("Reset the grid", systemImage: "arrow.counterclockwise")
            }
            .help("Put the grid numbers back to the defaults")
            Button(action: close) {
                Label("Close", systemImage: "xmark")
            }
            .help("Close")
            .keyboardShortcut(.cancelAction)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassBar()
        .padding(Self.margin)
        .fixedSize()
    }

    private var separator: some View {
        Divider().frame(height: 18)
    }

    /// The preset the current theme equals, or "custom" once it is edited.
    private var themeSelection: Binding<String> {
        Binding(
            get: { store.config.themePresetID ?? "custom" },
            set: { id in
                guard let preset = ThemeLibrary.preset(id: id) else { return }
                store.update { $0.adopt(preset: preset) }
            }
        )
    }
}

/// Icon, slider, value: one knob small enough for a toolbar row.
private struct ToolbarSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            // Stepped by rounding rather than `step:`, which makes macOS draw a
            // tick for every step under the track.
            Slider(value: stepped, in: range)
                .frame(width: 90)
            Text(value.formatted(.number.precision(.fractionLength(0 ... 1))))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .help("\(title), in points")
    }

    private var stepped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 / step).rounded() * step }
        )
    }
}

private extension View {
    /// Liquid Glass where the system has it, a material everywhere else.
    @ViewBuilder
    func glassBar() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
