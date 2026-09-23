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
    private let session: URLSession
    /// Delay before the single retry on a transient network error (nanoseconds).
    /// Exposed for test injection only; production default is 4 s.
    let retryDelayNanoseconds: UInt64

    init(session: URLSession? = nil, retryDelayNanoseconds: UInt64 = 4_000_000_000) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

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

    // MARK: - History fetch

    /// Fetches all attendance statuses for the employee for the given month.
    /// Returns a dictionary keyed by "yyyy-MM-dd" ISO date strings.
    /// Weeks with no board row are silently skipped.
    func fetchMonthStatus(boardId: String,
                          employeeId: String,
                          columnMap: ColumnMap,
                          token: String,
                          month: Date) async throws -> [String: AttendanceStatus] {
        let weekStarts = weekStartDates(overlapping: month)
        var result: [String: AttendanceStatus] = [:]

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        let colIds = [
            (columnMap.mondayColumnId,    0),
            (columnMap.tuesdayColumnId,   1),
            (columnMap.wednesdayColumnId, 2),
            (columnMap.thursdayColumnId,  3),
            (columnMap.fridayColumnId,    4)
        ]

        try await withThrowingTaskGroup(of: [String: AttendanceStatus].self) { group in
            for weekStart in weekStarts {
                let weekStartStr = weekStartDateString(for: weekStart)
                group.addTask {
                    // Find the row for this week; skip if not found
                    guard let itemId = try? await self.findItemId(
                        boardId: boardId,
                        employeeId: employeeId,
                        weekStartDate: weekStartStr,
                        columnMap: columnMap,
                        token: token
                    ) else { return [:] }

                    let dayValues = try await self.fetchWeekDayValues(
                        itemId: itemId,
                        columnMap: columnMap,
                        token: token
                    )

                    var weekResult: [String: AttendanceStatus] = [:]
                    for (colId, dayOffset) in colIds {
                        guard let text = dayValues[colId],
                              let status = AttendanceStatus.allCases.first(where: { $0.mondayValue == text }),
                              let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
                        else { continue }
                        weekResult[isoFormatter.string(from: dayDate)] = status
                    }
                    return weekResult
                }
            }

            for try await weekResult in group {
                result.merge(weekResult) { _, remote in remote }
            }
        }

        return result
    }

    /// Returns every Monday date for weeks that overlap the given month.
    private func weekStartDates(overlapping month: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let monthStart = calendar.date(from: comps),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }
        let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart)!

        var starts: [Date] = []
        var current = weekStartDate(for: monthStart)
        while current <= monthEnd {
            starts.append(current)
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }
        return starts
    }

    // MARK: - Internal helpers

    private func findItemId(boardId: String, employeeId: String,
                            weekStartDate: String, columnMap: ColumnMap,
                            token: String) async throws -> String {
        let firstPageQuery = """
        query($boardId: ID!) {
          boards(ids: [$boardId]) {
            items_page(limit: 500) {
              cursor
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
        let nextPageQuery = """
        query($cursor: String!) {
          next_items_page(limit: 500, cursor: $cursor) {
            cursor
            items {
              id
              column_values(ids: ["\(columnMap.employeeColumnId)", "\(columnMap.weekStartColumnId)"]) {
                id text value
              }
            }
          }
        }
        """

        let decoder = JSONDecoder()
        func matchesTarget(_ item: [String: Any]) -> Bool {
            guard let colVals = item["column_values"] as? [[String: Any]] else { return false }
            let empMatch = colVals.contains {
                $0["id"] as? String == columnMap.employeeColumnId &&
                ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == employeeId
            }
            let weekMatch = colVals.contains {
                $0["id"] as? String == columnMap.weekStartColumnId &&
                (try? decoder.decode([String: String].self,
                    from: Data(($0["value"] as? String ?? "").utf8)))?["date"] == weekStartDate
            }
            return empMatch && weekMatch
        }

        // First page
        let firstPayload = try buildPayload(query: firstPageQuery, variables: ["boardId": boardId])
        let firstData = try await post(payload: firstPayload, token: token)
        let firstJson = try JSONSerialization.jsonObject(with: firstData) as? [String: Any]
        let firstErrors = (firstJson?["errors"] as? [[String: Any]]) ?? []
        if !firstErrors.isEmpty {
            throw MondayError.apiError(firstErrors.first?["message"] as? String ?? "unknown")
        }
        guard let firstPage = ((((firstJson?["data"] as? [String: Any])?["boards"] as? [[String: Any]])?.first)?["items_page"] as? [String: Any])
        else { throw MondayError.apiError("Unexpected response shape") }

        let firstItems = firstPage["items"] as? [[String: Any]] ?? []
        if let match = firstItems.first(where: matchesTarget),
           let id = match["id"] as? String { return id }

        // Subsequent pages via cursor
        var cursor = firstPage["cursor"] as? String
        var pageCount = 0
        let maxPages = 200 // 200 × 500 = 100 000 items; well above any real board
        while let activeCursor = cursor {
            pageCount += 1
            if pageCount > maxPages { throw MondayError.apiError("Pagination limit exceeded") }
            let payload = try buildPayload(query: nextPageQuery, variables: ["cursor": activeCursor])
            let data = try await post(payload: payload, token: token)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errors = (json?["errors"] as? [[String: Any]]) ?? []
            if !errors.isEmpty {
                throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
            }
            guard let page = (json?["data"] as? [String: Any])?["next_items_page"] as? [String: Any]
            else { throw MondayError.apiError("Unexpected response shape") }

            let items = page["items"] as? [[String: Any]] ?? []
            if let match = items.first(where: matchesTarget),
               let id = match["id"] as? String { return id }

            cursor = page["cursor"] as? String
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

    /// Fetches the five day-column text values for a known itemId.
    /// Returns a dict of columnId -> text (only non-empty values are included).
    private func fetchWeekDayValues(itemId: String,
                                     columnMap: ColumnMap,
                                     token: String) async throws -> [String: String] {
        let colIds = [columnMap.mondayColumnId, columnMap.tuesdayColumnId,
                      columnMap.wednesdayColumnId, columnMap.thursdayColumnId,
                      columnMap.fridayColumnId]
        let idsLiteral = colIds.map { "\"\($0)\"" }.joined(separator: ",")
        let query = """
        query($itemId: ID!) {
          items(ids: [$itemId]) {
            column_values(ids: [\(idsLiteral)]) {
              id text
            }
          }
        }
        """
        let payload = try buildPayload(query: query, variables: ["itemId": itemId])
        let data = try await post(payload: payload, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = (json?["errors"] as? [[String: Any]]) ?? []
        if !errors.isEmpty {
            throw MondayError.apiError(errors.first?["message"] as? String ?? "unknown")
        }
        guard let items = (json?["data"] as? [String: Any])?["items"] as? [[String: Any]],
              let colVals = items.first?["column_values"] as? [[String: Any]]
        else { throw MondayError.apiError("Unexpected response shape from items query") }

        var result: [String: String] = [:]
        for cv in colVals {
            guard let id = cv["id"] as? String,
                  let text = cv["text"] as? String,
                  !text.isEmpty else { continue }
            result[id] = text
        }
        return result
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

        // Retry once on transient connection errors that occur when the network
        // interface comes up but routes are not yet established (e.g. WiFi join,
        // wake from sleep).
        do {
            let (data, _) = try await session.data(for: request)
            return data
        } catch let urlError as URLError
            where urlError.code == .networkConnectionLost
               || urlError.code == .notConnectedToInternet {
            try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            let (data, _) = try await session.data(for: request)
            return data
        }
    }
}
