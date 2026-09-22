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
    private var dynamicStore: SCDynamicStore?
    private let queue = DispatchQueue(label: "com.ibm.office-attendance.network")
    private var credentials: CredentialStore.Credentials?

    func start(credentials: CredentialStore.Credentials) {
        self.credentials = credentials

        // NWPathMonitor fires on WiFi/interface changes.
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] _ in
            self?.reevaluate()
        }
        m.start(queue: queue)
        monitor = m

        // SCDynamicStore fires on VPN connect/disconnect (and DNS changes),
        // which NWPathMonitor misses because the underlying en0 path is unchanged.
        startDynamicStoreMonitor()

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

    private func reevaluate() {
        guard let creds = credentials else { return }
        DispatchQueue.main.async { [weak self] in
            self?.evaluateAndPublishCurrentNetwork(credentials: creds)
        }
    }

    /// Watches DNS and interface-list changes via SCDynamicStore so that VPN
    /// connect/disconnect events (which NWPathMonitor does not surface) trigger
    /// a re-evaluation.
    private func startDynamicStoreMonitor() {
        let keys = [
            "State:/Network/Global/DNS",
            "State:/Network/Interface",
        ] as CFArray

        var ctx = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil, "OfficeAttendance.VPNWatch" as CFString,
            { _, _, info in
                guard let info else { return }
                let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.reevaluate()
            },
            &ctx
        ) else { return }

        SCDynamicStoreSetNotificationKeys(store, keys, nil)
        let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        dynamicStore = store
    }

    private func evaluateAndPublishCurrentNetwork(credentials: CredentialStore.Credentials) {
        let ip = currentIPAddress() ?? ""
        let dns = currentDNSDomain() ?? ""
        let vpn = vpnChecker()
        let result = isOnOfficeNetwork(ip: ip, dns: dns, vpnActive: vpn, credentials: credentials)
        detectedIP = ip
        detectedDNS = dns
        isVPNActive = vpn
        isOnOfficeNetwork = result
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        dynamicStore = nil   // source is removed when the store is deallocated
    }

    // MARK: - Testable helpers

    func evaluate(path: NWPath, credentials: CredentialStore.Credentials) -> Bool {
        let ip = currentIPAddress() ?? ""
        let dns = currentDNSDomain() ?? ""
        return isOnOfficeNetwork(ip: ip, dns: dns, vpnActive: vpnChecker(), credentials: credentials)
    }

    /// Core office-network decision, fully testable without live syscalls.
    ///
    /// Rule: BOTH IP prefix AND DNS domain must match, AND no VPN must be active.
    ///
    /// A single signal is not sufficient because:
    /// - IP alone: a home router or mobile hotspot could fall in a matching range.
    /// - DNS alone: VPN tunnels inject the corporate search domain (e.g. ibm.com)
    ///   even when the physical network is a home broadband or mobile hotspot.
    /// - VPN active: suppress entirely — the machine is logically remote even if
    ///   the IP/DNS happen to match (e.g. split-tunnel from home on corp subnet).
    func isOnOfficeNetwork(ip: String, dns: String, vpnActive: Bool,
                           credentials: CredentialStore.Credentials) -> Bool {
        guard !vpnActive else { return false }
        return ipMatches(ip: ip, prefix: credentials.ipPrefix)
            && dnsMatches(domain: dns, suffix: credentials.dnsDomain)
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

    /// Returns true when a real VPN tunnel (utun* or ppp*) carrying a routable
    /// IPv4 address is active.
    ///
    /// macOS always has several utun interfaces (utun0–utun5) for system services
    /// like mDNS, Wireguard, and Private Relay — all UP+RUNNING+POINTOPOINT but
    /// with only IPv6 link-local addresses. A VPN client (Cisco AnyConnect, etc.)
    /// assigns an IPv4 address to its tunnel. Requiring AF_INET ensures we only
    /// match real VPN tunnels, not the always-present system ones.
    ///
    /// Loopback (127.x.x.x) and APIPA (169.254.x.x) addresses are excluded —
    /// local proxies, VMs, and some system daemons may bind a utun interface to
    /// those ranges, which must not be treated as an active VPN.
    static func checkVPNActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var addr = ifaddr
        while let current = addr {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isPointToPoint = (flags & IFF_POINTOPOINT) != 0
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("ppp")
            // Only count interfaces that carry a routable IPv4 address — system
            // utun interfaces only have IPv6 link-local addresses and must be
            // excluded, as must loopback and APIPA ranges.
            let hasRoutableIPv4: Bool = {
                guard ifa.ifa_addr != nil,
                      ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { return false }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                return !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.")
            }()
            if isTunnel && isPointToPoint && isUp && hasRoutableIPv4 {
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
