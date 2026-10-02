import AgentUsageCore
import AppKit
import SwiftUI

/// Runs the menu bar app, or renders the README screenshot when asked to.
@main
enum Launcher {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-readme-screenshot") {
            let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "docs/screenshot.png"
            let rendered = MainActor.assumeIsolated { ReadmeScreenshot.render(to: path) }
            exit(rendered ? 0 : 1)
        }
        AgentUsageApp.main()
    }
}

struct AgentUsageApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item: Claude mark plus `session% · weekly%` used, red once a window passes 90%.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Image(nsImage: rendered)
            .task { store.start() }
    }

    private var text: String? {
        guard let session = store.session else { return nil }
        guard let weekly = store.weekly else { return "\(session.usedPercent)%" }
        return "\(session.usedPercent)% · \(weekly.usedPercent)%"
    }

    /// The menu bar only honours color for non-template images, so the label is drawn to an image:
    /// a template while normal (macOS tints it for the menu bar) and red when critical.
    private var rendered: NSImage {
        let critical = store.isCritical
        let content = HStack(spacing: 4) {
            if let mark = ClaudeMark.template {
                Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 14, height: 14)
            }
            if let text {
                Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(critical ? Theme.urgent : .black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = !critical
        return image
    }
}
