import AppKit
import Foundation
import PatternEngine
import Renderer
import TimeModel
import WallpaperService

/// `Yearwall --preview` renders straight to a file without touching the desktop.
/// Development aid, and how the README images are made.
enum PreviewCommand {
    static func run(arguments: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        let width = Int(value("--width") ?? "") ?? 2560
        let height = Int(value("--height") ?? "") ?? 1600
        let scale = Double(value("--scale") ?? "") ?? 2
        let appearance = Appearance(rawValue: value("--appearance") ?? value("--scheme") ?? "dark") ?? .dark
        let output = URL(fileURLWithPath: value("--out") ?? "preview.png")
        let backdrop = value("--backdrop").flatMap { path -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let calculator = ProgressCalculator()
        var config = WallpaperConfig.default
        config.installSeed = UInt64(value("--seed") ?? "") ?? 0xD07_D07_D07
        config.patternID = value("--pattern") ?? config.patternID
        config.mode = TimeMode(rawValue: value("--mode") ?? "year") ?? .year
        if let themeID = value("--theme"), let preset = ThemeLibrary.preset(id: themeID) {
            config.adopt(preset: preset)
        }
        if let marks = value("--marks").flatMap({ UInt32($0, radix: 16) }) {
            let background = value("--background").flatMap { UInt32($0, radix: 16) } ?? 0x000000
            let opacity = Double(value("--marks-opacity") ?? "") ?? 1
            config.customiseTheme {
                $0 = .custom(background: RGBA(hex: background), marks: RGBA(hex: marks, alpha: opacity), accent: $0.accent)
            }
        }
        if backdrop != nil {
            config.customiseTheme { _ in }
            config.backdropName = "preview"
        }
        if let years = Int(value("--block-years") ?? "") { config.budget.groupsPerBlock = years }
        if let perRow = Int(value("--blocks-per-row") ?? "") { config.budget.blocksPerRow = perRow }
        config.blacksOutMenuBar = arguments.contains("--black-menu-bar")
        config.connectsElapsedMarks = !arguments.contains("--no-connect")
        if let text = value("--birth") {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 {
                var components = DateComponents()
                components.year = parts[0]
                components.month = parts[1]
                components.day = parts[2]
                config.birthDate = calculator.calendar.date(from: components)
            }
        }

        let progress = calculator.progress(
            for: Date(), mode: config.mode, birthDate: config.birthDate, lifespanYears: config.lifespanYears
        )
        let canvas = CanvasSpec(
            pixelWidth: width, pixelHeight: height, scale: scale, appearance: appearance
        )

        do {
            let data = try WallpaperRenderer().pngData(
                config: config, progress: progress, canvas: canvas, backdrop: backdrop
            )
            try data.write(to: output)
            print("\(output.path)  \(width)x\(height)  \(progress.summary)  "
                + "\(config.patternID)/\(appearance.rawValue)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("preview failed: \(error)\n".utf8))
            return 1
        }
    }
}
