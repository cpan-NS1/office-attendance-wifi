import SwiftUI

struct SettingsView: View {
    @ObservedObject var credentialStore: CredentialStore
    let mondayService: MondayService
    var onSave: (() -> Void)?

    @State private var token = ""
    @State private var boardId = ""
    @State private var employeeId = ""
    @State private var ipPrefix = "9."
    @State private var dnsDomain = "ibm.com"
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var showAdvanced = false
    @State private var columnMap: ColumnMap? = nil

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
        Form {
            Section("Monday.com") {
                SecureField("API Token", text: $token)
                TextField("Board ID", text: $boardId)
                TextField("Employee ID (name as shown on board)", text: $employeeId)
            }

            Section("Network Detection") {
                TextField("Office IP Prefix (e.g. 9.)", text: $ipPrefix)
                TextField("Office DNS Domain (e.g. ibm.com)", text: $dnsDomain)
            }

            Section("Board Verification") {
                Button("Verify Board") { Task { await verifyBoard() } }
                    .disabled(token.isEmpty || boardId.isEmpty)
                switch verifyStatus {
                case .idle: EmptyView()
                case .loading: ProgressView("Checking…")
                case .success(let map):
                    Text("✅ Monday(\(map.mondayColumnId)) Tue(\(map.tuesdayColumnId)) Wed(\(map.wednesdayColumnId)) Thu(\(map.thursdayColumnId)) Fri(\(map.fridayColumnId))")
                        .font(.caption).foregroundColor(.secondary)
                case .failure(let msg):
                    Text("❌ \(msg)").font(.caption).foregroundColor(.red)
                }

                DisclosureGroup("Advanced (manual column IDs)", isExpanded: $showAdvanced) {
                    TextField("Employee name column ID", text: $manualEmployeeCol)
                    TextField("Week Start column ID", text: $manualWeekStartCol)
                    TextField("Monday column ID", text: $manualMon)
                    TextField("Tuesday column ID", text: $manualTue)
                    TextField("Wednesday column ID", text: $manualWed)
                    TextField("Thursday column ID", text: $manualThu)
                    TextField("Friday column ID", text: $manualFri)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { NSApp.keyWindow?.close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveCredentials() }
                    .disabled(!canSave)
            }
        }
        .onAppear { loadExisting() }
    }

    private func verifyBoard() async {
        verifyStatus = .loading
        do {
            let map = try await mondayService.discoverColumns(boardId: boardId, token: token)
            columnMap = map
            // Pre-fill advanced fields
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
        // Apply manual overrides if advanced fields were edited
        if showAdvanced {
            map = ColumnMap(employeeColumnId: manualEmployeeCol.isEmpty ? map.employeeColumnId : manualEmployeeCol,
                            weekStartColumnId: manualWeekStartCol.isEmpty ? map.weekStartColumnId : manualWeekStartCol,
                            mondayColumnId: manualMon.isEmpty ? map.mondayColumnId : manualMon,
                            tuesdayColumnId: manualTue.isEmpty ? map.tuesdayColumnId : manualTue,
                            wednesdayColumnId: manualWed.isEmpty ? map.wednesdayColumnId : manualWed,
                            thursdayColumnId: manualThu.isEmpty ? map.thursdayColumnId : manualThu,
                            fridayColumnId: manualFri.isEmpty ? map.fridayColumnId : manualFri)
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
    }
}
