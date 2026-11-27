import Foundation
import Network

/// Measures round-trip latency as the time to complete a TCP handshake (one RTT).
///
/// ICMP needs raw sockets that iOS apps and sandboxed macOS apps cannot open, so a TCP
/// connect is the reliable "ping". While the VPN is up the probe is routed through the
/// tunnel, so the result reflects latency via the VPN server.
public enum LatencyProbe {
    public struct Target: Sendable, Equatable {
        public let host: String
        public let port: UInt16
        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }

    /// Well-known anycast resolvers that accept TCP on 443 and 53.
    public static let defaultTargets: [Target] = [
        Target(host: "1.1.1.1", port: 443),
        Target(host: "8.8.8.8", port: 443),
        Target(host: "1.1.1.1", port: 53)
    ]

    /// Returns the latency in milliseconds of the first target that answers, or nil.
    public static func measure(targets: [Target] = defaultTargets, timeout: TimeInterval = 3) async -> Int? {
        for target in targets {
            if let ms = await measure(target, timeout: timeout) {
                return ms
            }
        }
        return nil
    }

    public static func measure(_ target: Target, timeout: TimeInterval) async -> Int? {
        guard let port = NWEndpoint.Port(rawValue: target.port) else { return nil }
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = max(1, Int(timeout.rounded(.up)))
            tcp.noDelay = true
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: params)
        let queue = DispatchQueue(label: "com.oktayibis.awgconnect.latency")

        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let lock = NSLock()
            var finished = false
            let start = DispatchTime.now()

            func finish(_ value: Int?) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(max(1, Int(elapsed / 1_000_000)))
                case .failed, .cancelled:
                    finish(nil)
                case .waiting:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
