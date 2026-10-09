import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Independent History presentation. Original evidence: history help/screenshot,
/// open 0x00033ae7, search 0x00033ba3, details 0x00034238, sections 0x00034faa.
/// Recovered date/search predicates are retained. Exact original popup labels and
/// runtime visual parity remain unverified; labels describe the recovered intervals.
@MainActor
final class HistoryBrowser: NSWindowController, NSCollectionViewDataSource,
    NSCollectionViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    struct Item: Equatable {
        var id: UUID
        var name: String
        var date: Date
        var size: CGSize
        var action: String
        var text: String
        var destination: String?
        var link: URL?
        var previewURL: URL?
        var missing: Bool
    }
    enum Category: Int, CaseIterable {
        case all, posted, savedDragged, archived
        var title: String { ["All", "Posted to Web", "Saved/DragMe'd", "Archived"][rawValue] }
        func includes(_ item: Item) -> Bool {
            switch self {
            case .all: return true
            case .posted: return item.action == "Shared"
            case .savedDragged: return item.action == "Exported/Dragged"
            case .archived: return item.action == "Saved"
            }
        }
    }
    enum DateFilter: Int, CaseIterable {
        case all, lastHour, yesterday, last48
        var title: String { ["All dates", "Last hour", "Yesterday", "Last 48 hours"][rawValue] }
    }
    enum Action: Int, CaseIterable {
        case open, copy, copyLink, openLink, remove, deleteFiles, deleteRemote
        var title: String { ["Open", "Copy", "Copy Link", "Open Link", "Hide from History", "Move to Trash", "Delete from Web"][rawValue] }
    }
    struct Section { var day: Date; var title: String; var items: [Item] }
    nonisolated static let dragFormats = ["png", "jpeg", "tiff", "pdf", "svg", "opensnap"]
    nonisolated static let dragFormatDefaultsKey = "OpenSnap.HistoryDragFormat"

    var onOpen: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onCopy: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onCopyLink: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onOpenLink: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onRemove: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onDeleteFiles: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onDeleteRemote: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onExport: ((UUID, String) throws -> Data)?
    var onError: ((Error) -> Void)?

    private(set) var sections: [Section] = []
    private(set) var category: Category = .all
    private(set) var dateFilter: DateFilter = .all
    private(set) var query = ""
    var selectedIDs: [UUID] { selectedItems.map(\.id) }
    var dragFormat: String { Self.dragFormats.contains(defaults.string(forKey: Self.dragFormatDefaultsKey) ?? "") ? defaults.string(forKey: Self.dragFormatDefaultsKey)! : "png" }
    var visibleItems: [Item] { sections.flatMap(\.items) }
    private var items: [Item] = []
    private var lastRefreshDay: Date?
    #if HISTORY_BROWSER_TESTS
    private(set) var fullReloadCount = 0
    private(set) var partialReloadCount = 0
    #endif
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let thumbnails = NSCache<NSURL, NSImage>()
    private let collection = HistoryGrid()
    private let categoryControl = NSSegmentedControl()
    private let datePopup = NSPopUpButton()
    private let formatPopup = NSPopUpButton()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let warning = NSTextField(wrappingLabelWithString: "")
    private let detailsImage = NSImageView()
    private var detailValues: [String: NSTextField] = [:]
    private var buttons: [Action: NSButton] = [:]
    private var contextItems: [Action: NSMenuItem] = [:]
    private var selectionChanging = false
    private var selectedItems: [Item] {
        collection.selectionIndexPaths.sorted { a,b in a.section == b.section ? a.item < b.item : a.section < b.section }.compactMap(item)
    }

    convenience init() { self.init(defaults: .standard, calendar: .current, now: Date.init) }
    init(defaults: UserDefaults, calendar: Calendar, now: @escaping () -> Date) {
        self.defaults = defaults; self.calendar = calendar; self.now = now
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1180,height:900),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = "History"; window.minSize = NSSize(width:1120,height:850)
        window.isReleasedWhenClosed = false
        super.init(window:window)
        thumbnails.countLimit = 256; thumbnails.totalCostLimit = 64*1024*1024
        buildUI(); rebuild(keeping: [])
    }
    required init?(coder: NSCoder) { return nil }

    func update(items: [Item]) {
        let selected = Set(selectedIDs)
        var seen = Set<UUID>()
        // Core supplies reverse insertion order. Dates can be edited or imported;
        // timestamp sorting here would change the recovered History ordering.
        let updated = items.filter { seen.insert($0.id).inserted }
        let movingDateWindow = dateFilter == .lastHour || dateFilter == .last48
        guard updated != self.items || lastRefreshDay != calendar.startOfDay(for:now()) || movingDateWindow else { return }
        let old = Dictionary(uniqueKeysWithValues:self.items.map { ($0.id,$0) })
        for value in updated where old[value.id] != value {
            if let url = value.previewURL { thumbnails.removeObject(forKey:url as NSURL) }
            if let url = old[value.id]?.previewURL { thumbnails.removeObject(forKey:url as NSURL) }
        }
        self.items = updated
        rebuild(keeping:selected,preserveScroll:true)
    }
    func setFilters(category: Category, date: DateFilter = .all, query: String = "") {
        let selected = Set(selectedIDs)
        self.category = category; dateFilter = date; self.query = query
        categoryControl.selectedSegment = category.rawValue
        datePopup.selectItem(at:date.rawValue); search.stringValue = query
        rebuild(keeping:selected)
    }
    func select(ids: [UUID]) {
        let wanted = Set(ids)
        var paths = Set<IndexPath>()
        for (section,group) in sections.enumerated() { for (index,value) in group.items.enumerated() where wanted.contains(value.id) {
            paths.insert(IndexPath(item:index,section:section))
        } }
        collection.selectionIndexPaths = paths
        updateControls()
    }
    func setDragFormat(_ format: String) {
        guard let index = Self.dragFormats.firstIndex(of:format) else { return }
        defaults.set(format,forKey:Self.dragFormatDefaultsKey); formatPopup.selectItem(at:index)
    }
    func canPerform(_ action: Action) -> Bool {
        let selected = selectedItems
        guard !selected.isEmpty, callback(action) != nil else { return false }
        switch action {
        case .open,.copy,.deleteFiles: return selected.allSatisfy { !$0.missing }
        case .copyLink,.openLink,.deleteRemote: return selected.allSatisfy { $0.link != nil }
        case .remove: return true
        }
    }
    func perform(_ action: Action) {
        guard canPerform(action) else { return }
        let ids = selectedIDs // Capture UUIDs before a callback changes the catalog.
        callback(action)?(ids)
    }
    private func callback(_ action: Action) -> (([UUID]) -> Void)? {
        switch action {
        case .open: return onOpen
        case .copy: return onCopy
        case .copyLink: return onCopyLink
        case .openLink: return onOpenLink
        case .remove: return onRemove
        case .deleteFiles: return onDeleteFiles
        case .deleteRemote: return onDeleteRemote
        }
    }

    private func dateIncludes(_ date: Date,reference: Date) -> Bool {
        switch dateFilter {
        case .all: return true
        case .lastHour: return date > reference.addingTimeInterval(-3600) && date < .distantFuture
        case .last48: return date > reference.addingTimeInterval(-172800) && date < .distantFuture
        case .yesterday:
            let today = calendar.startOfDay(for:reference)
            guard let start = calendar.date(byAdding:.day,value:-1,to:today),
                  let nextDay = calendar.date(byAdding:.day,value:1,to:start) else { return false }
            // Modern calendar-day boundary with strict endpoints. Original used
            // NSCalendarDate +23h59m59s; its DST behavior remains runtime-unverified.
            return date > start && date < nextDay.addingTimeInterval(-1)
        }
    }
    private func rebuild(keeping selected: Set<UUID>,preserveScroll: Bool = false) {
        let previous = sections
        let scroll = collection.enclosingScrollView
        let origin = scroll?.contentView.bounds.origin
        let reference = now()
        let filtered = items.filter { value in
            category.includes(value) && dateIncludes(value.date,reference:reference) &&
                (query.isEmpty || [value.name,value.text,value.link?.absoluteString ?? ""]
                    .contains { $0.range(of:query,options:.caseInsensitive) != nil })
        }
        let today = calendar.startOfDay(for:reference), yesterday = calendar.date(byAdding:.day,value:-1,to:today)
        lastRefreshDay = today
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .full
        sections = []
        for value in filtered {
            let day = calendar.startOfDay(for:value.date)
            if sections.last?.day != day {
                let title = day == today ? "Today" : (day == yesterday ? "Yesterday" : formatter.string(from:day))
                sections.append(Section(day:day,title:title,items:[]))
            }
            sections[sections.count-1].items.append(value)
        }
        selectionChanging = true
        let sameStructure = previous.count == sections.count && zip(previous,sections).allSatisfy {
            $0.day == $1.day && $0.items.map(\.id) == $1.items.map(\.id)
        }
        if preserveScroll && sameStructure {
            var changed = Set<IndexPath>(), headers = IndexSet()
            for section in sections.indices {
                if previous[section].title != sections[section].title { headers.insert(section) }
                for index in sections[section].items.indices where previous[section].items[index] != sections[section].items[index] {
                    changed.insert(IndexPath(item:index,section:section))
                }
            }
            if !headers.isEmpty { collection.reloadSections(headers) }
            if !changed.isEmpty {
                collection.reloadItems(at:changed)
                #if HISTORY_BROWSER_TESTS
                partialReloadCount += 1
                #endif
            }
        } else {
            collection.reloadData()
            #if HISTORY_BROWSER_TESTS
            fullReloadCount += 1
            #endif
        }
        select(ids:Array(selected)); selectionChanging = false
        if preserveScroll, let scroll, let origin {
            collection.layoutSubtreeIfNeeded()
            let maximumY = max(0,collection.bounds.height-scroll.contentView.bounds.height)
            scroll.contentView.scroll(to:NSPoint(x:origin.x,y:min(maximumY,max(0,origin.y))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        updateControls()
    }
    private func item(_ path: IndexPath) -> Item? {
        guard sections.indices.contains(path.section), sections[path.section].items.indices.contains(path.item) else { return nil }
        return sections[path.section].items[path.item]
    }
    private func thumbnail(_ value: Item) -> NSImage? {
        guard !value.missing, let url = value.previewURL, url.isFileURL else { return nil }
        if let cached = thumbnails.object(forKey:url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,
                [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
                 kCGImageSourceThumbnailMaxPixelSize:320,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
        let result = NSImage(cgImage:image,size:.zero)
        thumbnails.setObject(result,forKey:url as NSURL,cost:image.bytesPerRow*image.height)
        return result
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 8; root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),root.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),
                                     root.topAnchor.constraint(equalTo:content.topAnchor,constant:18),root.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-18)])
        categoryControl.segmentCount = Category.allCases.count; categoryControl.trackingMode = .selectOne; categoryControl.font = .systemFont(ofSize:20)
        for value in Category.allCases { categoryControl.setLabel(value.title,forSegment:value.rawValue) }
        categoryControl.selectedSegment = 0; categoryControl.target = self; categoryControl.action = #selector(filtersChanged)
        categoryControl.setAccessibilityLabel("History category")
        root.addArrangedSubview(categoryControl)
        search.font = .systemFont(ofSize:20); search.placeholderString = "Search history"; search.delegate = self
        search.sendsSearchStringImmediately = true; search.setAccessibilityLabel("Search history")
        datePopup.addItems(withTitles:DateFilter.allCases.map(\.title)); datePopup.font = .systemFont(ofSize:20); datePopup.menu?.font = .systemFont(ofSize:20)
        datePopup.target = self; datePopup.action = #selector(filtersChanged); datePopup.setAccessibilityLabel("History date filter")
        let filters = row([search,datePopup]); search.widthAnchor.constraint(greaterThanOrEqualToConstant:480).isActive = true
        root.addArrangedSubview(filters)

        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width:210,height:234)
        layout.minimumInteritemSpacing = 20; layout.minimumLineSpacing = 20; layout.headerReferenceSize = NSSize(width:1,height:52)
        layout.sectionInset = NSEdgeInsets(top:8,left:12,bottom:20,right:12)
        collection.frame = NSRect(x:0,y:0,width:1140,height:400); collection.autoresizingMask = [.width]
        collection.collectionViewLayout = layout; collection.dataSource = self; collection.delegate = self
        collection.isSelectable = true; collection.allowsMultipleSelection = true; collection.allowsEmptySelection = true
        collection.backgroundColors = [.controlBackgroundColor]; collection.setAccessibilityLabel("History thumbnail grid")
        collection.register(HistoryThumbnail.self,forItemWithIdentifier:HistoryThumbnail.identifier)
        collection.register(HistoryDayHeader.self,forSupplementaryViewOfKind:NSCollectionView.elementKindSectionHeader,withIdentifier:HistoryDayHeader.identifier)
        collection.setDraggingSourceOperationMask(.copy,forLocal:false); collection.setDraggingSourceOperationMask(.copy,forLocal:true)
        collection.browser = self
        let menu = NSMenu(title:"History actions"); menu.font = .systemFont(ofSize:20)
        for action in Action.allCases {
            let item = NSMenuItem(title:action.title,action:#selector(actionInvoked(_:)),keyEquivalent:"")
            item.tag = action.rawValue; item.target = self; menu.addItem(item); contextItems[action] = item
        }
        collection.menu = menu
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:1140,height:400)); scroll.documentView = collection; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive = true
        scroll.setContentHuggingPriority(.defaultLow,for:.vertical)
        status.font = .systemFont(ofSize:18); root.addArrangedSubview(status)

        detailsImage.imageScaling = .scaleProportionallyUpOrDown; detailsImage.setAccessibilityLabel("Selected history preview")
        detailsImage.widthAnchor.constraint(equalToConstant:176).isActive = true; detailsImage.heightAnchor.constraint(equalToConstant:150).isActive = true
        let details = NSStackView(); details.orientation = .vertical; details.alignment = .leading; details.spacing = 5
        for name in ["Name","Date","Size","Action","Destination"] {
            let label = NSTextField(labelWithString:name+":"); label.font = .systemFont(ofSize:18,weight:.semibold)
            label.widthAnchor.constraint(equalToConstant:118).isActive = true
            let value = NSTextField(wrappingLabelWithString:"—"); value.font = .systemFont(ofSize:20); value.isSelectable = true
            value.maximumNumberOfLines = 2; value.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            value.setAccessibilityLabel(name); detailValues[name] = value
            let line = row([label,value]); details.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo:details.widthAnchor).isActive = true
        }
        root.addArrangedSubview(row([detailsImage,details]))
        warning.font = .systemFont(ofSize:20); warning.textColor = .systemRed; root.addArrangedSubview(warning)
        let actions = Action.allCases.map { action -> NSButton in
            let button = NSButton(title:action.title,target:self,action:#selector(actionInvoked(_:)))
            button.tag = action.rawValue; button.font = .systemFont(ofSize:20); button.bezelStyle = .rounded
            buttons[action] = button; return button
        }
        root.addArrangedSubview(row(Array(actions.prefix(4))))
        root.addArrangedSubview(row(Array(actions.suffix(3))))
        let formatLabel = NSTextField(labelWithString:"Drag from History format:"); formatLabel.font = .systemFont(ofSize:18)
        formatPopup.addItems(withTitles:Self.dragFormats.map { $0.uppercased() }); formatPopup.font = .systemFont(ofSize:20); formatPopup.menu?.font = .systemFont(ofSize:20)
        formatPopup.selectItem(at:Self.dragFormats.firstIndex(of:dragFormat) ?? 0)
        formatPopup.target = self; formatPopup.action = #selector(formatChanged); formatPopup.setAccessibilityLabel("History drag export format")
        root.addArrangedSubview(row([formatLabel,formatPopup]))
        for child in root.arrangedSubviews { child.widthAnchor.constraint(equalTo:root.widthAnchor).isActive = true }
        content.layoutSubtreeIfNeeded()
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views:views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 12
        return stack
    }
    private func updateControls() {
        let selected = selectedItems
        for action in Action.allCases { buttons[action]?.isEnabled = canPerform(action) }
        status.stringValue = visibleItems.isEmpty ? "No history items match these filters." : "\(visibleItems.count) items · \(selected.count) selected"
        let missingCount = selected.filter(\.missing).count
        warning.stringValue = missingCount == 0 ? "" : "\(missingCount) selected \(missingCount == 1 ? "file is" : "files are") missing. You can remove the history entry or use its web link."
        warning.isHidden = missingCount == 0
        guard let value = selected.first else {
            detailsImage.image = nil; detailValues.values.forEach { $0.stringValue = "—" }; return
        }
        detailsImage.image = selected.count == 1 ? thumbnail(value) : nil
        if selected.count > 1 {
            detailValues["Name"]?.stringValue = "\(selected.count) items selected"
            detailValues["Date"]?.stringValue = "Multiple dates"; detailValues["Size"]?.stringValue = "Multiple sizes"
            detailValues["Action"]?.stringValue = Set(selected.map(\.action)).sorted().joined(separator:", ")
            detailValues["Destination"]?.stringValue = "Multiple destinations"
        } else {
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .long; formatter.timeStyle = .short
            detailValues["Name"]?.stringValue = value.name; detailValues["Date"]?.stringValue = formatter.string(from:value.date)
            let size = value.size
            detailValues["Size"]?.stringValue = size.width.isFinite && size.height.isFinite ? "\(size.width.formatted()) × \(size.height.formatted())" : "Unknown size"
            detailValues["Action"]?.stringValue = value.action
            detailValues["Destination"]?.stringValue = value.destination ?? value.link?.absoluteString ?? "—"
        }
    }
    @objc private func filtersChanged() {
        setFilters(category:Category(rawValue:categoryControl.selectedSegment) ?? .all,
                   date:DateFilter(rawValue:datePopup.indexOfSelectedItem) ?? .all,query:search.stringValue)
    }
    @objc private func formatChanged() { setDragFormat(Self.dragFormats[max(0,formatPopup.indexOfSelectedItem)]) }
    @objc private func actionInvoked(_ sender: AnyObject) {
        let tag = (sender as? NSControl)?.tag ?? (sender as? NSMenuItem)?.tag ?? -1
        if let action = Action(rawValue:tag) { perform(action) }
    }
    func controlTextDidChange(_ obj: Notification) { filtersChanged() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Popup choices have default tag zero and no action selector. They
        // must remain selectable even when the grid has no selected drawing.
        guard menuItem.action == #selector(actionInvoked(_:)) else { return true }
        return Action(rawValue:menuItem.tag).map(canPerform) ?? false
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: NSCollectionView,numberOfItemsInSection section: Int) -> Int { sections[section].items.count }
    func collectionView(_ collectionView: NSCollectionView,itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier:HistoryThumbnail.identifier,for:indexPath) as! HistoryThumbnail
        if let value = item(indexPath) { cell.configure(value,image:thumbnail(value)) }
        return cell
    }
    func collectionView(_ collectionView: NSCollectionView,viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind:kind,withIdentifier:HistoryDayHeader.identifier,for:indexPath) as! HistoryDayHeader
        header.label.stringValue = sections[indexPath.section].title; return header
    }
    func collectionView(_ collectionView: NSCollectionView,didSelectItemsAt indexPaths: Set<IndexPath>) { if !selectionChanging { updateControls() } }
    func collectionView(_ collectionView: NSCollectionView,didDeselectItemsAt indexPaths: Set<IndexPath>) { if !selectionChanging { updateControls() } }

    /// Export now, never when Finder later asks the promise to write. The delegate
    /// owns immutable bytes/name/format even if the history catalog is then removed.
    func dragPromise(for id: UUID) -> NSFilePromiseProvider? {
        guard let value = visibleItems.first(where: { $0.id == id }), !value.missing, let export = onExport else { return nil }
        let format = dragFormat
        do {
            let bytes = try export(value.id,format)
            let snapshot = HistoryPromiseSnapshot(name:value.name,format:format,bytes:bytes) { [weak self] error in self?.onError?(error) }
            return HistoryFilePromise(snapshot:snapshot)
        } catch { onError?(error); return nil }
    }
    func collectionView(_ collectionView: NSCollectionView,pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        item(indexPath).flatMap { dragPromise(for:$0.id) }
    }
}

@MainActor
private final class HistoryGrid: NSCollectionView {
    weak var browser: HistoryBrowser?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with:event)
        if event.clickCount == 2, indexPathForItem(at:convert(event.locationInWindow,from:nil)) != nil { browser?.perform(.open) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let path = indexPathForItem(at:convert(event.locationInWindow,from:nil)) else { return nil }
        if !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            browser?.collectionView(self,didSelectItemsAt:[path])
        }
        return super.menu(for:event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { browser?.perform(.open); return }
        if event.keyCode == 51 || event.keyCode == 117 { browser?.perform(.remove); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            browser?.perform(event.modifierFlags.contains(.shift) ? .copyLink : .copy); return
        }
        super.keyDown(with:event) // Native arrow/Shift/Command selection behavior.
    }
}

@MainActor
private final class HistoryThumbnail: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryThumbnail")
    private let name = NSTextField(wrappingLabelWithString:"")
    private let action = NSTextField(labelWithString:"")
    private let placeholder = NSTextField(wrappingLabelWithString:"Preview unavailable")
    private let preview = NSImageView()
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 8
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 5; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),
                                     stack.topAnchor.constraint(equalTo:view.topAnchor,constant:8),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-8)])
        let host = NSView(); host.translatesAutoresizingMaskIntoConstraints = false; host.heightAnchor.constraint(equalToConstant:126).isActive = true
        for child in [preview,placeholder] {
            child.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:host.leadingAnchor),child.trailingAnchor.constraint(equalTo:host.trailingAnchor),
                                         child.topAnchor.constraint(equalTo:host.topAnchor),child.bottomAnchor.constraint(equalTo:host.bottomAnchor)])
        }
        preview.imageScaling = .scaleProportionallyUpOrDown; placeholder.font = .systemFont(ofSize:18); placeholder.alignment = .center
        name.font = .systemFont(ofSize:20); name.maximumNumberOfLines = 2; name.lineBreakMode = .byTruncatingTail
        action.font = .systemFont(ofSize:18); action.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(host); stack.addArrangedSubview(name); stack.addArrangedSubview(action)
        host.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
    }
    func configure(_ value: HistoryBrowser.Item,image: NSImage?) {
        _ = view
        name.stringValue = value.name; action.stringValue = value.missing ? "Missing file · \(value.action)" : value.action
        preview.image = image; placeholder.isHidden = image != nil; preview.isHidden = image == nil
        preview.setAccessibilityLabel(value.name); view.setAccessibilityLabel(value.name+", "+action.stringValue)
        refreshSelection()
    }
    override var isSelected: Bool { didSet { refreshSelection() } }
    private func refreshSelection() {
        guard isViewLoaded else { return }
        view.layer?.borderWidth = isSelected ? 2 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.15) : .clear).cgColor
    }
}
@MainActor
private final class HistoryDayHeader: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryDayHeader")
    let label = NSTextField(labelWithString:"")
    override init(frame: NSRect) {
        super.init(frame:frame); label.font = .systemFont(ofSize:20,weight:.semibold)
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),label.centerYAnchor.constraint(equalTo:centerYAnchor)])
    }
    required init?(coder: NSCoder) { return nil }
}

/// Immutable file-promise state; no document/core/browser access on worker threads.
final class HistoryPromiseSnapshot: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let filename: String
    let typeIdentifier: String
    let bytes: Data
    private let failure: @MainActor @Sendable (Error) -> Void
    private let queue: OperationQueue
    init(name: String,format: String,bytes: Data,failure: @escaping @MainActor @Sendable (Error) -> Void) {
        self.bytes = bytes; self.failure = failure
        let ext = format == "jpeg" ? "jpg" : format
        let invalid = CharacterSet(charactersIn:"/\\:\0").union(.controlCharacters)
        let clean = name.components(separatedBy:invalid).joined(separator:"_").trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:".")))
        let base = clean.isEmpty ? "OpenSnap" : String(clean.prefix(160))
        let knownExtension = HistoryBrowser.dragFormats.contains((base as NSString).pathExtension.lowercased()) || (base as NSString).pathExtension.lowercased() == "jpg"
        filename = (knownExtension ? (base as NSString).deletingPathExtension : base)+"."+ext
        typeIdentifier = UTType(filenameExtension:ext)?.identifier ?? UTType.data.identifier
        queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.name = "OpenSnap.HistoryPromise"
        super.init()
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,fileNameForType fileType: String) -> String { filename }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,writePromiseTo url: URL,completionHandler: @escaping (Error?) -> Void) {
        do { try bytes.write(to:url,options:.atomic); completionHandler(nil) }
        catch {
            completionHandler(error)
            let failure = failure
            Task { @MainActor in failure(error) }
        }
    }
}
final class HistoryFilePromise: NSFilePromiseProvider {
    private(set) var snapshot: HistoryPromiseSnapshot!
    // AppKit's fileType initializer dynamically calls init(); retain the delegate
    // after that initializer completes rather than relying on a Swift-only init.
    override init() { super.init() }
    convenience init(snapshot: HistoryPromiseSnapshot) {
        self.init(fileType:snapshot.typeIdentifier,delegate:snapshot); self.snapshot = snapshot
    }
    required init?(coder: NSCoder) { return nil }
}
