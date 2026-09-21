import Foundation
import Network
import Combine
import SystemConfiguration

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnOfficeNetwork: Bool = false
    @Published private(set) var detectedIP: String = ""
    @Published private(set) var detectedDNS: String = ""
    @Published private(set) var isVPNActive: Bool = false

    /// Override in tests to stub VPN state without touching live interfaces.
    var vpnChecker: () -> Bool = { NetworkMonitor.checkVPNActive() }

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.ibm.office-attendance.network")
    private var credentials: CredentialStore.Credentials?

    func start(credentials: CredentialStore.Credentials) {
        self.credentials = credentials
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self, let creds = self.credentials else { return }
            let ip = self.currentIPAddress() ?? ""
            let dns = self.currentDNSDomain() ?? ""
            let result = self.evaluate(path: path, credentials: creds)
            DispatchQueue.main.async {
                self.detectedIP = ip
                self.detectedDNS = dns
                self.isOnOfficeNetwork = result
            }
        }
        m.start(queue: queue)
        monitor = m
        // Evaluate synchronously on the caller (main) thread so isOnOfficeNetwork
        // reflects the real value before any subscriber is attached. The IP/DNS
        // reads are fast syscalls and safe to call on the main thread.
        evaluateAndPublishCurrentNetwork(credentials: credentials)
    }

    /// Evaluates the current network state and publishes the result on the main thread.
    /// Safe to call from any thread; publishes synchronously when already on main.
    func checkCurrentNetwork(credentials: CredentialStore.Credentials) {
        if Thread.isMainThread {
            evaluateAndPublishCurrentNetwork(credentials: credentials)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluateAndPublishCurrentNetwork(credentials: credentials)
            }
        }
    }

    // MARK: - Private helpers

    private func evaluateAndPublishCurrentNetwork(credentials: CredentialStore.Credentials) {
        let ip = currentIPAddress() ?? ""
        let dns = currentDNSDomain() ?? ""
        let vpn = vpnChecker()
        let result = !vpn
                  && (ipMatches(ip: ip, prefix: credentials.ipPrefix)
                   || dnsMatches(domain: dns, suffix: credentials.dnsDomain))
        detectedIP = ip
        detectedDNS = dns
        isVPNActive = vpn
        isOnOfficeNetwork = result
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Testable helpers

    func evaluate(path: NWPath, credentials: CredentialStore.Credentials) -> Bool {
        guard !vpnChecker() else { return false }
        let ip = currentIPAddress() ?? ""
        let dns = currentDNSDomain() ?? ""
        return ipMatches(ip: ip, prefix: credentials.ipPrefix)
            || dnsMatches(domain: dns, suffix: credentials.dnsDomain)
    }

    /// Requires the prefix to end with "." so that "9." matches "9.x.x.x"
    /// but NOT "192.168.x.x" or a home network that happens to share a leading digit.
    func ipMatches(ip: String, prefix: String) -> Bool {
        guard !ip.isEmpty, !prefix.isEmpty else { return false }
        let p = prefix.hasSuffix(".") ? prefix : prefix + "."
        return ip.hasPrefix(p)
    }

    func dnsMatches(domain: String, suffix: String) -> Bool {
        !domain.isEmpty && !suffix.isEmpty && domain.contains(suffix)
    }

    /// Returns true when a point-to-point VPN tunnel (utun* or ppp*) is active.
    /// When on VPN from home the corporate DNS search domain leaks through the
    /// tunnel, which would otherwise cause a false-positive office detection.
    /// Made `static` so it can be referenced in the default `vpnChecker` closure
    /// without capturing `self`, and so tests can call it directly.
    static func checkVPNActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var addr = ifaddr
        while let current = addr {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            // Require UP + RUNNING so dormant system utun interfaces (e.g. iCloud
            // Private Relay placeholders) don't trigger a false VPN detection.
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isPointToPoint = (flags & IFF_POINTOPOINT) != 0
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("ppp")
            // Also require a non-nil address so unassigned tunnel slots are skipped.
            let hasAddr = ifa.ifa_addr != nil
            if isTunnel && isPointToPoint && isUp && hasAddr {
                return true
            }
            addr = current.pointee.ifa_next
        }
        return false
    }

    private func currentIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var addr = ifaddr
        while let current = addr {
            let ifa = current.pointee
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
            addr = current.pointee.ifa_next
        }
        return nil
    }

    private func currentDNSDomain() -> String? {
        // Read the first DNS search domain via SystemConfiguration
        guard let store = SCDynamicStoreCreate(nil, "OfficeAttendance" as CFString, nil, nil) else {
            return nil
        }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetDNS)
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let domains = dict["SearchDomains"] as? [String] else { return nil }
        return domains.first
    }
}
