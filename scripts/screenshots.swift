// Renders App Store screenshots into docs/screenshots/ at 2880×1800.
// Run: swift scripts/screenshots.swift (from the repo root, after ./build.sh for docs/AppIcon.icns).
import AppKit
import SwiftUI

let size = CGSize(width: 1440, height: 900)

func appIcon(_ id: String) -> NSImage {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
}

struct Desktop<Content: View>: View {
    let headline: String, sub: String
    var leading = false
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.31, green: 0.27, blue: 0.9), Color(red: 0.58, green: 0.2, blue: 0.92)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Spacer()
                    Image(nsImage: NSImage(contentsOfFile: "docs/icon-dark.png")!).resizable().frame(width: 18, height: 18)
                        .padding(4).background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.25)))
                    Image(systemName: "wifi"); Image(systemName: "battery.100")
                    Text("Tue 9:41 AM")
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 30).background(.black.opacity(0.18))
                if leading {
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(headline).font(.system(size: 46, weight: .bold))
                            Text(sub).font(.system(size: 22)).opacity(0.85)
                        }
                        .foregroundStyle(.white).frame(width: 640, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 110)
                        content
                    }
                } else {
                    VStack(spacing: 10) {
                        Text(headline).font(.system(size: 46, weight: .bold))
                        Text(sub).font(.system(size: 22)).opacity(0.85)
                    }
                    .foregroundStyle(.white).padding(.top, 70)
                    content.frame(maxHeight: .infinity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(28).frame(width: 520, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white).shadow(color: .black.opacity(0.25), radius: 30, y: 12))
    }
}

let rich = Card(title: "Copied in Slack") {
    VStack(alignment: .leading, spacing: 10) {
        Text("Picnic plan for **Saturday**").font(.system(size: 20))
        ForEach(["bring the **red blanket**", "pack sandwiches", "pick a few games"], id: \.self) { item in
            HStack(alignment: .top, spacing: 10) { Text("•"); Text(.init(item)) }.font(.system(size: 20))
        }
        HStack(alignment: .top, spacing: 10) { Text("◦"); Text("frisbee") }.font(.system(size: 20)).padding(.leading, 26)
        Text("Weather: [forecast](https://example.com)").font(.system(size: 20))
    }
    .foregroundStyle(Color(white: 0.1))
}

let markdown = Card(title: "Pasted in your editor") {
    Text("""
    Picnic plan for **Saturday**

    - bring the **red blanket**
    - pack sandwiches
    - pick a few games
      - frisbee

    Weather: [forecast](https://example.com)
    """)
    .font(.system(size: 18, design: .monospaced)).foregroundStyle(Color(white: 0.15))
    .padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.95)))
}

struct MenuRow: View {
    let title: String
    var checked = false, icon: NSImage? = nil, dim = false, shortcut = ""
    var body: some View {
        HStack(spacing: 8) {
            Text(checked ? "✓" : " ").frame(width: 14)
            if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(title).foregroundStyle(dim ? .secondary : .primary)
            Spacer()
            Text(shortcut).foregroundStyle(.secondary)
        }
        .font(.system(size: 15)).padding(.horizontal, 12).frame(height: 28)
    }
}

let menu = VStack(alignment: .leading, spacing: 0) {
    MenuRow(title: "Enabled", checked: true)
    Divider().padding(.vertical, 5)
    MenuRow(title: "Watched apps (click to remove)", dim: true)
    MenuRow(title: "Slack", checked: true, icon: appIcon("com.tinyspeck.slackmacgap"))
    MenuRow(title: "Notion", checked: true, icon: appIcon("notion.id"))
    MenuRow(title: "Watch Xcode", icon: appIcon("com.apple.dt.Xcode"))
    Divider().padding(.vertical, 5)
    MenuRow(title: "Launch at Login", checked: true)
    MenuRow(title: "Quit", shortcut: "⌘Q")
}
.padding(.vertical, 6).frame(width: 330)
.background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.97)).shadow(color: .black.opacity(0.3), radius: 24, y: 10))

let shots: [(String, AnyView)] = [
    ("1-before-after", AnyView(Desktop(headline: "Copy formatted. Paste Markdown.",
                                       sub: "Clip.md rewrites what you copy from Slack and Notion so it pastes cleanly into code editors.") {
        HStack(spacing: 40) {
            rich
            Image(systemName: "arrow.right").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            markdown
        }
    })),
    ("2-menu", AnyView(Desktop(headline: "You choose which apps it watches.",
                               sub: "Lives in the menu bar. Everything else on the clipboard stays exactly as copied.", leading: true) {
        // Drops from the status icon, which sits ~200pt from the right edge.
        menu.padding(.top, 4).padding(.trailing, 190)
    })),
]

try! FileManager.default.createDirectory(atPath: "docs/screenshots", withIntermediateDirectories: true)
MainActor.assumeIsolated {
  for (name, view) in shots {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
    r.scale = 2
    let rep = NSBitmapImageRep(cgImage: r.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/screenshots/\(name).png"))
    print("docs/screenshots/\(name).png", rep.pixelsWide, "x", rep.pixelsHigh)
}
}
