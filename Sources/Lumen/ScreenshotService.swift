import AppKit

/// Silent screenshot capture. Uses the macOS `screencapture` tool with `-x`
/// (no shutter sound) and `-i` (interactive region/window selection).
/// Returns the image as base64 PNG for the vision model.
enum ScreenshotService {
    /// Interactive: user drags to select a region (or presses Space for a
    /// window, Esc to cancel). Silent — no sound, no saved file left behind.
    static func captureInteractive(completion: @escaping (String?) -> Void) {
        capture(interactive: true, completion: completion)
    }

    /// Full screen, no interaction.
    static func captureFullScreen(completion: @escaping (String?) -> Void) {
        capture(interactive: false, completion: completion)
    }

    private static func capture(interactive: Bool, completion: @escaping (String?) -> Void) {
        let tmp = NSTemporaryDirectory() + "lumen-shot-\(UUID().uuidString).png"

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -x: silent, -o: no window shadow, -i: interactive selection.
            task.arguments = interactive ? ["-x", "-o", "-i", tmp] : ["-x", tmp]

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Interactive capture is cancelled → no file written.
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: tmp)) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let downsized = downscale(data) ?? data
            try? FileManager.default.removeItem(atPath: tmp)

            let base64 = downsized.base64EncodedString()
            DispatchQueue.main.async { completion(base64) }
        }
    }

    /// Vision models cap resolution; shrink large captures to keep the request
    /// small and fast (longest side ≤ 1600px).
    private static func downscale(_ data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return data }

        let scale = maxSide / longest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return data }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func nsImage(fromBase64 base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
