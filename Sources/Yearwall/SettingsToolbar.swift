import AppKit
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
    let service: WallpaperService
    let close: () -> Void

    @State private var isEditingCustom = false

    var body: some View {
        HStack(spacing: 10) {
            Picker("Theme", selection: themeSelection) {
                ForEach(ThemeLibrary.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                Divider()
                Text("Custom").tag(Self.customID)
            }
            .labelsHidden()
            .fixedSize()
            .help("Theme")

            if store.config.themePresetID == nil {
                Button { isEditingCustom.toggle() } label: {
                    Label("Edit custom theme", systemImage: "paintpalette")
                }
                .help("Background, marks and picture")
                .popover(isPresented: $isEditingCustom, arrowEdge: .top) {
                    CustomThemeEditor(store: store, service: service)
                }
            }

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

    private static let customID = "custom"

    /// The followed preset, or Custom. Picking Custom starts from the colours
    /// on screen right now and opens the editor.
    private var themeSelection: Binding<String> {
        Binding(
            get: { store.config.themePresetID ?? Self.customID },
            set: { id in
                if let preset = ThemeLibrary.preset(id: id) {
                    store.update { $0.adopt(preset: preset) }
                } else if store.config.themePresetID != nil {
                    let appearance = service.currentAppearance()
                    store.update { config in
                        let colours = config.theme.resolved(
                            for: appearance,
                            maxContrast: config.budget.maxPatternContrast,
                            remainingIntensity: config.budget.remainingIntensity
                        )
                        config.customiseTheme {
                            $0 = .custom(background: colours.background, marks: colours.elapsed, accent: $0.accent)
                        }
                    }
                    isEditingCustom = true
                }
            }
        )
    }
}

/// Background, marks and an optional picture for the Custom theme.
private struct CustomThemeEditor: View {
    @Bindable var store: ConfigStore
    let service: WallpaperService

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Background")
                ColorPicker("Background", selection: background, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(hasPicture)
            }
            GridRow {
                Text("Marks")
                ColorPicker("Marks", selection: marks, supportsOpacity: true)
                    .labelsHidden()
            }
            GridRow {
                Text("Picture")
                HStack {
                    Button(hasPicture ? "Replace…" : "Choose…", action: choosePicture)
                    if hasPicture {
                        Button("Remove") { service.removeBackdrop() }
                    }
                }
            }
        }
        .padding(16)
    }

    private var hasPicture: Bool { store.config.backdropName != nil }

    private var background: Binding<CGColor> {
        Binding(
            get: { store.config.theme.base.cgColor },
            set: { colour in
                store.update { config in
                    config.customiseTheme {
                        $0 = .custom(background: RGBA(colour), marks: $0.elapsedOverride ?? RGBA(1, 1, 1), accent: $0.accent)
                    }
                }
            }
        )
    }

    private var marks: Binding<CGColor> {
        Binding(
            get: { (store.config.theme.elapsedOverride ?? RGBA(1, 1, 1)).cgColor },
            set: { colour in
                store.update { config in
                    config.customiseTheme {
                        $0 = .custom(background: $0.base, marks: RGBA(colour), accent: $0.accent)
                    }
                }
            }
        )
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture to draw the year over"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try service.setBackdrop(from: url)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
}

private extension RGBA {
    init(_ colour: CGColor) {
        let srgb = colour.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let c = srgb?.components ?? [0, 0, 0, 1]
        self.init(Double(c[0]), Double(c[1]), Double(c[2]), Double(srgb?.alpha ?? 1))
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
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
