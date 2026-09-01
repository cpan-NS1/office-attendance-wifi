import Foundation
import Network
import Combine
import SystemConfiguration

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnOfficeNetwork: Bool = false
    @Published private(set) var detectedIP: String = ""
    @Published private(set) var detectedDNS: String = ""

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
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Testable helpers

    func evaluate(path: NWPath, credentials: CredentialStore.Credentials) -> Bool {
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
