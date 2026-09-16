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

    func test_ipMatches_normalisesPrefix_withoutTrailingDot() {
        // "9" without trailing dot should still match "9.x.x.x"
        let monitor = NetworkMonitor()
        XCTAssertTrue(monitor.ipMatches(ip: "9.123.45.67", prefix: "9"))
    }

    func test_ipMatches_returnsFalse_forEmptyPrefix() {
        let monitor = NetworkMonitor()
        XCTAssertFalse(monitor.ipMatches(ip: "9.123.45.67", prefix: ""))
    }

    func test_dnsMatches_returnsTrue_forExactSuffix() {
        let monitor = NetworkMonitor()
        XCTAssertTrue(monitor.dnsMatches(domain: "ibm.com", suffix: "ibm.com"))
    }

    func test_dnsMatches_returnsFalse_forEmptySuffix() {
        let monitor = NetworkMonitor()
        XCTAssertFalse(monitor.dnsMatches(domain: "subdomain.ibm.com", suffix: ""))
    }
}
