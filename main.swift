import AppKit
import ServiceManagement

// MARK: HTML → Markdown

let blockTags: Set = ["div", "p", "ul", "ol", "li", "pre", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6", "table", "tr", "hr"]

func name(_ n: XMLNode) -> String { n.name?.lowercased() ?? "" }
func attr(_ n: XMLNode, _ a: String) -> String? { (n as? XMLElement)?.attribute(forName: a)?.stringValue }

func markdown(fromHTML html: String) -> String? {
    guard let doc = try? XMLDocument(xmlString: "<html><body>\(html)</body></html>", options: [.documentTidyHTML]),
          let body = try? doc.nodes(forXPath: "//body").first
    else { return nil }
    return blocks(body.children ?? [], sep: "\n\n")
}

func blocks(_ nodes: [XMLNode], sep: String) -> String {
    var out: [String] = []
    var run = ""
    func flush() {
        let t = run.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { out.append(t) }
        run = ""
    }
    for n in nodes {
        if n.kind == .element, blockTags.contains(name(n)) {
            flush()
            let b = block(n)
            if !b.isEmpty { out.append(b) }
        } else {
            run += inline(n)
        }
    }
    flush()
    return out.joined(separator: sep)
}

func block(_ e: XMLNode) -> String {
    let kids = e.children ?? []
    switch name(e) {
    case "ul", "ol":
        let ordered = name(e) == "ol"
        var i = Int(attr(e, "start") ?? "") ?? 1
        var items: [[XMLNode]] = []
        for li in kids where name(li) == "li" {
            let nodes = li.children ?? []
            // Google Docs puts a sublist beside the <li> it belongs to; tidy wraps it in a bare <li>.
            let sublist = nodes.allSatisfy { $0.kind == .element ? ["ul", "ol"].contains(name($0)) : raw($0).allSatisfy(\.isWhitespace) }
                && nodes.contains { $0.kind == .element }
            if sublist, !items.isEmpty {
                items[items.count - 1] += nodes
            } else {
                items.append(nodes)
            }
        }
        return items.map { nodes in
            let marker = ordered ? "\(i). " : "- "
            i += 1
            let pad = String(repeating: " ", count: marker.count)
            let loose = nodes.filter { name($0) == "p" }.count > 1
            let lines = blocks(nodes, sep: loose ? "\n\n" : "\n").split(separator: "\n", omittingEmptySubsequences: false)
            return marker + lines.enumerated().map { $0 == 0 || $1.isEmpty ? String($1) : pad + $1 }.joined(separator: "\n")
        }.joined(separator: "\n")
    case "hr":
        return "---"
    case "pre":
        return "```\n" + raw(e).trimmingCharacters(in: .newlines) + "\n```"
    case "blockquote":
        return blocks(kids, sep: "\n\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    case let h where h.count == 2 && h.first == "h":
        // Notion wraps heading text in <strong>; headings are already bold.
        var text = blocks(kids, sep: " ")
        if text.hasPrefix("**"), text.hasSuffix("**"), text.count > 4, !text.dropFirst(2).dropLast(2).contains("**") {
            text = String(text.dropFirst(2).dropLast(2))
        }
        return String(repeating: "#", count: Int(h.dropFirst()) ?? 1) + " " + text
    default:
        return blocks(kids, sep: "\n\n")
    }
}

func inline(_ n: XMLNode) -> String {
    if n.kind == .text {
        return (n.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    guard n.kind == .element else { return "" }
    let inner = { (n.children ?? []).map(inline).joined() }
    switch name(n) {
    case "br": return "\n"
    case "b", "strong":
        // Google Docs wraps the whole copy in <b style="font-weight:normal">.
        let style = (attr(n, "style") ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        return style.contains("font-weight:normal") || style.contains("font-weight:400") ? inner() : wrap(inner(), "**")
    case "i", "em": return wrap(inner(), "_")
    case "s", "strike", "del": return wrap(inner(), "~~")
    case "code": return wrap(raw(n), "`")
    case "img": return attr(n, "alt") ?? ""
    case "a":
        let text = inner(), href = attr(n, "href") ?? ""
        if href.isEmpty || text == href || "mailto:" + text == href { return text }
        return "[\(text)](\(href))"
    case "span":
        let style = (attr(n, "style") ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        var s = inner()
        if style.contains("font-weight:bold") || style.contains("font-weight:700") { s = wrap(s, "**") }
        if style.contains("font-style:italic") { s = wrap(s, "_") }
        if style.contains("line-through") { s = wrap(s, "~~") }
        return s
    default:
        return blockTags.contains(name(n)) ? blocks([n], sep: "") : inner()
    }
}

/// Keeps surrounding whitespace outside the markers — `** x **` isn't emphasis.
func wrap(_ s: String, _ m: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return s }
    let lead = s.prefix { $0.isWhitespace }, trail = String(s.reversed().prefix { $0.isWhitespace }.reversed())
    return lead + m + t + m + trail
}

func raw(_ n: XMLNode) -> String {
    if n.kind == .text { return n.stringValue ?? "" }
    if name(n) == "br" { return "\n" }
    return (n.children ?? []).map(raw).joined()
}

// MARK: Chromium web custom data

/// Decodes Chromium's `org.chromium.web-custom-data` pickle: a header, a count, then
/// (type, value) pairs of UTF-16LE strings, each length-prefixed and padded to 4 bytes.
func webCustomData(_ d: Data) -> [String: String] {
    let b = [UInt8](d)
    var o = 4, out: [String: String] = [:]
    func u32() -> Int? {
        guard o + 4 <= b.count else { return nil }
        defer { o += 4 }
        return Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
    }
    func s16() -> String? {
        guard let n = u32(), o + n * 2 <= b.count else { return nil }
        defer { o += (n * 2 + 3) & ~3 }
        return String(data: Data(b[o ..< o + n * 2]), encoding: .utf16LittleEndian)
    }
    guard let count = u32() else { return out }
    for _ in 0 ..< count {
        guard let k = s16(), let v = s16() else { break }
        out[k] = v
    }
    return out
}

/// Slack escapes punctuation (`\~30 min`); drop the backslashes so it matches the HTML path.
/// Code fences and inline code keep theirs.
func unescape(_ md: String) -> String {
    var fenced = false
    return md.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        if line.hasPrefix("```") { fenced.toggle(); return String(line) }
        if fenced { return String(line) }
        return line.split(separator: "`", omittingEmptySubsequences: false).enumerated().map { i, seg in
            i % 2 == 1 ? String(seg) : seg.replacingOccurrences(of: #"\\([!-/:-@\[-`{-~])"#, with: "$1", options: .regularExpression)
        }.joined(separator: "`")
    }.joined(separator: "\n")
}

func markdown(fromWebCustomData d: Data) -> String? {
    let custom = webCustomData(d)
    return custom["text/markdown"].map(unescape) ?? custom["slack/texty"].flatMap(markdown(fromTexty:))
}

// MARK: Slack composer (Quill Delta)

/// Copying from Slack's composer yields only `slack/texty`, a Quill Delta: text runs carry
/// inline attributes, and each "\n" carries the block attributes of the line it ends.
func markdown(fromTexty json: String) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let ops = root["ops"] as? [[String: Any]]
    else { return nil }
    var lines: [(text: String, attrs: [String: Any])] = []
    var line = ""
    for op in ops {
        let attrs = op["attributes"] as? [String: Any] ?? [:]
        if let s = op["insert"] as? String {
            for (i, part) in s.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if i > 0 { lines.append((line, attrs)); line = "" }
                line += styled(String(part), attrs)
            }
        } else if let embed = (op["insert"] as? [String: Any])?.values.first as? [String: Any] {
            line += embed["text"] as? String ?? embed["label"] as? String ?? ""
        }
    }
    if !line.isEmpty { lines.append((line, [:])) }

    var out: [String] = [], counters: [Int] = [], pads = [0]
    var inList = false, fenced = false
    for (text, a) in lines {
        if (a["code-block"] != nil) != fenced { out.append("```"); fenced.toggle() }
        if fenced { out.append(text); continue }
        guard let list = a["list"] as? String else {
            if inList, !text.isEmpty { out.append("") }
            inList = false
            counters = []
            out.append(a["blockquote"] != nil ? "> " + text : text)
            continue
        }
        if !inList, out.last?.isEmpty == false { out.append("") }
        inList = true
        let depth = a["indent"] as? Int ?? 0
        counters = Array(counters.prefix(depth + 1)) + Array(repeating: 0, count: max(0, depth + 1 - counters.count))
        counters[depth] += 1
        while pads.count <= depth { pads.append(pads.last! + 2) }
        let marker = list == "ordered" ? "\(counters[depth]). " : "- "
        out.append(String(repeating: " ", count: pads[depth]) + marker + text)
        pads = Array(pads.prefix(depth + 1)) + [pads[depth] + marker.count]
    }
    if fenced { out.append("```") }
    return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
}

func styled(_ s: String, _ a: [String: Any]) -> String {
    guard !s.isEmpty else { return s }
    if a["code"] != nil { return wrap(s, "`") }
    var t = s
    let url = (a["slackslug"] as? [String: Any])?["url"] as? String ?? a["link"] as? String
    if let url { t = url == s || url.hasSuffix("://" + s) ? url : "[\(s)](\(url))" }
    if a["strike"] != nil { t = wrap(t, "~~") }
    if a["italic"] != nil { t = wrap(t, "_") }
    if a["bold"] != nil { t = wrap(t, "**") }
    return t
}

/// Clipboard symbol with ".md" over its lower right.
let icon: NSImage = {
    let clip = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))!
    let font = NSFont.systemFont(ofSize: 9, weight: .heavy)
    let img = NSImage(size: NSSize(width: 22, height: clip.size.height), flipped: false) { r in
        clip.draw(in: NSRect(origin: .zero, size: clip.size))
        let text = NSAttributedString(string: ".md", attributes: [.font: font, .kern: -0.3])
        let at = NSPoint(x: r.maxX - text.size().width, y: 0)
        // Knock a halo out of the clipboard so the text reads as sitting on top of it.
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setBlendMode(.clear)
        // Stamped around a ring, not stroked: a stroke wider than the dot glyph leaves a hole beside it.
        for i in 0..<16 {
            let a = Double(i) * .pi / 8
            text.draw(at: NSPoint(x: at.x + 1.5 * cos(a), y: at.y + 1.5 * sin(a)))
        }
        ctx.setBlendMode(.normal)
        text.draw(at: at)
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Clip.md"
    return img
}()

func png(size: NSSize, to path: String, draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.current?.flushGraphics()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

extension NSColor {
    convenience init(hex: String) {
        let v = Int(hex.trimmingCharacters(in: ["#"]), radix: 16) ?? 0
        self.init(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Clipboard watcher

let plain = NSPasteboard.PasteboardType("public.utf8-plain-text")
let chromiumCustom = NSPasteboard.PasteboardType("org.chromium.web-custom-data")

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let pb = NSPasteboard.general
    lazy var seen = pb.changeCount
    var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "disabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "disabled"); refresh() }
    }
    var watched: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watched") ?? ["com.tinyspeck.slackmacgap", "notion.id"] }
        set { UserDefaults.standard.set(newValue, forKey: "watched") }
    }

    func applicationDidFinishLaunching(_: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    func refresh() {
        item.button?.image = icon
        item.button?.appearsDisabled = !enabled
    }


    // Status-item menus don't activate this app, so the frontmost app is still the one the user came from.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Enabled", action: #selector(toggle), keyEquivalent: "").state = enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Watched apps", action: nil, keyEquivalent: "")
        for id in watched {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let mi = menu.addItem(withTitle: url?.deletingPathExtension().lastPathComponent ?? id,
                                  action: #selector(unwatch), keyEquivalent: "")
            mi.representedObject = id
            mi.state = .on
            mi.image = url.map { menuIcon(NSWorkspace.shared.icon(forFile: $0.path)) }
        }
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
           id != Bundle.main.bundleIdentifier, !watched.contains(id) {
            let mi = menu.addItem(withTitle: "Watch \(front.localizedName ?? id)", action: #selector(watch), keyEquivalent: "")
            mi.representedObject = id
            mi.image = front.icon.map(menuIcon)
        }
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.image = NSImage(systemSymbolName: "person.badge.clock", accessibilityDescription: nil)
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q").image =
            NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        for mi in menu.items where mi.action != nil && mi.action != #selector(NSApp.terminate) { mi.target = self }
    }

    func menuIcon(_ img: NSImage) -> NSImage {
        let copy = img.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    @objc func toggle() { enabled.toggle() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    @objc func watch(_ mi: NSMenuItem) { watched.append(mi.representedObject as! String) }
    @objc func unwatch(_ mi: NSMenuItem) { watched.removeAll { $0 == mi.representedObject as? String } }

    func poll() {
        guard pb.changeCount != seen else { return }
        seen = pb.changeCount
        // Google Docs lives in a browser, so it's recognized by the marker in its HTML rather than by app.
        guard enabled, NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(watched.contains) == true
            || pb.string(forType: .html)?.contains("docs-internal-guid-") == true else { return }
        rewrite()
    }

    /// Pasteboard items can't be edited in place, so every type's bytes are copied
    /// verbatim into fresh items and only the plain-text flavor is swapped.
    func rewrite() {
        guard let items = pb.pasteboardItems, !items.isEmpty else { return }
        var changed = false
        let fresh = items.map { old -> NSPasteboardItem in
            let new = NSPasteboardItem()
            // Slack's "Copy message" and composer copies have no HTML, only Chromium custom data.
            var md = old.data(forType: chromiumCustom).flatMap(markdown(fromWebCustomData:))
            if md == nil, let html = old.string(forType: .html) { md = markdown(fromHTML: html) }
            for t in old.types {
                if t == plain, let md, md != old.string(forType: plain) {
                    new.setString(md, forType: t)
                    changed = true
                } else if let d = old.data(forType: t) {
                    new.setData(d, forType: t)
                }
            }
            return new
        }
        guard changed else { return }
        pb.clearContents()
        pb.writeObjects(fresh)
        seen = pb.changeCount
    }
}

switch CommandLine.arguments.dropFirst().first {
case "--convert":
    print(markdown(fromHTML: String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)) ?? "")
    exit(0)
case "--convert-web-custom-data":
    print(markdown(fromWebCustomData: FileHandle.standardInput.readDataToEndOfFile()) ?? "")
    exit(0)
case "--icon":
    // --icon <out.png> <hex color>: README art, same drawing as the menubar.
    let args = CommandLine.arguments
    png(size: NSSize(width: icon.size.width * 8, height: icon.size.height * 8), to: args[2]) { rect in
        icon.draw(in: rect)
        NSColor(hex: args[3]).set()
        rect.fill(using: .sourceAtop)
    }
    exit(0)
case "--app-icon":
    // --app-icon <out.iconset>: Finder/App Store icon, the menubar glyph in white on a squircle.
    let dir = CommandLine.arguments[2]
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let glyph = NSImage(size: icon.size, flipped: false) { r in
        icon.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = CGFloat(pt * scale)
            png(size: NSSize(width: px, height: px), to: "\(dir)/icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png") { r in
                // Apple's macOS grid: 824/1024 body, 185/1024 corner radius.
                let body = r.insetBy(dx: px * 100 / 1024, dy: px * 100 / 1024)
                let path = NSBezierPath(roundedRect: body, xRadius: px * 185 / 1024, yRadius: px * 185 / 1024)
                NSGradient(starting: NSColor(hex: "4f46e5"), ending: NSColor(hex: "9333ea"))!.draw(in: path, angle: -60)
                let h = body.height * 0.62, w = h * icon.size.width / icon.size.height
                glyph.draw(in: NSRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h))
            }
        }
    }
    exit(0)
default: break
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
