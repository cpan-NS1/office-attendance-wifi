import XCTest
import Network
@testable import OfficeAttendance

final class NetworkMonitorTests: XCTestCase {
    func test_evaluate_returnsTrue_whenIPMatches() {
        let monitor = NetworkMonitor()
        // evaluate is tested via the helper that checks IP prefix
        let result = monitor.ipMatches(ip: "9.123.45.67", prefix: "9.")
        XCTAssertTrue(result)
    }

    func test_evaluate_returnsFalse_whenIPDoesNotMatch() {
        let monitor = NetworkMonitor()
        let result = monitor.ipMatches(ip: "192.168.1.1", prefix: "9.")
        XCTAssertFalse(result)
    }

    func test_evaluate_returnsTrue_whenDNSMatches() {
        let monitor = NetworkMonitor()
        let result = monitor.dnsMatches(domain: "subdomain.ibm.com", suffix: "ibm.com")
        XCTAssertTrue(result)
    }

    func test_evaluate_returnsFalse_whenBothEmpty() {
        let monitor = NetworkMonitor()
        let resultIP  = monitor.ipMatches(ip: "", prefix: "9.")
        let resultDNS = monitor.dnsMatches(domain: "", suffix: "ibm.com")
        XCTAssertFalse(resultIP)
        XCTAssertFalse(resultDNS)
    }
}
