import AppKit

extension AppDelegate {
    /// Frame mode already shows and hides Cancel in AppDelegate; the chrome mirrors it into the glass layer.
    func setModernFrameMode(_ on: Bool) {
        if #available(macOS 26, *) { (modernChrome as? ModernEditorChrome)?.frameMode = on }
    }

    /// The Drag Me thumbnail doubles as the canvas bleed under the rails.
    func feedCanvasBleed() {
        if #available(macOS 26, *) { (modernChrome as? ModernEditorChrome)?.updateCanvasBleed(dragExportView?.overview) }
    }

    /// What this process's window is built from, so tools/test-native-startup.py can tell a pinned appearance
    /// that really produced its chrome from one that silently fell back.
    func appearanceEvidence() -> [String: Any] {
        var glassSurfaces = 0
        if #available(macOS 26, *) {
            func count(_ view: NSView) {
                if view is NSGlassEffectView { glassSurfaces += 1 }
                view.subviews.forEach(count)
            }
            if let content = window.contentView { count(content) }
        }
        return ["style": Appearance.current.rawValue, "modernChrome": modernChrome != nil,
                "toolButtonClass": toolButtons[.brush].map { String(describing: type(of: $0)) } ?? "none",
                "glassSurfaces": glassSurfaces]
    }
}

@available(macOS 26, *)
extension AppDelegate {
    /// The Modern counterpart of buildWindow(): the same controls and behaviors, laid out by ModernEditorChrome.
    /// Classic's size constraints are not copied; the chrome sizes the shared controls and owns the canvas border.
    func buildModernWindowContent() {
        FontAwesomeFont.registerBundledFonts()
        let content = FrameChromeView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = content
        let toolbox = bezelToolbox()

        colorWell.color = OriginalDrawingControls.presets[0].color; colorWell.target = self; colorWell.action = #selector(changeColor(_:))
        paletteButton.font = .systemFont(ofSize: 18); paletteButton.target = self; paletteButton.action = #selector(showDrawingColors(_:))
        paletteButton.imagePosition = .imageLeading; paletteButton.setAccessibilityLabel("Drawing colors")
        paletteButton.toolTip = "Hover for original preset colors; hold Shift to change the canvas background"
        paletteButton.onHover = { [weak self] inside in self?.drawingColorHover(inside, palette: false) }
        sizeLabel.font = .systemFont(ofSize: 18)
        widthControl.target = self; widthControl.action = #selector(changeWidth(_:))
        widthControl.onBegin = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return false }
            self.canvas.editingUndoManager.beginUndoGrouping(); self.sizeUndoGrouping = true; return true
        }
        widthControl.onEnd = { [weak self] in self?.endDrawingSizeGesture() }
        dragOriginalControl.title = "Original size"; dragOriginalControl.font = .systemFont(ofSize: 18)
        dragOriginalControl.target = self; dragOriginalControl.action = #selector(changeDragOptions(_:))
        dragOriginalControl.state = (UserDefaults.standard.object(forKey: "DragOriginalSize") as? Bool ?? true) ? .on : .off
        dragOriginalControl.setAccessibilityLabel("Drag out at original size")
        nameField.font = .systemFont(ofSize: 20); nameField.placeholderString = "Image name"
        zoomControl.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        for (index, item) in zoomControl.itemArray.enumerated() { item.representedObject = [0.25, 0.5, 0.75, 1, 1.5, 2][index] }
        zoomControl.selectItem(withTitle: "100%"); zoomControl.font = .systemFont(ofSize: 18)
        zoomControl.target = self; zoomControl.action = #selector(changeZoom(_:)); zoomControl.setAccessibilityLabel("Canvas zoom")
        let drag = DragExportView(); dragExportView = drag
        drag.drawsBackground = false
        configureDragExport(drag)
        dragFormatControl.addItems(withTitles: ["PNG", "JPEG 100%", "JPEG 80%", "JPEG 60%", "JPEG 30%", "JPEG 10%", "TIFF", "GIF", "BMP", "PDF", "SVG", "Skitch"])
        dragFormatControl.font = .systemFont(ofSize: 20)
        dragFormatControl.setAccessibilityLabel("Drag Me format")
        for item in dragFormatControl.itemArray { item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 20)]) }
        dragFormatControl.target = self; dragFormatControl.action = #selector(changeDragOptions(_:))
        let choice = UserDefaults.standard.integer(forKey: "DragFormatChoice")
        dragFormatControl.selectItem(at: (0..<dragFormatControl.numberOfItems).contains(choice) ? choice : 0)
        dragSizeLabel.font = .systemFont(ofSize: 18); dragSizeLabel.lineBreakMode = .byTruncatingTail
        status.font = .systemFont(ofSize: 18); status.lineBreakMode = .byTruncatingTail

        let controls = ModernEditorChrome.SharedControls(
            canvas: canvas, canvasBorder: canvasBorder, nameField: nameField, status: status, sizeLabel: sizeLabel,
            widthControl: widthControl, paletteButton: paletteButton, zoomControl: zoomControl, dragFormatControl: dragFormatControl,
            dragOriginalControl: dragOriginalControl, dragSizeLabel: dragSizeLabel, dragExportView: drag, toolbox: toolbox,
            brandLogo: recoveredImage("OpenSkitch"))
        let actions = ModernEditorChrome.Actions(
            target: self, hide: #selector(vanish), photos: #selector(showPhotos), saveHistory: #selector(saveHistory),
            showHistory: #selector(showHistory), chooseTool: #selector(chooseTool(_:)), snap: #selector(snapButtonPressed),
            cancelFrame: #selector(cancelFrame), font: #selector(chooseFont), undo: #selector(undo),
            wipe: #selector(wipe), actualSize: #selector(toggleActualSize), resize: #selector(resize), share: #selector(share(_:)))
        let originalToolOrder: [SketchTool] = [.select, .brush, .line, .ellipse, .rectangle, .fill, .eraser, .text, .arrow]
        let chrome = ModernEditorChrome(controls: controls, actions: actions, toolOrder: (originalToolOrder + [.crop]).map(\.rawValue))
        chrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor), chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: content.topAnchor), chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.canvasScrollView = chrome.scrollView
        modernChrome = chrome
        configureWebpostButton(chrome.shareButton)

        snapButton = chrome.snapButton; cancelFrameButton = chrome.cancelFrameButton
        actualButton = chrome.actualButton; resizeButton = chrome.resizeButton
        chrome.snapButton.alternateTarget = self
        chrome.snapButton.alternateAction = #selector(fullscreenSnap)
        for tool in SketchTool.allCases {
            guard let button = chrome.toolButtons[tool.rawValue] else { continue }
            toolButtons[tool] = button
            trackHint(button, owner: "tool-" + tool.rawValue) { OriginalHintMessages.hover(tool: tool) }
        }
        trackHint(chrome.wipeButton, owner: "wipe") { OriginalHintMessages.hover(actionTag: 50) }
        trackHint(widthControl, owner: "drawing-size") { OriginalHintMessages.hover(actionTag: 20) }

        wireEditorChrome(scroll: chrome.scrollView)
        setTool(.arrow)
    }
}
