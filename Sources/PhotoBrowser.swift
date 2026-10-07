import AppKit
import CoreFoundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

// Original Photos.html lists Pictures/iPhoto/Aperture; the recovered
// mediaBrowserView:shouldPreviewDoubleClickedItem: opens full-resolution files.
// Modern equivalents below browse only a chosen folder or picker-selected Photos.
struct PhotoBrowserEntry: Equatable, Sendable {
    let url: URL
    let typeIdentifier: String
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int
    var name: String { url.lastPathComponent }
    var displayWidth: Int { (5...8).contains(orientation) ? pixelHeight : pixelWidth }
    var displayHeight: Int { (5...8).contains(orientation) ? pixelWidth : pixelHeight }
}

enum PhotoBrowserCatalog {
    static func metadata(for url: URL, requireImageExtension: Bool = true) -> PhotoBrowserEntry? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        if requireImageExtension {
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return nil }
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let w = width.intValue, h = height.intValue
        guard w > 0, h > 0, w <= 65_536, h <= 65_536,
              Int64(w) * Int64(h) <= 268_435_456 else { return nil }
        // A header alone is not a valid image. Decode a bounded sample without
        // allocating a full-resolution bitmap during folder enumeration.
        let sample = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1,
                      kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, sample) != nil else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return PhotoBrowserEntry(url: url.standardizedFileURL, typeIdentifier: identifier,
                                 pixelWidth: w, pixelHeight: h,
                                 orientation: (1...8).contains(orientation) ? orientation : 1)
    }

    static func entries(from urls: [URL], isCancelled: () -> Bool = { false }) -> [PhotoBrowserEntry] {
        var seen = Set<URL>(), result: [PhotoBrowserEntry] = []
        for url in urls {
            if isCancelled() { return [] }
            let canonical = url.standardizedFileURL
            guard seen.insert(canonical).inserted, let entry = metadata(for: canonical) else { continue }
            result.append(entry)
        }
        // Stable, case-insensitive natural ordering independent of enumeration order.
        return result.sorted {
            let order = $0.name.compare($1.name, options: [.numeric, .caseInsensitive],
                                        locale: Locale(identifier: "en_US_POSIX"))
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }

    static func entries(in folder: URL, isCancelled: () -> Bool = { false }) throws -> [PhotoBrowserEntry] {
        guard folder.isFileURL else { throw PhotoBrowserFailure("Choose a local image folder.") }
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        // No recursion, library indexing, or following symlinks outside this folder.
        return entries(from: urls, isCancelled: isCancelled)
    }

    static func thumbnail(for entry: PhotoBrowserEntry, maximumPixelSize: Int = 256) -> CGImage? {
        guard (1...2048).contains(maximumPixelSize),
              let source = CGImageSourceCreateWithURL(entry.url as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true,
             kCGImageSourceCreateThumbnailWithTransform: true,
             kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
             kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

struct PhotoBrowserFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// NSItemProvider deletes its file when the completion returns. Copy immediately
// inside that completion, then retain this lease until synchronous onOpen returns.
final class PhotoBrowserTemporaryImport {
    let url: URL
    private let directory: URL
    private init(url: URL, directory: URL) { self.url = url; self.directory = directory }
    static func copyRepresentation(from source: URL) throws -> PhotoBrowserTemporaryImport {
        guard let metadata = PhotoBrowserCatalog.metadata(for: source, requireImageExtension: false) else {
            throw PhotoBrowserFailure("The selected item is not a supported, readable photo.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkitchPhoto-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            let ext = UTType(metadata.typeIdentifier)?.preferredFilenameExtension ?? "png"
            let destination = directory.appendingPathComponent("Selected Photo." + ext)
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return PhotoBrowserTemporaryImport(url: destination, directory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func deliver(to onOpen: (URL) -> Void) { defer { cleanup() }; onOpen(url) }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    deinit { cleanup() }
}

// Immutable, compiler-checked Sendable lease: URL and the acquisition result
// never change after init. Each reader retains this lease through its file I/O;
// cancellation only releases the coordinator's reference. ARC ends the scope
// exactly once after the last reader releases it, on whichever thread releases
// last. A failed acquisition is never balanced with a stop call.
private final class PhotoBrowserFolderAccess: Sendable {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

final class PhotoBrowserCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

enum PhotoBrowserImportOutcome: Sendable {
    case copied(UUID)
    case failed(String)
}

// All admission, ownership and completion state is protected by lock. A worker
// transfers its lease here before releasing admission; only a successful claim
// transfers access to the main actor. Cleanup happens outside the lock but is
// counted until it finishes. No lease or callback escapes an unprotected lookup.
final class PhotoBrowserImportWork: @unchecked Sendable {
    private struct OwnedLease {
        let lease: PhotoBrowserTemporaryImport
        var claimed = false
    }
    private let lock = NSLock()
    private var closed = false
    private var workers = Set<UUID>()
    private var leases: [UUID: OwnedLease] = [:]
    private var cleanups = 0
    private var waiters: [@Sendable () -> Void] = []

    func admitCopy() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return nil }
        let id = UUID(); workers.insert(id); return id
    }
    func finishCopy(_ id: UUID, result: Result<PhotoBrowserTemporaryImport, Error>) -> PhotoBrowserImportOutcome? {
        lock.lock()
        precondition(workers.remove(id) != nil, "Copy admission must finish exactly once")
        let outcome: PhotoBrowserImportOutcome
        switch result {
        case .success(let lease): leases[id] = OwnedLease(lease: lease); outcome = .copied(id)
        case .failure(let error): outcome = .failed(error.localizedDescription)
        }
        let rejected = closed
        let callbacks = drainedWaitersLocked()
        lock.unlock()
        if rejected, case .copied = outcome { release(id) }
        callbacks.forEach { $0() }
        return rejected ? nil : outcome
    }
    func claim(_ id: UUID) -> PhotoBrowserTemporaryImport? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, var owned = leases[id], !owned.claimed else { return nil }
        owned.claimed = true; leases[id] = owned; return owned.lease
    }
    func release(_ id: UUID) {
        lock.lock()
        guard let owned = leases.removeValue(forKey: id) else { lock.unlock(); return }
        cleanups += 1
        lock.unlock()
        owned.lease.cleanup()
        lock.lock()
        cleanups -= 1
        let callbacks = drainedWaitersLocked()
        lock.unlock()
        callbacks.forEach { $0() }
    }
    func beginShutdown() {
        lock.lock()
        closed = true
        let unclaimed = leases.compactMap { $0.value.claimed ? nil : $0.key }
        lock.unlock()
        unclaimed.forEach { release($0) }
    }
    // Returns true instead of calling completion when already idle, allowing
    // the main-actor API to acknowledge synchronously without a dispatch hop.
    func notifyWhenDrained(_ completion: @escaping @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isDrainedLocked { return true }
        waiters.append(completion); return false
    }
    private var isDrainedLocked: Bool {
        closed && workers.isEmpty && leases.isEmpty && cleanups == 0
    }
    private func drainedWaitersLocked() -> [@Sendable () -> Void] {
        guard isDrainedLocked else { return [] }
        let callbacks = waiters; waiters = []; return callbacks
    }
}

@MainActor
final class PhotoBrowserShutdownCompletion {
    private var callback: (() -> Void)?
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    func call() {
        guard let callback else { return }
        self.callback = nil; callback()
    }
    nonisolated func schedule() {
        // terminateLater enters NSModalPanelRunLoopMode. A main-actor task can
        // stall behind the main queue's enclosing termination call. Register one
        // block for both modes (not two callbacks) and explicitly wake the loop.
        let main = CFRunLoopGetMain()
        let modes = [CFRunLoopMode.commonModes.rawValue, RunLoop.Mode.modalPanel.rawValue as CFString] as CFArray
        CFRunLoopPerformBlock(main, modes) {
            MainActor.assumeIsolated { self.call() }
        }
        CFRunLoopWakeUp(main)
    }
}

// Shared by the real coordinator and permission-free lifecycle tests. Invalidate
// before ending sheets/cancelling providers: those operations can reenter AppKit.
@MainActor
final class PhotoBrowserSession {
    private(set) var id: UUID?
    private(set) var isShutdown = false
    private var onOpen: ((URL) -> Void)?
    func begin(onOpen: @escaping (URL) -> Void) -> UUID? {
        guard !isShutdown else { return nil }
        let id = UUID(); self.id = id; self.onOpen = onOpen
        return id
    }
    func accepts(_ id: UUID) -> Bool { !isShutdown && self.id == id }
    func shutdown() { isShutdown = true; id = nil; onOpen = nil }
    func complete(_ id: UUID, opening url: URL?, lease: PhotoBrowserTemporaryImport?,
                  beforeDelivery: () -> Void = {}) {
        defer { lease?.cleanup() }
        guard accepts(id) else { return }
        let callback = onOpen
        self.id = nil; onOpen = nil
        beforeDelivery()
        guard !isShutdown, let url, let callback else { return }
        if let lease { lease.deliver(to: callback) } else { callback(url) }
    }
}

@MainActor
private final class PhotoBrowserCell: NSTableCellView {
    var representedURL: URL?
    let preview = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        preview.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 20, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 18)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.lineBreakMode = .byTruncatingTail
        for view in [preview, nameLabel, detailLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: 140), preview.heightAnchor.constraint(equalToConstant: 112),
            nameLabel.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
}

@MainActor
final class PhotoBrowserCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                     NSWindowDelegate, PHPickerViewControllerDelegate {
    private var panel: NSPanel?
    private var browserContent: NSView?
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let folderButton = NSButton()
    private let libraryButton = NSButton()
    private let thumbnails = NSCache<NSURL, NSImage>()
    private var entries: [PhotoBrowserEntry] = []
    private var folderAccess: PhotoBrowserFolderAccess?
    private var cancellation: PhotoBrowserCancellation?
    private let session = PhotoBrowserSession()
    private var sessionID: UUID? { session.id }
    private var requestID: UUID?
    private var pendingURL: URL?
    private var pendingLease: PhotoBrowserTemporaryImport?
    private var pendingImportID: UUID?
    private let importWork = PhotoBrowserImportWork()
    private var picker: PHPickerViewController?
    private var pickerProgress: Progress?
    private var folderChooser: NSOpenPanel?

    /// onOpen must synchronously read/decode the URL, as App.openURL does. The
    /// Photos copy is removed after it returns, including a declined dirty prompt.
    func show(relativeTo parent: NSWindow, onOpen: @escaping (URL) -> Void) {
        guard !session.isShutdown else { return }
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        guard let session = session.begin(onOpen: onOpen) else { return }
        thumbnails.countLimit = 128
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Photos"; panel.minSize = NSSize(width: 760, height: 540)
        panel.isReleasedWhenClosed = false; panel.delegate = self; self.panel = panel
        buildContent(in: panel)
        // Retain a temporary coordinator until the sheet actually completes.
        parent.beginSheet(panel) { [self] _ in complete(session: session) }
    }

    /// Call on the main actor after Quit is approved. Terminal and idempotent:
    /// no future show or pending folder/Photos completion can invoke onOpen.
    public func shutdown() {
        shutdown(completion: {})
    }

    /// Completion runs on the main actor, synchronously when idle, after all
    /// admitted copies and owned leases drain. It does not await OS picker work.
    public func shutdown(completion: @escaping () -> Void) {
        session.shutdown()
        importWork.beginShutdown() // Reject callbacks before cancelling Progress.
        clearBrowser()
        let completion = PhotoBrowserShutdownCompletion(completion)
        if importWork.notifyWhenDrained({
            completion.schedule()
        }) { completion.call() }
    }

    private func buildContent(in panel: NSPanel) {
        let content = NSView(); browserContent = content; panel.contentView = content
        let title = NSTextField(labelWithString: "Open a photo")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "Choose Pictures or another image folder, or select a photo from your Photos library. Double-click a thumbnail to open the original image.")
        help.font = .systemFont(ofSize: 20)
        configure(folderButton, "Pictures Folder…", #selector(chooseFolder))
        configure(libraryButton, "Photos Library…", #selector(chooseLibrary))
        configure(openButton, "Open Selected Photo", #selector(openSelected)); openButton.isEnabled = false
        openButton.keyEquivalent = "\r"
        let close = NSButton(title: "Close", target: self, action: #selector(closeBrowser))
        close.font = .systemFont(ofSize: 20); close.keyEquivalent = "\u{1b}"
        let sources = NSStackView(views: [folderButton, libraryButton]); sources.spacing = 16
        let bottom = NSStackView(views: [close, openButton]); bottom.spacing = 16
        status.font = .systemFont(ofSize: 18); status.maximumNumberOfLines = 2
        status.stringValue = "No folder selected. Only the folder you choose will be browsed."
        table.headerView = nil; table.rowHeight = 140; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self; table.delegate = self; table.target = self
        table.doubleAction = #selector(openSelected); table.allowsMultipleSelection = false
        if table.tableColumns.isEmpty { let column = NSTableColumn(identifier: .init("photo")); column.width = 800; table.addTableColumn(column) }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        for view in [title, help, sources, scroll, status, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), title.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor), help.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            sources.leadingAnchor.constraint(equalTo: title.leadingAnchor), sources.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: help.trailingAnchor), scroll.topAnchor.constraint(equalTo: sources.bottomAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor), status.trailingAnchor.constraint(equalTo: help.trailingAnchor), status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: help.trailingAnchor), bottom.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 18), bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
    }
    private func configure(_ button: NSButton, _ title: String, _ action: Selector) {
        button.title = title; button.target = self; button.action = action
        button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 20)
    }
    private func setLoading(_ loading: Bool) {
        folderButton.isEnabled = !loading; libraryButton.isEnabled = !loading
        openButton.isEnabled = !loading && entries.indices.contains(table.selectedRow)
    }

    @objc private func chooseFolder() {
        guard let panel, let session = sessionID else { return }
        let chooser = NSOpenPanel(); chooser.title = "Choose an image folder"; chooser.prompt = "Browse"
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false; chooser.canCreateDirectories = false
        chooser.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        folderChooser = chooser
        chooser.beginSheetModal(for: panel) { [weak self, weak chooser] response in
            guard let self, let chooser, self.session.accepts(session) else { return }
            self.folderChooser = nil
            guard response == .OK, let url = chooser.url else { return }
            self.loadFolder(url)
        }
    }
    private func loadFolder(_ url: URL) {
        guard panel != nil, let session = sessionID else { return }
        cancellation?.cancel()
        let access = PhotoBrowserFolderAccess(url), cancel = PhotoBrowserCancellation()
        let request = UUID()
        cancellation = cancel; folderAccess = access; requestID = request
        entries = []; thumbnails.removeAllObjects(); table.reloadData(); setLoading(true)
        status.stringValue = "Reading \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try PhotoBrowserCatalog.entries(in: access.url, isCancelled: { cancel.isCancelled }) }
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == session, self.requestID == request, !cancel.isCancelled else { return }
                switch result {
                case .success(let entries):
                    self.entries = entries
                    self.status.stringValue = entries.isEmpty ? "No supported photos in \(url.lastPathComponent). Choose another folder or use Photos Library." : "\(entries.count) photos in \(url.lastPathComponent). Double-click a photo to open it."
                    self.table.reloadData()
                case .failure(let error): self.status.stringValue = error.localizedDescription
                }
                self.setLoading(false)
            }
        }
    }

    @objc private func chooseLibrary() {
        guard let panel, sessionID != nil else { return }
        var configuration = PHPickerConfiguration() // No PHPhotoLibrary access or authorization request.
        configuration.filter = .images; configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self
        self.picker = picker; panel.title = "Photos Library"; panel.contentViewController = picker
    }
    private func restoreBrowser() {
        picker?.delegate = nil; picker = nil
        panel?.contentViewController = nil; panel?.contentView = browserContent; panel?.title = "Photos"
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard picker === self.picker, let session = sessionID else { return }
        restoreBrowser()
        guard let provider = results.first?.itemProvider else { return }
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            status.stringValue = "The selected item has no supported image representation."; return
        }
        let request = UUID(), cancel = PhotoBrowserCancellation()
        cancellation?.cancel(); cancellation = cancel
        requestID = request; setLoading(true)
        status.stringValue = "Preparing selected photo…"
        let work = importWork
        pickerProgress = provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard !cancel.isCancelled, let admission = work.admitCopy() else { return }
            // This copy must finish before NSItemProvider's callback returns.
            let result: Result<PhotoBrowserTemporaryImport, Error> = Result {
                if let error { throw error }
                guard let url else { throw PhotoBrowserFailure("Photos did not provide an image file.") }
                return try PhotoBrowserTemporaryImport.copyRepresentation(from: url)
            }
            guard let outcome = work.finishCopy(admission, result: result) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.session.accepts(session), self.requestID == request, !cancel.isCancelled else {
                    if case .copied(let id) = outcome { work.release(id) }; return
                }
                self.pickerProgress = nil
                switch outcome {
                case .copied(let id):
                    guard let lease = work.claim(id) else { return }
                    self.pendingImportID = id; self.pendingLease = lease
                    self.finish(opening: lease.url)
                case .failed(let message): self.status.stringValue = message; self.setLoading(false)
                }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableViewSelectionDidChange(_ notification: Notification) { openButton.isEnabled = entries.indices.contains(table.selectedRow) && folderButton.isEnabled }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("PhotoBrowserCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PhotoBrowserCell ?? PhotoBrowserCell(frame: .zero)
        cell.identifier = identifier
        let entry = entries[row]; cell.representedURL = entry.url; cell.nameLabel.stringValue = entry.name
        cell.detailLabel.stringValue = "\(entry.displayWidth) × \(entry.displayHeight) pixels · \(UTType(entry.typeIdentifier)?.localizedDescription ?? "Photo")"
        cell.preview.image = thumbnails.object(forKey: entry.url as NSURL)
        cell.setAccessibilityLabel(entry.name + ", " + cell.detailLabel.stringValue)
        guard cell.preview.image == nil else { return cell }
        guard let session = sessionID, let cancel = cancellation else { return cell }
        let access = folderAccess, request = requestID
        DispatchQueue.global(qos: .utility).async { [weak self, weak cell] in
            guard !cancel.isCancelled else { return }
            let image = PhotoBrowserCatalog.thumbnail(for: entry)
            withExtendedLifetime(access) { }
            guard !cancel.isCancelled else { return }
            Task { @MainActor [weak self, weak cell] in
                guard let self, self.sessionID == session, self.requestID == request,
                      !cancel.isCancelled, let image else { return }
                let thumbnail = NSImage(cgImage: image, size: .zero)
                self.thumbnails.setObject(thumbnail, forKey: entry.url as NSURL)
                if cell?.representedURL == entry.url { cell?.preview.image = thumbnail }
            }
        }
        return cell
    }
    @objc private func openSelected() {
        guard folderButton.isEnabled, entries.indices.contains(table.selectedRow) else { return }
        let url = entries[table.selectedRow].url
        guard PhotoBrowserCatalog.metadata(for: url) != nil else {
            status.stringValue = "This photo is no longer readable. Choose the folder again."; return
        }
        finish(opening: url)
    }
    @objc private func closeBrowser() { finish(opening: nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeBrowser(); return false }
    private func finish(opening url: URL?) {
        guard sessionID != nil, let panel, let parent = panel.sheetParent else { return }
        pendingURL = url; parent.endSheet(panel, returnCode: url == nil ? .cancel : .OK)
    }
    private func complete(session: UUID) {
        guard self.session.accepts(session) else { return }
        let url = pendingURL, lease = pendingLease, access = folderAccess
        let importID = pendingImportID
        defer { if let importID { importWork.release(importID) } }
        // Invalidate callbacks before sheet cleanup; deliver only after cleanup.
        self.session.complete(session, opening: url, lease: lease) {
            pendingLease = nil // The completion retains the lease until App reads it.
            pendingImportID = nil // Keep claimed ownership until delivery returns.
            clearBrowser()
        }
        withExtendedLifetime(access) { }
    }
    private func clearBrowser() {
        cancellation?.cancel(); cancellation = nil; requestID = nil
        let progress = pickerProgress; pickerProgress = nil; progress?.cancel()
        picker?.delegate = nil; picker = nil
        let chooser = folderChooser; folderChooser = nil
        if let chooser {
            chooser.sheetParent?.endSheet(chooser, returnCode: .cancel)
            chooser.orderOut(nil)
        }
        let closingPanel = panel; panel = nil; browserContent = nil
        if let closingPanel {
            closingPanel.delegate = nil
            closingPanel.sheetParent?.endSheet(closingPanel, returnCode: .cancel)
            closingPanel.orderOut(nil)
        }
        folderAccess = nil; pendingURL = nil
        pendingLease?.cleanup(); pendingLease = nil
        if let id = pendingImportID { pendingImportID = nil; importWork.release(id) }
        entries = []; table.reloadData(); thumbnails.removeAllObjects()
    }
}
