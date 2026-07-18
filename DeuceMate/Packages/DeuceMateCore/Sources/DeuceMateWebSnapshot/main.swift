// main.swift — DeuceMateWebSnapshot: headless renderer for a local HTML file
// (used for the interactive match web export, see WebExport/MatchHTMLExporter),
// producing PNG screenshots for documentation/marketing without needing macOS
// Screen Recording permission. It renders in-process via WKWebView's own
// view snapshot, not a display capture, so no TCC permission is required.
// macOS-only — not part of the iOS/watchOS app targets.
import AppKit
import WebKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// Usage: DeuceMateWebSnapshot <html-or-txt-file> <output-dir> [width] [height] [step-1 step-2 ...]
// Each step is either a button label (clicks the first <button> whose text
// matches it, simulating a real user tab switch) or "scroll:<0-100>" (scrolls
// to that percentage of the page's scroll height) before taking that shot; the
// first shot (before any step) is always captured as "00-default.png". A
// ".txt" input is wrapped in a simple styled dark page first (monospace
// <pre>), so plain text (e.g. a captured AI-coach prompt) gets a presentable
// screenshot without needing its own HTML.
guard CommandLine.arguments.count >= 3 else {
    fail("Usage: DeuceMateWebSnapshot <html-or-txt-file> <output-dir> [width] [height] [steps...]")
}

let inputPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
let width = CommandLine.arguments.count >= 4 ? (Double(CommandLine.arguments[3]) ?? 1400) : 1400
let height = CommandLine.arguments.count >= 5 ? (Double(CommandLine.arguments[4]) ?? 1000) : 1000
let steps = CommandLine.arguments.count >= 6 ? Array(CommandLine.arguments[5...]) : []

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func htmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func wrappedTextPage(for text: String) -> String {
    """
    <!doctype html><html><head><meta charset="utf-8"><style>
      body { margin: 0; background: #0b0f14; color: #e6edf3; }
      pre {
        font: 15px/1.6 -apple-system, ui-monospace, Menlo, monospace;
        white-space: pre-wrap; word-wrap: break-word;
        padding: 32px 40px; margin: 0;
      }
    </style></head><body><pre>\(htmlEscaped(text))</pre></body></html>
    """
}

let htmlPath: String
if inputPath.lowercased().hasSuffix(".txt") {
    let text = (try? String(contentsOf: URL(fileURLWithPath: inputPath), encoding: .utf8)) ?? ""
    let wrapped = URL(fileURLWithPath: outputDir).appendingPathComponent("_wrapped-input.html")
    do {
        try wrappedTextPage(for: text).write(to: wrapped, atomically: true, encoding: .utf8)
    } catch {
        fail("Could not write wrapped text page: \(error.localizedDescription)")
    }
    htmlPath = wrapped.path
} else {
    htmlPath = inputPath
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
let window = NSWindow(
    contentRect: webView.frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
window.contentView = webView
window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
window.orderFront(nil)

final class NavDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("Navigation failed: \(error.localizedDescription)")
    }
}
let navDelegate = NavDelegate()
webView.navigationDelegate = navDelegate

func snapshot(name: String, completion: @escaping () -> Void) {
    let config = WKSnapshotConfiguration()
    config.rect = webView.bounds
    webView.takeSnapshot(with: config) { image, error in
        if let error {
            fail("Snapshot '\(name)' failed: \(error.localizedDescription)")
        }
        guard let image, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fail("Snapshot '\(name)' produced no image data")
        }
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
        do {
            try png.write(to: url)
            print("Wrote \(url.path)")
        } catch {
            fail("Could not write \(url.path): \(error.localizedDescription)")
        }
        completion()
    }
}

func clickButton(labeled label: String, then completion: @escaping () -> Void) {
    let escaped = label.replacingOccurrences(of: "'", with: "\\'")
    let js = "Array.from(document.querySelectorAll('button')).some(b => b.textContent.trim() === '\(escaped)' && (b.click(), true))"
    webView.evaluateJavaScript(js) { result, error in
        if let error {
            fail("Could not click button '\(label)': \(error.localizedDescription)")
        }
        if (result as? Bool) != true {
            fail("No button labeled '\(label)' was found")
        }
        // Let the re-render (and any chart/SVG rebuild) settle before the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: completion)
    }
}

func scroll(toPercent percent: Double, then completion: @escaping () -> Void) {
    let js = "window.scrollTo(0, Math.max(0, (document.body.scrollHeight - window.innerHeight) * \(percent) / 100))"
    webView.evaluateJavaScript(js) { _, error in
        if let error {
            fail("Could not scroll to \(percent)%: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: completion)
    }
}

func runSteps(_ steps: [String]) {
    var remaining = steps
    func step(index: Int) {
        if index == 0 {
            snapshot(name: "00-default.png") { step(index: 1) }
            return
        }
        guard !remaining.isEmpty else { exit(0) }
        let instruction = remaining.removeFirst()
        let shotName = String(format: "%02d-%@.png", index, instruction.lowercased().replacingOccurrences(of: ":", with: "-"))
        if instruction.hasPrefix("scroll:"), let percent = Double(instruction.dropFirst("scroll:".count)) {
            scroll(toPercent: percent) {
                snapshot(name: shotName) { step(index: index + 1) }
            }
        } else {
            clickButton(labeled: instruction) {
                snapshot(name: shotName) { step(index: index + 1) }
            }
        }
    }
    step(index: 0)
}

navDelegate.onFinish = {
    // Give the page's own JS a moment to finish building the interactive
    // chart/SVG before the first capture.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        runSteps(steps)
    }
}

webView.loadFileURL(
    URL(fileURLWithPath: htmlPath),
    allowingReadAccessTo: URL(fileURLWithPath: htmlPath).deletingLastPathComponent()
)

app.run()
