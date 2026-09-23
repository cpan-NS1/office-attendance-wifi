import XCTest
import Foundation
@testable import OfficeAttendance

// MARK: - URLProtocol stub for retry tests

/// A URLProtocol that returns a configurable sequence of responses.
/// Each element in `responses` is used for one request in order.
final class SequencedURLProtocol: URLProtocol {
    /// Each element: either `.success(Data)` or `.failure(URLError)`.
    enum Response {
        case success(Data)
        case failure(URLError)
    }

    /// Set before each test; consumed in FIFO order.
    static var responses: [Response] = []
    private static let lock = NSLock()

    static func nextResponse() -> Response {
        lock.lock(); defer { lock.unlock() }
        guard !responses.isEmpty else {
            fatalError("SequencedURLProtocol: no more responses queued")
        }
        return responses.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.nextResponse() {
        case .success(let data):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Convenience: build a URLSession backed by this protocol (no caching, no cookies).
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SequencedURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }
}

final class MondayServiceTests: XCTestCase {
    func test_weekStartDate_isAlwaysMonday() {
        let service = MondayService()
        let calendar = Calendar(identifier: .gregorian)
        // Use a known Wednesday: 2025-07-16
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let wednesday = calendar.date(from: components)!
        let weekStart = service.weekStartDate(for: wednesday)
        let weekday = calendar.component(.weekday, from: weekStart)
        XCTAssertEqual(weekday, 2, "Week start should be Monday (weekday=2)")
    }

    func test_weekStartDate_formatsAsISO() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 16
        let calendar = Calendar(identifier: .gregorian)
        let wednesday = calendar.date(from: components)!
        let result = service.weekStartDateString(for: wednesday)
        XCTAssertEqual(result, "2025-07-14")
    }

    // A Friday in the last week of a month whose last day is mid-week; the
    // returned Monday must still be <= the last day, so it's included.
    func test_weekStartDate_returnsCorrectMonday_forFridayInLastWeekOfMonth() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 31 // Friday
        let calendar = Calendar(identifier: .gregorian)
        let friday = calendar.date(from: components)!
        let weekStart = service.weekStartDate(for: friday)
        let startComps = calendar.dateComponents([.year, .month, .day], from: weekStart)
        XCTAssertEqual(startComps.year, 2025)
        XCTAssertEqual(startComps.month, 1)
        XCTAssertEqual(startComps.day, 27) // Monday 27 Jan 2025
    }

    func test_weekStartDateString_formatsMonday_forFriday() {
        let service = MondayService()
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 31
        let calendar = Calendar(identifier: .gregorian)
        let friday = calendar.date(from: components)!
        XCTAssertEqual(service.weekStartDateString(for: friday), "2025-01-27")
    }
}

final class MondayErrorTests: XCTestCase {
    func test_noRowFound_hasNonEmptyDescription() {
        XCTAssertFalse((MondayError.noRowFound.errorDescription ?? "").isEmpty)
    }

    func test_columnNotFound_includesColumnName() {
        let desc = MondayError.columnNotFound("Monday").errorDescription ?? ""
        XCTAssertTrue(desc.contains("Monday"), "Expected column name in: \(desc)")
    }

    func test_apiError_includesMessage() {
        let desc = MondayError.apiError("token expired").errorDescription ?? ""
        XCTAssertTrue(desc.contains("token expired"), "Expected message in: \(desc)")
    }
}

// MARK: - Retry tests

/// Verifies that MondayService retries once on transient URLErrors so that
/// a "network connection lost" during a WiFi join / wake-from-sleep does not
/// leave the coordinator in a permanent error state.
final class MondayServiceRetryTests: XCTestCase {

    // Valid minimal GraphQL success response that satisfies discoverColumns.
    private let successJSON: Data = {
        let payload: [String: Any] = [
            "data": [
                "boards": [[
                    "columns": [
                        ["id": "person",     "title": "Employee",   "type": "people"],
                        ["id": "week_start", "title": "Week Start", "type": "date"],
                        ["id": "mon",        "title": "Monday",     "type": "text"],
                        ["id": "tue",        "title": "Tuesday",    "type": "text"],
                        ["id": "wed",        "title": "Wednesday",  "type": "text"],
                        ["id": "thu",        "title": "Thursday",   "type": "text"],
                        ["id": "fri",        "title": "Friday",     "type": "text"],
                    ]
                ]]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }()

    override func setUp() {
        super.setUp()
        SequencedURLProtocol.responses = []
    }

    /// First request returns networkConnectionLost; retry succeeds → no throw.
    func test_post_retriesOnNetworkConnectionLost() async throws {
        SequencedURLProtocol.responses = [
            .failure(URLError(.networkConnectionLost)),
            .success(successJSON),
        ]
        let service = MondayService(session: SequencedURLProtocol.makeSession(), retryDelayNanoseconds: 0)
        // discoverColumns internally calls post() — if retry works this should not throw.
        _ = try await service.discoverColumns(boardId: "123", token: "tok")
        XCTAssertTrue(SequencedURLProtocol.responses.isEmpty, "Both responses should have been consumed")
    }

    /// First request returns notConnectedToInternet; retry succeeds → no throw.
    func test_post_retriesOnNotConnectedToInternet() async throws {
        SequencedURLProtocol.responses = [
            .failure(URLError(.notConnectedToInternet)),
            .success(successJSON),
        ]
        let service = MondayService(session: SequencedURLProtocol.makeSession(), retryDelayNanoseconds: 0)
        _ = try await service.discoverColumns(boardId: "123", token: "tok")
        XCTAssertTrue(SequencedURLProtocol.responses.isEmpty, "Both responses should have been consumed")
    }

    /// A non-transient error (e.g. timedOut) is NOT retried and propagates immediately.
    func test_post_doesNotRetryOnNonTransientError() async {
        SequencedURLProtocol.responses = [
            .failure(URLError(.timedOut)),
            // A second response would be consumed if a retry happened — we expect it NOT to be.
            .success(successJSON),
        ]
        let service = MondayService(session: SequencedURLProtocol.makeSession(), retryDelayNanoseconds: 0)
        do {
            _ = try await service.discoverColumns(boardId: "123", token: "tok")
            XCTFail("Expected an error to be thrown")
        } catch let urlError as URLError {
            XCTAssertEqual(urlError.code, .timedOut)
            // The success response was NOT consumed — only one request was made.
            XCTAssertEqual(SequencedURLProtocol.responses.count, 1,
                           "Second response should not have been consumed on non-transient error")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Pagination tests

/// Verifies that findItemId walks all pages via cursor-based pagination so that
/// a new user whose row sits beyond the first 500 items is found correctly.
///
/// Tests exercise findItemId indirectly through checkIn (the only caller that
/// takes a fully-controllable path). Each test uses SequencedURLProtocol to
/// inject exact HTTP responses for every API call checkIn makes.
final class MondayServicePaginationTests: XCTestCase {

    // MARK: - Shared fixtures

    private let columnMap = ColumnMap(
        employeeColumnId:   "emp_col",
        weekStartColumnId:  "week_col",
        mondayColumnId:     "mon_col",
        tuesdayColumnId:    "tue_col",
        wednesdayColumnId:  "wed_col",
        thursdayColumnId:   "thu_col",
        fridayColumnId:     "fri_col"
    )

    private let credentials = CredentialStore.Credentials(
        token: "test-token",
        boardId: "board-1",
        employeeId: "1058851",
        ipPrefix: "",
        dnsDomain: ""
    )

    /// Builds an items_page JSON response.
    /// - Parameters:
    ///   - items: Array of item dictionaries to include.
    ///   - cursor: If non-nil, included as the pagination cursor (more pages available).
    private func itemsPageJSON(items: [[String: Any]], cursor: String?) -> Data {
        var page: [String: Any] = ["items": items]
        if let cursor { page["cursor"] = cursor }
        let payload: [String: Any] = [
            "data": ["boards": [["items_page": page]]]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    /// Builds a next_items_page JSON response.
    private func nextItemsPageJSON(items: [[String: Any]], cursor: String?) -> Data {
        var page: [String: Any] = ["items": items]
        if let cursor { page["cursor"] = cursor }
        let payload: [String: Any] = [
            "data": ["next_items_page": page]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    /// Builds a minimal mutation success response.
    private var mutationSuccessJSON: Data {
        let payload: [String: Any] = [
            "data": ["change_simple_column_value": ["id": "item-99"]]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    /// The ISO week-start string for the current week (matches what checkIn computes internally).
    private var currentWeekStart: String {
        MondayService().weekStartDateString(for: Date())
    }

    /// Builds a board item whose employee and week-start columns match the test credentials/date.
    private func matchingItem(id: String = "item-99") -> [String: Any] {
        let ws = currentWeekStart
        return [
            "id": id,
            "column_values": [
                ["id": "emp_col",  "text": "1058851", "value": "\"1058851\""],
                ["id": "week_col", "text": ws, "value": "{\"date\":\"\(ws)\"}"]
            ]
        ]
    }

    /// Builds a board item that does NOT match (different employee).
    private func nonMatchingItem(id: String) -> [String: Any] {
        let ws = currentWeekStart
        return [
            "id": id,
            "column_values": [
                ["id": "emp_col",  "text": "0000001", "value": "\"0000001\""],
                ["id": "week_col", "text": ws, "value": "{\"date\":\"\(ws)\"}"]
            ]
        ]
    }

    override func setUp() {
        super.setUp()
        SequencedURLProtocol.responses = []
    }

    // MARK: - Tests

    /// Match found on page 1: cursor is present but should never be followed.
    /// Expected network calls: 1 (items_page) + 1 (mutation) = 2 total.
    func test_findItemId_matchOnFirstPage_doesNotFetchSecondPage() async throws {
        // Page 1 contains the matching item; cursor signals more pages exist
        // but should never be consumed.
        let page1 = itemsPageJSON(items: [matchingItem()], cursor: "cursor-abc")
        SequencedURLProtocol.responses = [
            .success(page1),
            .success(mutationSuccessJSON),
        ]

        let service = MondayService(session: SequencedURLProtocol.makeSession(),
                                    retryDelayNanoseconds: 0)
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date())
        try XCTSkipIf(weekday == 1 || weekday == 7, "Skipped: test requires a weekday")

        try await service.checkIn(status: .office, credentials: credentials, columnMap: columnMap)

        XCTAssertTrue(SequencedURLProtocol.responses.isEmpty,
                      "Both responses should be consumed (1 items_page + 1 mutation)")
    }

    /// Match found on page 2: first page has no match + cursor, second page has the match.
    /// Expected network calls: 1 (items_page) + 1 (next_items_page) + 1 (mutation) = 3 total.
    func test_findItemId_matchOnSecondPage_consumesCursor() async throws {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date())
        try XCTSkipIf(weekday == 1 || weekday == 7, "Skipped: test requires a weekday")

        let page1 = itemsPageJSON(items: [nonMatchingItem(id: "item-01")], cursor: "cursor-page2")
        let page2 = nextItemsPageJSON(items: [matchingItem()], cursor: nil)

        SequencedURLProtocol.responses = [
            .success(page1),
            .success(page2),
            .success(mutationSuccessJSON),
        ]

        let service = MondayService(session: SequencedURLProtocol.makeSession(),
                                    retryDelayNanoseconds: 0)
        try await service.checkIn(status: .office, credentials: credentials, columnMap: columnMap)

        XCTAssertTrue(SequencedURLProtocol.responses.isEmpty,
                      "All 3 responses should be consumed (items_page + next_items_page + mutation)")
    }

    /// All pages exhausted with no match → .noRowFound thrown (mutation never called).
    /// Expected network calls: 1 (items_page) + 1 (next_items_page) = 2 total.
    func test_findItemId_noMatchOnAnyPage_throwsNoRowFound() async throws {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date())
        try XCTSkipIf(weekday == 1 || weekday == 7, "Skipped: test requires a weekday")

        let page1 = itemsPageJSON(items: [nonMatchingItem(id: "item-01")], cursor: "cursor-page2")
        let page2 = nextItemsPageJSON(items: [nonMatchingItem(id: "item-02")], cursor: nil)

        SequencedURLProtocol.responses = [
            .success(page1),
            .success(page2),
        ]

        let service = MondayService(session: SequencedURLProtocol.makeSession(),
                                    retryDelayNanoseconds: 0)
        do {
            try await service.checkIn(status: .office, credentials: credentials, columnMap: columnMap)
            XCTFail("Expected MondayError.noRowFound to be thrown")
        } catch MondayError.noRowFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(SequencedURLProtocol.responses.isEmpty,
                      "Both page responses should be consumed before throwing")
    }
}
