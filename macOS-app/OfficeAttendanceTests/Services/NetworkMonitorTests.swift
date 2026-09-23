import XCTest
import Network
@testable import OfficeAttendance

// MARK: - Tests

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

// MARK: - Office detection logic tests
//
// Rule: BOTH IP prefix AND DNS domain must match AND VPN must be inactive.
//
//  IP match | DNS match | VPN active | → isOnOffice
//  ---------+-----------+------------+-------------
//  yes      | yes       | no         | true
//  yes      | yes       | yes        | false  (VPN active suppresses detection)
//  yes      | no        | no         | false
//  no       | yes       | no         | false  (DNS alone unreliable — VPN injects corp domain)
//  no       | no        | no         | false

final class NetworkMonitorOfficeDetectionTests: XCTestCase {
    private var monitor: NetworkMonitor!
    private let creds = CredentialStore.Credentials(
        token: "", boardId: "", boardName: "", employeeId: "", employeeName: "",
        ipPrefix: "9.",
        dnsDomain: "ibm.com"
    )

    override func setUp() {
        super.setUp()
        monitor = NetworkMonitor()
    }

    // IP + DNS both match → office (the only true-positive case)
    func test_ipAndDnsMatch_isOffice() {
        XCTAssertTrue(monitor.isOnOfficeNetwork(
            ip: "9.1.2.3", dns: "corp.ibm.com", vpnActive: false, credentials: creds))
    }

    // VPN active suppresses office detection even when IP + DNS both match.
    func test_ipAndDnsMatch_vpnActive_notOffice() {
        XCTAssertFalse(monitor.isOnOfficeNetwork(
            ip: "9.1.2.3", dns: "corp.ibm.com", vpnActive: true, credentials: creds))
    }

    // IP matches but DNS doesn't → not office
    func test_ipMatchOnly_notOffice() {
        XCTAssertFalse(monitor.isOnOfficeNetwork(
            ip: "9.1.2.3", dns: "home.net", vpnActive: false, credentials: creds))
    }

    // DNS matches but IP doesn't → not office
    // Covers: at home on company VPN (DNS injected, IP is home address)
    func test_dnsMatchOnly_notOffice() {
        XCTAssertFalse(monitor.isOnOfficeNetwork(
            ip: "172.20.10.7", dns: "ibm.com", vpnActive: true, credentials: creds),
            "VPN-injected DNS without matching IP must not count as office")
    }

    // Neither matches → not office
    func test_noMatch_notOffice() {
        XCTAssertFalse(monitor.isOnOfficeNetwork(
            ip: "192.168.1.1", dns: "home.net", vpnActive: false, credentials: creds))
    }
}
