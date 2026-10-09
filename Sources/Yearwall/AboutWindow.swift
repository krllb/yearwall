import AppKit
import SwiftUI

/// The standard About panel, redrawn: the panel can only show links as blue
/// text in its credits, and these read better as buttons.
@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.styleMask = [.titled, .closable]
        window.title = "About Yearwall"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct AboutView: View {
    private static let links = [
        ("Website", "yearwall.krllb.com", "https://yearwall.krllb.com"),
        ("GitHub", "krllb/yearwall", "https://github.com/krllb/yearwall"),
        ("Developer", "krllb.com", "https://krllb.com"),
    ]

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(Self.info("CFBundleName"))
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 10)
            Text("Version \(Self.info("CFBundleShortVersionString")) (\(Self.info("CFBundleVersion")))")
                .font(.system(size: 11))
                .padding(.top, 6)

            Form {
                Section {
                    ForEach(Self.links, id: \.0) { title, address, url in
                        Button { openURL(URL(string: url)!) } label: {
                            LabeledContent(title) {
                                HStack(spacing: 4) {
                                    Text(address)
                                    Image(systemName: "arrow.up.forward")
                                        .imageScale(.small)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 150)

            Text(Self.info("NSHumanReadableCopyright"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding(.top, 4)
        .frame(width: 320)
    }

    /// The embedded Info.plist, so `swift run` shows the same values.
    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
