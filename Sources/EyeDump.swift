import AppKit

/// `CGWindowListCreateImage` is obsoleted for macOS 15+ targets in the SDK but still present at runtime; resolved
/// by name so the 26.0 target builds. A ScreenCaptureKit migration would replace this.
private func legacyWindowListImage(_ rect: CGRect, _ list: CGWindowListOption, _ window: CGWindowID, _ options: CGWindowImageOption) -> CGImage? {
    typealias Function = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
    return unsafeBitCast(symbol, to: Function.self)(rect, list, window, options)?.takeRetainedValue()
}

/// `--eye-dump <outdir>`: saves PNGs of the app's own windows for repeatable visual review, then quits.
extension AppDelegate {
    /// The dump draws on the live canvas and quits clean, which would delete the real recovery file,
    /// so the flag is ignored unless SKITCH_APP_SUPPORT points at an isolated directory.
    static func eyeDumpDirectory(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let args = arguments
        guard let flag = args.firstIndex(of: "--eye-dump"), args.indices.contains(flag + 1) else { return nil }
        var isDirectory: ObjCBool = false
        guard let support = environment["SKITCH_APP_SUPPORT"], !support.isEmpty,
              FileManager.default.fileExists(atPath: support, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: args[flag + 1], isDirectory: true)
    }

    func runEyeDump(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func pump(_ seconds: TimeInterval = 0.5) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
        func shoot(_ name: String, _ target: NSWindow?) {
            guard let target else { return }
            pump()
            target.contentView?.layoutSubtreeIfNeeded()
            let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
            if let image = legacyWindowListImage(.null, .optionIncludingWindow, CGWindowID(target.windowNumber), options),
               image.width > 1, image.height > 1,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: dir.appendingPathComponent(name + ".png")); return
            }
            guard let view = target.contentView?.superview ?? target.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + "-cachedisplay.png"))
        }

        shoot("1-default", window)

        let defaultFrame = window.frame
        window.setContentSize(window.contentMinSize)
        shoot("2-minsize", window)
        window.setFrame(defaultFrame, display: true)

        enterFrame(keepingAnnotations: false, manualFlags: [])
        shoot("3-frame", window)
        leaveFrame()
        window.setFrame(defaultFrame, display: true)

        showPreferences()
        shoot("4-preferences", preferencesWindow)
        closePreferences()

        let red = SketchColor(.systemRed)
        var arrow = SketchElement(kind: .arrow); arrow.points = [CGPoint(x: 40, y: 60), CGPoint(x: 220, y: 140)]; arrow.color = red
        var box = SketchElement(kind: .rectangle); box.rect = CGRect(x: 120, y: 200, width: 200, height: 110); box.color = red
        var note = SketchElement(kind: .text); note.text = "Eye dump"; note.rect = CGRect(x: 60, y: 340, width: 220, height: 40); note.color = red
        canvas.document.elements.append(contentsOf: [arrow, box, note])
        canvas.selection = [box.id]
        canvas.needsDisplay = true
        window.makeKeyAndOrderFront(nil)
        shoot("5-annotations-selected", window)

        dirty = false
        NSApp.terminate(nil)
    }
}
