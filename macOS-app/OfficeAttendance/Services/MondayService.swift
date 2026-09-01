import Foundation

enum MondayError: Error, LocalizedError {
    case noRowFound
    case columnNotFound(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noRowFound:               return "No attendance row found for this week."
        case .columnNotFound(let name): return "Column \"\(name)\" not found on the board. Check your board column titles."
        case .apiError(let msg):        return "Monday.com API error: \(msg)"
        }
    }
}

final class MondayService {
    private let endpoint = URL(string: "https://api.monday.com/v2")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Column Discovery

    func discoverColumns(boardId: String, token: String) async throws -> ColumnMap {
        let query = """
        query($boardId: ID!) {
          boards(ids: [$boardId]) {
            columns { id title type }
          }
        }
        """
        let payload = try buildPayload(query: query, variables: ["boardId": boardId])
        let data = try await post(payload: payload, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
        guard let columns = (((json?["data"] as? [String: Any])?["boards"] as? [[String: Any]])?.first)?["columns"] as? [[String: Any]]
        else { throw MondayError.apiError("Unexpected response shape") }

        func id(forTitle title: String) throws -> String {
            guard let col = columns.first(where: { ($0["title"] as? String) == title }),
                  let id = col["id"] as? String else {
                throw MondayError.columnNotFound(title)
            }
            return id
        }

        // Try common employee column name variants
        func employeeId() throws -> String {
            for title in ["Employee ID", "Employee name", "Employee", "Name"] {
                if let col = columns.first(where: { ($0["title"] as? String) == title }),
                   let id = col["id"] as? String { return id }
            }
            let available = columns.compactMap { $0["title"] as? String }.joined(separator: ", ")
            throw MondayError.columnNotFound("employee column (tried: Employee ID, Employee name, Employee, Name). Available: \(available)")
        }

        return ColumnMap(
            employeeColumnId:   try employeeId(),
            weekStartColumnId:  try id(forTitle: "Week Start"),
            mondayColumnId:     try id(forTitle: "Monday"),
            tuesdayColumnId:    try id(forTitle: "Tuesday"),
            wednesdayColumnId:  try id(forTitle: "Wednesday"),
            thursdayColumnId:   try id(forTitle: "Thursday"),
            fridayColumnId:     try id(forTitle: "Friday")
        )
    }

    // MARK: - Check-in

    func checkIn(status: AttendanceStatus,
                 credentials: CredentialStore.Credentials,
                 columnMap: ColumnMap) async throws {
        let today = Date()
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: today)

        guard let dayColumnId = columnMap.columnId(forWeekday: weekday) else {
            throw MondayError.columnNotFound("today's weekday")
        }

        // Step 1: find the item_id for this person's row this week
        let itemId = try await findItemId(
            boardId: credentials.boardId,
            employeeId: credentials.employeeId,
            weekStartDate: weekStartDateString(for: today),
            columnMap: columnMap,
            token: credentials.token
        )

        // Step 2: write the status to today's column
        let mutation = """
        mutation($boardId: ID!, $itemId: ID!, $columnId: String!, $value: String!) {
          change_simple_column_value(
            board_id: $boardId, item_id: $itemId,
            column_id: $columnId, value: $value
          ) { id }
        }
        """
        let vars: [String: Any] = [
            "boardId":  credentials.boardId,
            "itemId":   itemId,
            "columnId": dayColumnId,
            "value":    status.mondayValue
        ]
        let payload = try buildPayload(query: mutation, variables: vars)
        let data = try await post(payload: payload, token: credentials.token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
    }

    // MARK: - Internal helpers

    private func findItemId(boardId: String, employeeId: String,
                            weekStartDate: String, columnMap: ColumnMap,
                            token: String) async throws -> String {
        let query = """
        query($boardId: ID!) {
          boards(ids: [$boardId]) {
            items_page(limit: 500) {
              items {
                id
                column_values(ids: ["\(columnMap.employeeColumnId)", "\(columnMap.weekStartColumnId)"]) {
                  id text value
                }
              }
            }
          }
        }
        """
        let payload = try buildPayload(query: query, variables: ["boardId": boardId])
        let data = try await post(payload: payload, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
        guard let items = ((((json?["data"] as? [String: Any])?["boards"] as? [[String: Any]])?.first)?["items_page"] as? [String: Any])?["items"] as? [[String: Any]]
        else { throw MondayError.apiError("Unexpected response shape") }

        for item in items {
            guard let id = item["id"] as? String,
                  let colVals = item["column_values"] as? [[String: Any]] else { continue }

            let empMatch = colVals.contains {
                $0["id"] as? String == columnMap.employeeColumnId &&
                $0["text"] as? String == employeeId
            }
            let weekMatch = colVals.contains {
                $0["id"] as? String == columnMap.weekStartColumnId &&
                (try? (JSONDecoder().decode([String: String].self,
                    from: Data(($0["value"] as? String ?? "").utf8)))["date"]) == weekStartDate
            }
            if empMatch && weekMatch { return id }
        }
        throw MondayError.noRowFound
    }

    func weekStartDate(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)!
    }

    func weekStartDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: weekStartDate(for: date))
    }

    private func buildPayload(query: String, variables: [String: Any]) throws -> Data {
        let body: [String: Any] = ["query": query, "variables": variables]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func post(payload: Data, token: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        let (data, _) = try await session.data(for: request)
        return data
    }
}
