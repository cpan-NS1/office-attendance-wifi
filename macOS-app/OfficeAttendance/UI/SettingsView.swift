import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var credentialStore: CredentialStore
    let mondayService: MondayService
    @ObservedObject var networkMonitor: NetworkMonitor
    var onSave: (() -> Void)?

    @FocusState private var boardFieldFocused: Bool
    @State private var token = ""
    @State private var boardId = ""
    @State private var employeeId = ""
    @State private var ipPrefix = "9."
    @State private var dnsDomain = "ibm.com"
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var showAdvanced = false
    @State private var columnMap: ColumnMap? = nil
    @State private var launchAtLogin = false
    @State private var showInDock = false

    /// Set when auto-detect succeeds; nil means not yet detected or detection failed.
    @State private var detectedEmployeeName: String? = nil
    /// Tracks the state of the employee ID auto-fetch.
    @State private var fetchEmployeeStatus: FetchEmployeeStatus = .idle

    // Board picker state
    /// The list of boards fetched after a valid token is entered.
    @State private var boardList: [MondayService.Board] = []
    /// Tracks the board-fetch state.
    @State private var boardFetchStatus: BoardFetchStatus = .idle
    /// The text shown in the board search field (display name or raw ID if no boards loaded).
    @State private var boardSearchText = ""
    /// Whether the board dropdown overlay is visible.
    @State private var showBoardPicker = false
    /// Debounce task for board list fetching triggered by token changes.
    @State private var boardFetchTask: Task<Void, Never>? = nil
    /// In-flight board verify + employee-fetch task. Stored so it can be cancelled
    /// when the user selects a different board before the previous verify finishes.
    @State private var verifyTask: Task<Void, Never>? = nil

    enum BoardFetchStatus {
        case idle, loading, failed(String)
    }

    enum FetchEmployeeStatus {
        case idle, loading, failed(String)
    }

    // Advanced manual overrides
    @State private var manualEmployeeCol = ""
    @State private var manualWeekStartCol = ""
    @State private var manualMon = ""
    @State private var manualTue = ""
    @State private var manualWed = ""
    @State private var manualThu = ""
    @State private var manualFri = ""

    enum VerifyStatus {
        case idle, loading, success(ColumnMap), failure(String)
    }

    var canSave: Bool {
        switch verifyStatus {
        case .success: return !employeeId.isEmpty
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {

                    // MARK: Monday.com
                    GroupBox("Monday.com") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledField("API Token") {
                                VStack(alignment: .leading, spacing: 2) {
                                    SecureField("required", text: $token)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: token) { newToken in
                                            // Skip when loadExisting() restores the already-saved
                                            // token — nothing needs to change in that case.
                                            guard newToken != (credentialStore.load()?.token ?? "")
                                            else { return }
                                            // User changed the token: reset board state and kick off
                                            // a debounced fetch. boardSearchText is NOT cleared here;
                                            // that only happens inside scheduleBoardFetch when the
                                            // board field is focused.
                                            resetBoardState()
                                            scheduleBoardFetch(debounceSeconds: 0.3)
                                        }
                                    Link("Get your token at ibm.monday.com/apps/manage/tokens",
                                         destination: URL(string: "https://ibm.monday.com/apps/manage/tokens")!)
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            LabeledField("Board ID") {
                                VStack(alignment: .leading, spacing: 2) {
                                    boardPickerField
                                    if case .idle = boardFetchStatus, boardList.isEmpty, !token.isEmpty {
                                        Text("Found in the board URL: ibm.monday.com/boards/{boardId}")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if case .failed(let msg) = boardFetchStatus {
                                        Text("⚠️ \(msg) — enter the board ID manually.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            LabeledField("Employee ID") {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = detectedEmployeeName {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("\(employeeId) — \(name)")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Button("Change") {
                                                detectedEmployeeName = nil
                                                fetchEmployeeStatus = .idle
                                                employeeId = ""
                                            }
                                            .font(.caption)
                                        }
                                    } else {
                                        switch fetchEmployeeStatus {
                                        case .idle, .failed:
                                            TextField("Enter manually", text: $employeeId)
                                                .textFieldStyle(.roundedBorder)
                                                .onChange(of: employeeId) { newValue in
                                                    let filtered = String(newValue.filter(\.isNumber).prefix(8))
                                                    if filtered != newValue { employeeId = filtered }
                                                }
                                        case .loading:
                                            HStack(spacing: 6) {
                                                ProgressView().scaleEffect(0.7)
                                                Text("Looking up your employee ID…")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        if case .failed(let msg) = fetchEmployeeStatus {
                                            Text("⚠️ \(msg) — enter your ID manually.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: Network Detection
                    GroupBox("Network Detection") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledField("Office IP Prefix") {
                                TextField("e.g. 9.", text: $ipPrefix)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledField("Office DNS Domain") {
                                TextField("e.g. ibm.com", text: $dnsDomain)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Divider()
                            LabeledField("Current IP") {
                                Text(networkMonitor.detectedIP.isEmpty ? "—" : networkMonitor.detectedIP)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            LabeledField("Current DNS") {
                                Text(networkMonitor.detectedDNS.isEmpty ? "—" : networkMonitor.detectedDNS)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            LabeledField("VPN Active") {
                                if networkMonitor.isVPNActive {
                                    Text("Yes — office detection suppressed")
                                        .foregroundColor(.orange)
                                } else {
                                    Text("No")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: Board Verification
                    GroupBox("Board Verification") {
                        VStack(alignment: .leading, spacing: 8) {
                            switch verifyStatus {
                            case .idle:
                                EmptyView()
                            case .loading:
                                ProgressView("Checking…")
                            case .success(let map):
                                Text("✅ Mon(\(map.mondayColumnId)) Tue(\(map.tuesdayColumnId)) Wed(\(map.wednesdayColumnId)) Thu(\(map.thursdayColumnId)) Fri(\(map.fridayColumnId))")
                                    .font(.caption).foregroundColor(.secondary)
                            case .failure(let msg):
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("❌ \(msg)").font(.caption).foregroundColor(.red)
                                    Button("Re-verify") { startVerify() }
                                        .disabled(token.isEmpty || boardId.isEmpty)
                                }
                            }

                            DisclosureGroup("Advanced — manual column IDs", isExpanded: $showAdvanced) {
                                VStack(alignment: .leading, spacing: 6) {
                                    LabeledField("Employee col") {
                                        TextField("auto-detected", text: $manualEmployeeCol)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    LabeledField("Week Start col") {
                                        TextField("auto-detected", text: $manualWeekStartCol)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    LabeledField("Monday col")    { TextField("", text: $manualMon).textFieldStyle(.roundedBorder) }
                                    LabeledField("Tuesday col")   { TextField("", text: $manualTue).textFieldStyle(.roundedBorder) }
                                    LabeledField("Wednesday col") { TextField("", text: $manualWed).textFieldStyle(.roundedBorder) }
                                    LabeledField("Thursday col")  { TextField("", text: $manualThu).textFieldStyle(.roundedBorder) }
                                    LabeledField("Friday col")    { TextField("", text: $manualFri).textFieldStyle(.roundedBorder) }
                                }
                                .padding(.top, 6)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: General
                    GroupBox("General") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Start at login", isOn: $launchAtLogin)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: launchAtLogin) { enabled in
                                    do {
                                        if enabled {
                                            try SMAppService.mainApp.register()
                                        } else {
                                            try SMAppService.mainApp.unregister()
                                        }
                                    } catch {
                                        // Revert toggle if registration fails
                                        launchAtLogin = !enabled
                                    }
                                }
                            Toggle("Show in Dock", isOn: $showInDock)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: showInDock) { enabled in
                                    UserDefaults.standard.set(enabled, forKey: UserDefaults.Keys.showInDock)
                                    NSApp.setActivationPolicy(enabled ? .regular : .accessory)
                                }
                            Divider()
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .foregroundColor(.secondary)
                                Text("Press ⌥⌘A anytime to open the menu if the menu bar icon is hidden.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
            }
            .padding(20)

            // MARK: Bottom button bar
            Divider()
            HStack {
                Button("Cancel") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save") { saveCredentials() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadExisting()
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showInDock = UserDefaults.standard.bool(forKey: UserDefaults.Keys.showInDock)
        }
    }

    // MARK: - Board picker view

    @ViewBuilder
    private var boardPickerField: some View {
        // Always show the TextField so focus is never dropped during a fetch.
        // Loading feedback appears as a trailing spinner inside the HStack.
        HStack(spacing: 6) {
            TextField(boardList.isEmpty ? "e.g. 1234567890" : "Search boards…",
                      text: $boardSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($boardFieldFocused)
                .onChange(of: boardFieldFocused) { focused in
                    if focused, !token.isEmpty {
                        if boardList.isEmpty {
                            // No results yet — fetch now (no debounce, user is waiting).
                            scheduleBoardFetch(debounceSeconds: 0)
                        } else {
                            // Results already loaded — just open the picker.
                            showBoardPicker = true
                        }
                    } else if !focused {
                        // Next run-loop tick so a board button tap registers before dismiss.
                        DispatchQueue.main.async {
                            showBoardPicker = false
                        }
                    }
                }
                .onChange(of: boardSearchText) { newValue in
                    if boardList.isEmpty, boardFieldFocused {
                        // User is manually typing a raw board ID — restrict to digits (max 8).
                        // Guard on boardFieldFocused so loadExisting() restoring a saved board
                        // name (which contains letters) is never filtered out.
                        let filtered = String(newValue.filter(\.isNumber).prefix(8))
                        if filtered != newValue { boardSearchText = filtered }
                        boardId = filtered
                    } else if showBoardPicker {
                        // Keep picker open while the user types a search query.
                        // The guard prevents re-opening after selectBoard() closes it.
                        showBoardPicker = true
                    }
                }
                .popover(isPresented: $showBoardPicker, arrowEdge: .bottom) {
                    boardDropdownContent
                }
            if case .loading = boardFetchStatus {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    private var boardDropdownContent: some View {
        let filtered = boardList.filter {
            boardSearchText.isEmpty ||
            $0.name.localizedCaseInsensitiveContains(boardSearchText) ||
            $0.id.contains(boardSearchText)
        }
        return VStack(spacing: 0) {
            if filtered.isEmpty {
                Text("No matching boards")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { board in
                            Button(action: {
                                selectBoard(board)
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(board.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(board.id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(boardId == board.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(minWidth: 280)
    }

    private func selectBoard(_ board: MondayService.Board) {
        boardId = board.id
        boardSearchText = board.name
        showBoardPicker = false
        boardFieldFocused = false
        startVerify()
    }

    // MARK: - Actions

    /// Cancels any in-flight verify and starts a new one. Stores the task handle
    /// so concurrent calls (rapid board switches) cancel the previous attempt.
    private func startVerify() {
        verifyTask?.cancel()
        verifyTask = Task { await verifyBoard() }
    }

    private func verifyBoard() async {
        // Capture the board/token at the moment verify was requested so that
        // state changes mid-flight don't affect which result we write back.
        let boardIdSnapshot = boardId
        let tokenSnapshot = token
        verifyStatus = .loading
        do {
            let map = try await mondayService.discoverColumns(boardId: boardIdSnapshot, token: tokenSnapshot)
            guard !Task.isCancelled else { return }
            columnMap = map
            manualEmployeeCol = map.employeeColumnId
            manualWeekStartCol = map.weekStartColumnId
            manualMon = map.mondayColumnId
            manualTue = map.tuesdayColumnId
            manualWed = map.wednesdayColumnId
            manualThu = map.thursdayColumnId
            manualFri = map.fridayColumnId
            verifyStatus = .success(map)
            // Reset fetch state when board changes
            detectedEmployeeName = nil
            fetchEmployeeStatus = .idle
            // Auto-fetch employee ID immediately after board is verified
            await fetchEmployeeId(boardId: boardIdSnapshot, token: tokenSnapshot, map: map)
        } catch {
            guard !Task.isCancelled else { return }
            verifyStatus = .failure(error.localizedDescription)
        }
    }

    /// Fetches the boards list in the background.
    /// Pass `debounceSeconds: 0` to fire immediately (e.g. on field focus),
    /// or a positive value to debounce rapid token edits (e.g. token paste).
    /// The popover is only opened when the board field is focused so that
    /// restoring saved credentials on Settings open doesn't pop the picker.
    private func scheduleBoardFetch(debounceSeconds: Double = 0) {
        boardFetchTask?.cancel()
        boardList = []
        boardFetchStatus = .idle
        guard !token.isEmpty else { return }
        boardFetchStatus = .loading
        boardFetchTask = Task {
            if debounceSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            do {
                let boards = try await mondayService.fetchBoards(token: token)
                boardList = boards
                boardFetchStatus = .idle
                // Only open the picker and clear the search field when the user is
                // actively focused on the Board ID field. When restoring saved settings
                // on onAppear the field is not focused, so nothing pops up.
                if boardFieldFocused {
                    boardSearchText = ""
                    showBoardPicker = true
                }
            } catch {
                boardFetchStatus = .failed(error.localizedDescription)
            }
        }
    }

    /// Resets board-related state when the token changes.
    /// Does NOT clear boardSearchText — that is handled inside scheduleBoardFetch
    /// only when the board field is focused, preventing loadExisting() from wiping
    /// a saved board name when it sets token = creds.token.
    private func resetBoardState() {
        boardList = []
        boardFetchStatus = .idle
        boardFetchTask?.cancel()
        verifyTask?.cancel()
        verifyStatus = .idle
    }

    /// Looks up the current user's employee ID on the board.
    /// Parameters are passed explicitly (not read from self) so the result is
    /// always consistent with the board/token that was verified, even if the
    /// user changes their selection while this is in flight.
    private func fetchEmployeeId(boardId: String, token: String, map: ColumnMap) async {
        guard let peopleColId = map.peopleColumnId else {
            fetchEmployeeStatus = .failed("This board has no People column")
            return
        }
        fetchEmployeeStatus = .loading
        do {
            let user = try await mondayService.fetchCurrentUser(token: token)
            guard !Task.isCancelled else { return }
            let empId = try await mondayService.findEmployeeId(
                boardId: boardId,
                mondayUserId: user.id,
                peopleColumnId: peopleColId,
                employeeIdColumnId: map.employeeColumnId,
                token: token
            )
            guard !Task.isCancelled else { return }
            employeeId = empId
            detectedEmployeeName = user.name
            fetchEmployeeStatus = .idle
        } catch {
            guard !Task.isCancelled else { return }
            fetchEmployeeStatus = .failed(error.localizedDescription)
        }
    }

    private func saveCredentials() {
        guard case .success(var map) = verifyStatus else { return }
        if showAdvanced {
            map = ColumnMap(
                employeeColumnId:  manualEmployeeCol.isEmpty  ? map.employeeColumnId  : manualEmployeeCol,
                weekStartColumnId: manualWeekStartCol.isEmpty ? map.weekStartColumnId : manualWeekStartCol,
                mondayColumnId:    manualMon.isEmpty ? map.mondayColumnId    : manualMon,
                tuesdayColumnId:   manualTue.isEmpty ? map.tuesdayColumnId   : manualTue,
                wednesdayColumnId: manualWed.isEmpty ? map.wednesdayColumnId : manualWed,
                thursdayColumnId:  manualThu.isEmpty ? map.thursdayColumnId  : manualThu,
                fridayColumnId:    manualFri.isEmpty ? map.fridayColumnId    : manualFri,
                peopleColumnId:    map.peopleColumnId
            )
        }
        try? credentialStore.save(token: token, boardId: boardId, boardName: boardSearchText,
                                  employeeId: employeeId,
                                  employeeName: detectedEmployeeName ?? "",
                                  ipPrefix: ipPrefix, dnsDomain: dnsDomain)
        credentialStore.saveColumnMap(map)
        NSApp.keyWindow?.close()
        onSave?()
    }

    private func loadExisting() {
        guard let creds = credentialStore.load() else { return }
        // Assign all fields in one synchronous block. SwiftUI batches these state
        // changes and fires onChange handlers after the block completes.
        // onChange(of: token) will fire, but resetBoardState() does NOT clear
        // boardSearchText, so the board name we set here is preserved.
        token = creds.token
        boardId = creds.boardId
        // Show saved name if available, fall back to raw ID for old configs
        boardSearchText = creds.boardName.isEmpty ? creds.boardId : creds.boardName
        employeeId = creds.employeeId
        if !creds.employeeName.isEmpty {
            detectedEmployeeName = creds.employeeName
        }
        ipPrefix = creds.ipPrefix
        dnsDomain = creds.dnsDomain
        // Restore saved column map so Save is enabled without re-verifying
        if let map = credentialStore.loadColumnMap() {
            columnMap = map
            manualEmployeeCol = map.employeeColumnId
            manualWeekStartCol = map.weekStartColumnId
            manualMon = map.mondayColumnId
            manualTue = map.tuesdayColumnId
            manualWed = map.wednesdayColumnId
            manualThu = map.thursdayColumnId
            manualFri = map.fridayColumnId
            verifyStatus = .success(map)
        }
        // Board list is fetched on demand when the user taps the Board ID field.
        // Nothing to do here — boardSearchText already shows the board name.
    }
}

// MARK: - Helper

private struct LabeledField<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 130, alignment: .trailing)
                .foregroundColor(.secondary)
            content
        }
    }
}
