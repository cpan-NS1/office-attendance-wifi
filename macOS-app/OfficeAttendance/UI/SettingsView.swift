import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var credentialStore: CredentialStore
    let mondayService: MondayService
    @ObservedObject var networkMonitor: NetworkMonitor
    var onSave: (() -> Void)?

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
        case .success: return true
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
                                    Link("Get your token at ibm.monday.com/apps/manage/tokens",
                                         destination: URL(string: "https://ibm.monday.com/apps/manage/tokens")!)
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            LabeledField("Board ID") {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("e.g. 1234567890", text: $boardId)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: boardId) { newValue in
                                            let filtered = newValue.filter(\.isNumber)
                                            if filtered != newValue { boardId = filtered }
                                        }
                                    Text("Found in the board URL: ibm.monday.com/boards/{boardId}")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            LabeledField("Employee ID") {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("e.g. 1234567 or 12345678", text: $employeeId)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: employeeId) { newValue in
                                            let filtered = String(newValue.filter(\.isNumber).prefix(8))
                                            if filtered != newValue { employeeId = filtered }
                                        }
                                    Text("7 or 8-digit ID found in the Employee ID column of the board.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                            Button("Verify Board") { Task { await verifyBoard() } }
                                .disabled(token.isEmpty || boardId.isEmpty)

                            switch verifyStatus {
                            case .idle:
                                EmptyView()
                            case .loading:
                                ProgressView("Checking…")
                            case .success(let map):
                                Text("✅ Mon(\(map.mondayColumnId)) Tue(\(map.tuesdayColumnId)) Wed(\(map.wednesdayColumnId)) Thu(\(map.thursdayColumnId)) Fri(\(map.fridayColumnId))")
                                    .font(.caption).foregroundColor(.secondary)
                            case .failure(let msg):
                                Text("❌ \(msg)").font(.caption).foregroundColor(.red)
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

    // MARK: - Actions

    private func verifyBoard() async {
        verifyStatus = .loading
        do {
            let map = try await mondayService.discoverColumns(boardId: boardId, token: token)
            columnMap = map
            manualEmployeeCol = map.employeeColumnId
            manualWeekStartCol = map.weekStartColumnId
            manualMon = map.mondayColumnId
            manualTue = map.tuesdayColumnId
            manualWed = map.wednesdayColumnId
            manualThu = map.thursdayColumnId
            manualFri = map.fridayColumnId
            verifyStatus = .success(map)
        } catch {
            verifyStatus = .failure(error.localizedDescription)
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
                fridayColumnId:    manualFri.isEmpty ? map.fridayColumnId    : manualFri
            )
        }
        try? credentialStore.save(token: token, boardId: boardId, employeeId: employeeId,
                                  ipPrefix: ipPrefix, dnsDomain: dnsDomain)
        credentialStore.saveColumnMap(map)
        NSApp.keyWindow?.close()
        onSave?()
    }

    private func loadExisting() {
        guard let creds = credentialStore.load() else { return }
        token = creds.token
        boardId = creds.boardId
        employeeId = creds.employeeId
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
