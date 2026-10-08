import AppKit

// The Destination Settings sheet content: a list of saved destinations (Add / Edit / Remove /
// Make Default) and a form for one destination. It owns no storage; the coordinator supplies
// callbacks, so every action is testable without a window or a network.
final class PublishingDestinationsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onMakeDefault: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onSave: ((PublishingDestination, String) -> Void)?
    var onTest: ((PublishingDestination, String) -> Void)?
    var onDone: (() -> Void)?
    var passwordFor: (PublishingDestination) -> String = { _ in "" }

    private(set) var list: PublishingDestinationList
    private(set) var editing: PublishingDestination?

    private let table = NSTableView()
    private let listPage = NSStackView(), formPage = NSStackView()
    private let status = NSTextField(wrappingLabelWithString: "")

    // Form controls (internal so tests can fill them in like a user would).
    let nameField = NSTextField(), endpointField = NSTextField(), usernameField = NSTextField()
    let passwordField = NSSecureTextField(), folderField = NSTextField(), publicField = NSTextField()
    let aliasField = NSTextField(), remoteRootField = NSTextField(), portField = NSTextField()
    let regionField = NSTextField(), bucketField = NSTextField(), profileField = NSTextField()
    let protocolPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let aclCheckbox = NSButton(checkboxWithTitle: "Make uploads public-read (leave off when the bucket disables ACLs)", target: nil, action: nil)

    private struct Row { let label: NSTextField; let stack: NSStackView; let visible: (PublishingProtocol, Bool) -> Bool }
    private var rows: [String: Row] = [:]

    private static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size) }
    private static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.font = font(18); button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return button
    }

    init(list: PublishingDestinationList) {
        self.list = list
        super.init(frame: .zero)
        buildList(); buildForm()
        let root = NSStackView(views: [listPage, formPage]); root.orientation = .vertical; root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false; addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
                                     root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                                     root.topAnchor.constraint(equalTo: topAnchor, constant: 24),
                                     root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24)])
        showList()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: List page

    private func buildList() {
        listPage.orientation = .vertical; listPage.alignment = .leading; listPage.spacing = 16
        let title = label("Upload destinations. The checked one receives a Webpost click; right-click Webpost to switch.")
        title.preferredMaxLayoutWidth = 720
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        column.width = 700
        let cell = NSTextFieldCell(); cell.font = Self.font(18); cell.lineBreakMode = .byTruncatingTail
        column.dataCell = cell
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 34
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true
        table.setAccessibilityLabel("Destinations")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 740).isActive = true
        let add = Self.button("Add…", self, #selector(addTapped))
        let edit = Self.button("Edit…", self, #selector(editTapped))
        let remove = Self.button("Remove", self, #selector(removeTapped))
        let makeDefault = Self.button("Make Default", self, #selector(makeDefaultTapped))
        let actions = NSStackView(views: [add, edit, remove, makeDefault]); actions.spacing = 16
        status.font = Self.font(18); status.maximumNumberOfLines = 0; status.preferredMaxLayoutWidth = 720
        let done = Self.button("Done", self, #selector(doneTapped))
        listPage.setViews([title, scroll, actions, status, done], in: .leading)
        listButtons = (edit, remove, makeDefault)
    }
    private var listButtons: (edit: NSButton, remove: NSButton, makeDefault: NSButton)?

    func numberOfRows(in tableView: NSTableView) -> Int { list.destinations.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let destination = list.destinations[row]
        let isDefault = destination.id == list.defaultDestination?.id
        return destination.name + "  ·  " + destination.settings.transport.shortTitle + (isDefault ? "   (Default)" : "")
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateListButtons() }

    var selectedDestination: PublishingDestination? {
        let row = table.selectedRow
        return list.destinations.indices.contains(row) ? list.destinations[row] : nil
    }
    func select(id: String) {
        if let index = list.destinations.firstIndex(where: { $0.id == id }) { table.selectRowIndexes([index], byExtendingSelection: false) }
        updateListButtons()
    }
    private func updateListButtons() {
        let selected = selectedDestination
        listButtons?.edit.isEnabled = selected != nil
        listButtons?.remove.isEnabled = selected != nil
        listButtons?.makeDefault.isEnabled = selected != nil && selected?.id != list.defaultDestination?.id
    }

    /// Replaces the list (after a save, remove or default change) and returns to the list page.
    func reload(_ list: PublishingDestinationList, status text: String = "", selecting id: String? = nil) {
        self.list = list
        table.reloadData()
        if let id { select(id: id) }
        showList()
        status.stringValue = text
    }
    func showStatus(_ text: String) { status.stringValue = text; formStatus.stringValue = text }

    @objc func addTapped() { showForm(for: nil) }
    @objc func editTapped() { if let selected = selectedDestination { showForm(for: selected) } }
    @objc func removeTapped() { if let selected = selectedDestination { onRemove?(selected.id) } }
    @objc func makeDefaultTapped() { if let selected = selectedDestination { onMakeDefault?(selected.id) } }
    @objc func doneTapped() { onDone?() }

    private func showList() {
        formPage.isHidden = true; listPage.isHidden = false
        editing = nil; updateListButtons()
    }

    // MARK: Form page

    private let formStatus = NSTextField(wrappingLabelWithString: "")
    private let formHelp = NSTextField(wrappingLabelWithString: "")

    private func styled(_ field: NSTextField, _ placeholder: String) -> NSTextField {
        field.font = Self.font(20); field.placeholderString = placeholder; return field
    }
    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = Self.font(18); field.textColor = .labelColor
        return field
    }
    private func addRow(_ id: String, _ title: String, _ control: NSView, visible: @escaping (PublishingProtocol, Bool) -> Bool) {
        let caption = label(title)
        let stack = NSStackView(views: [caption, control]); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 16
        caption.widthAnchor.constraint(equalToConstant: 175).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        control.setAccessibilityLabel(title)
        rows[id] = Row(label: caption, stack: stack, visible: visible)
        formPage.addArrangedSubview(stack)
    }

    private func buildForm() {
        formPage.orientation = .vertical; formPage.alignment = .leading; formPage.spacing = 14
        for popup in [protocolPopup, sourcePopup] {
            popup.font = Self.font(18); popup.menu?.font = Self.font(18); popup.menu?.autoenablesItems = false
        }
        protocolPopup.addItems(withTitles: PublishingProtocol.allCases.map(\.title))
        protocolPopup.target = self; protocolPopup.action = #selector(formChanged)
        sourcePopup.addItems(withTitles: ["AWS credentials profile", "Access key stored in Keychain"])
        sourcePopup.target = self; sourcePopup.action = #selector(formChanged)
        aclCheckbox.font = Self.font(18)
        passwordField.font = Self.font(20)
        let all: (PublishingProtocol, Bool) -> Bool = { _, _ in true }
        addRow("name", "Name", styled(nameField, "Shown in the Webpost right-click menu"), visible: all)
        addRow("protocol", "Protocol", protocolPopup, visible: all)
        addRow("endpoint", "Endpoint URL", styled(endpointField, "https://example.com/uploads"), visible: all)
        addRow("region", "Region", styled(regionField, "us-east-1 (auto for Cloudflare R2)"), visible: { p, _ in p == .s3 })
        addRow("bucket", "Bucket", styled(bucketField, "cdn.example.com"), visible: { p, _ in p == .s3 })
        addRow("folder", "Remote folder", styled(folderField, "screenshots (relative to endpoint)"), visible: all)
        addRow("public", "Public base URL", styled(publicField, "https://example.com/screenshots (optional)"), visible: all)
        addRow("source", "Credentials", sourcePopup, visible: { p, _ in p == .s3 })
        addRow("profile", "AWS profile", styled(profileField, "default (from ~/.aws/credentials)"), visible: { p, keychain in p == .s3 && !keychain })
        addRow("username", "Username", styled(usernameField, "Username (optional for anonymous destinations)"),
               visible: { p, keychain in p == .s3 ? keychain : true })
        addRow("password", "Password", { passwordField.placeholderString = "Password stored in macOS Keychain"; return passwordField }(),
               visible: { p, keychain in p == .s3 ? keychain : p != .sftp })
        addRow("alias", "SSH host alias", styled(aliasField, "shoemoney.com (from ~/.ssh/config)"), visible: { p, _ in p == .sftp })
        addRow("root", "SFTP remote root", styled(remoteRootField, "/var/www/shoemoney.com/shared/imgs"), visible: { p, _ in p == .sftp })
        addRow("port", "SFTP port", styled(portField, "Use SSH configuration (optional)"), visible: { p, _ in p == .sftp })
        addRow("acl", "", aclCheckbox, visible: { p, _ in p == .s3 })
        formHelp.font = Self.font(18); formHelp.maximumNumberOfLines = 0; formHelp.preferredMaxLayoutWidth = 740
        formStatus.font = Self.font(18); formStatus.maximumNumberOfLines = 0; formStatus.preferredMaxLayoutWidth = 740
        formPage.addArrangedSubview(formHelp); formPage.addArrangedSubview(formStatus)
        let test = Self.button("Test", self, #selector(testTapped))
        let cancel = Self.button("Cancel", self, #selector(cancelFormTapped))
        let save = Self.button("Save", self, #selector(saveTapped))
        formButtons = (test, cancel, save)
        let buttons = NSStackView(views: [cancel, save, test]); buttons.spacing = 16
        formPage.addArrangedSubview(buttons)
        formPage.isHidden = true
    }
    private var formButtons: (test: NSButton, cancel: NSButton, save: NSButton)?

    private var keychainSource: Bool { sourcePopup.indexOfSelectedItem == 1 }
    private var selectedProtocol: PublishingProtocol {
        PublishingProtocol.allCases.indices.contains(protocolPopup.indexOfSelectedItem)
            ? PublishingProtocol.allCases[protocolPopup.indexOfSelectedItem] : .webDAV
    }

    @objc func formChanged() { refreshForm() }
    private func refreshForm() {
        let transport = selectedProtocol, keychain = keychainSource
        for row in rows.values { row.stack.isHidden = !row.visible(transport, keychain) }
        func caption(_ id: String, _ text: String) { rows[id]?.label.stringValue = text; rows[id]?.stack.arrangedSubviews.last?.setAccessibilityLabel(text) }
        switch transport {
        case .s3:
            caption("endpoint", "Endpoint (blank = AWS)"); caption("folder", "Key prefix")
            caption("username", "Access key ID"); caption("password", "Secret access key")
            formHelp.stringValue = "Path-style S3 over system curl. Public base URL maps to the key prefix; the uploaded file is downloaded from it to verify the exact bytes. Test lists the bucket without uploading."
        case .sftp:
            caption("endpoint", "Endpoint URL"); caption("folder", "Remote folder"); caption("username", "Username"); caption("password", "Password")
            formHelp.stringValue = "SFTP uses keys from SSH configuration or your agent, with strict known-host checks. Leave username and port empty to use the alias settings. Folders must exist."
        default:
            caption("endpoint", "Endpoint URL"); caption("folder", "Remote folder"); caption("username", "Username"); caption("password", "Password")
            formHelp.stringValue = "FTPS: ftp:// is explicit TLS, ftps:// is implicit TLS. Folders must exist. Public base URL maps to the upload folder; only the filename is appended."
        }
        formButtons?.test.isHidden = transport != .s3
    }

    /// Disables protocols the system tools cannot run.
    func setUnavailable(_ unavailable: Set<PublishingProtocol>) {
        for (index, transport) in PublishingProtocol.allCases.enumerated() { protocolPopup.item(at: index)?.isEnabled = !unavailable.contains(transport) }
    }

    private func showForm(for destination: PublishingDestination?) {
        editing = destination
        let settings = destination?.settings ?? PublishingSettings()
        nameField.stringValue = destination?.name ?? ""
        protocolPopup.selectItem(at: PublishingProtocol.allCases.firstIndex(of: settings.transport) ?? 0)
        endpointField.stringValue = settings.endpoint; usernameField.stringValue = settings.username
        folderField.stringValue = settings.remoteFolder; publicField.stringValue = settings.publicBaseURL
        aliasField.stringValue = settings.sshAlias; remoteRootField.stringValue = settings.sftpRemoteRoot
        portField.stringValue = settings.sftpPort.map(String.init) ?? ""
        let options = settings.s3 ?? S3Options()
        regionField.stringValue = options.region; bucketField.stringValue = options.bucket
        profileField.stringValue = options.credentialsProfile
        sourcePopup.selectItem(at: destination != nil && options.credentialsProfile.isEmpty && settings.transport == .s3 ? 1 : 0)
        aclCheckbox.state = options.publicReadACL ? .on : .off
        passwordField.stringValue = destination.map { settings.storesSecretInKeychain ? passwordFor($0) : "" } ?? ""
        formStatus.stringValue = ""
        listPage.isHidden = true; formPage.isHidden = false
        refreshForm()
    }

    /// Assembles the destination the form describes, preserving the edited entry's id.
    func makeDraft() throws -> (destination: PublishingDestination, password: String) {
        var settings = editing?.settings ?? PublishingSettings()
        let transport = selectedProtocol
        settings.transport = transport
        settings.endpoint = endpointField.stringValue; settings.remoteFolder = folderField.stringValue
        settings.publicBaseURL = publicField.stringValue
        settings.username = usernameField.stringValue
        settings.sshAlias = aliasField.stringValue; settings.sftpRemoteRoot = remoteRootField.stringValue
        let portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if portText.isEmpty { settings.sftpPort = nil }
        else {
            guard let port = Int(portText) else { throw PublishingFailure("SFTP port must be a number, or empty to use SSH configuration.") }
            settings.sftpPort = port
        }
        var password = transport == .sftp ? "" : passwordField.stringValue
        if transport == .s3 {
            var options = S3Options()
            options.region = regionField.stringValue; options.bucket = bucketField.stringValue
            options.publicReadACL = aclCheckbox.state == .on
            if keychainSource {
                guard !settings.username.isEmpty, !password.isEmpty else {
                    throw PublishingFailure("Enter the access key ID and secret, or choose an AWS credentials profile.")
                }
            } else {
                options.credentialsProfile = profileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !options.credentialsProfile.isEmpty else { throw PublishingFailure("Enter an AWS profile name, such as default.") }
                settings.username = ""; password = ""
            }
            settings.s3 = options
        } else { settings.s3 = nil }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = PublishingDestination(id: editing?.id ?? UUID().uuidString,
                                                name: typed.isEmpty ? settings.suggestedName : typed, settings: settings)
        return (destination, password)
    }

    @objc func saveTapped() {
        do { let draft = try makeDraft(); formStatus.stringValue = "Saving…"; onSave?(draft.destination, draft.password) }
        catch { formStatus.stringValue = error.localizedDescription }
    }
    @objc func testTapped() {
        do { let draft = try makeDraft(); formStatus.stringValue = "Testing…"; onTest?(draft.destination, draft.password) }
        catch { formStatus.stringValue = error.localizedDescription }
    }
    @objc func cancelFormTapped() { showList() }
}

extension PublishingProtocol {
    var shortTitle: String {
        switch self {
        case .webDAV: return "WebDAV"
        case .ftp: return "FTP"
        case .ftps: return "FTPS"
        case .sftp: return "SFTP"
        case .s3: return "S3"
        }
    }
}

private extension NSStackView {
    func setViews(_ views: [NSView], in gravity: NSStackView.Gravity) {
        views.forEach { addArrangedSubview($0) }
    }
}
