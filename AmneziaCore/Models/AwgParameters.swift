import Foundation

/// Obfuscation parameters for AmneziaWG (AWG) protocol
public struct AwgParameters: Codable, Equatable, Sendable {
    /// Junk packet count (Jc)
    public var jc: UInt16?
    /// Junk packet minimum size (Jmin)
    public var jmin: UInt16?
    /// Junk packet maximum size (Jmax)
    public var jmax: UInt16?
    /// Init packet junk size (S1)
    public var s1: UInt16?
    /// Response packet junk size (S2)
    public var s2: UInt16?
    /// Cookie reply packet junk size (S3)
    public var s3: UInt16?
    /// Transport packet junk size (S4)
    public var s4: UInt16?
    /// Init packet magic header (H1)
    public var h1: String?
    /// Response packet magic header (H2)
    public var h2: String?
    /// Underload packet magic header (H3)
    public var h3: String?
    /// Transport packet magic header (H4)
    public var h4: String?
    
    // Additional junk parameters
    public var i1: String?
    public var i2: String?
    public var i3: String?
    public var i4: String?
    public var i5: String?

    /// AmneziaWG 3.x interface settings, keyed by their wg-quick name (see `awg3Keys`).
    /// Kept as strings and passed through unchanged so the engine sees exactly what the server issued.
    public var awg3: [String: String]?

    /// AmneziaWG 3.x interface keys, in the order the official template writes them.
    public static let awg3Keys = [
        "HeaderProtectionKey", "ContentPaddingAddition",
        "RekeyAfterTime", "RekeyTimeout", "RejectAfterTime", "KeepaliveTimeout",
        "MaxHandshakeAttempts", "RandomTrailers", "DisableCookies"
    ]

    public init(
        jc: UInt16? = nil,
        jmin: UInt16? = nil,
        jmax: UInt16? = nil,
        s1: UInt16? = nil,
        s2: UInt16? = nil,
        s3: UInt16? = nil,
        s4: UInt16? = nil,
        h1: String? = nil,
        h2: String? = nil,
        h3: String? = nil,
        h4: String? = nil,
        i1: String? = nil,
        i2: String? = nil,
        i3: String? = nil,
        i4: String? = nil,
        i5: String? = nil,
        awg3: [String: String]? = nil
    ) {
        self.jc = jc
        self.jmin = jmin
        self.jmax = jmax
        self.s1 = s1
        self.s2 = s2
        self.s3 = s3
        self.s4 = s4
        self.h1 = h1
        self.h2 = h2
        self.h3 = h3
        self.h4 = h4
        self.i1 = i1
        self.i2 = i2
        self.i3 = i3
        self.i4 = i4
        self.i5 = i5
        self.awg3 = (awg3?.isEmpty ?? true) ? nil : awg3
    }

    /// Returns true if at least one AmneziaWG obfuscation parameter is active
    public var hasObfuscation: Bool {
        jc != nil || jmin != nil || jmax != nil ||
        s1 != nil || s2 != nil || s3 != nil || s4 != nil ||
        h1 != nil || h2 != nil || h3 != nil || h4 != nil ||
        i1 != nil || i2 != nil || i3 != nil || i4 != nil || i5 != nil ||
        awg3 != nil
    }

    /// AmneziaWG 3.x settings as ordered wg-quick lines' key/value pairs.
    public var orderedAwg3: [(key: String, value: String)] {
        guard let awg3 else { return [] }
        return Self.awg3Keys.compactMap { key in awg3[key].map { (key, $0) } }
    }

    /// Converts non-nil parameters to wg-quick configuration key-value dictionary
    public var configDictionary: [String: String] {
        var dict = [String: String]()
        if let jc { dict["Jc"] = "\(jc)" }
        if let jmin { dict["Jmin"] = "\(jmin)" }
        if let jmax { dict["Jmax"] = "\(jmax)" }
        if let s1 { dict["S1"] = "\(s1)" }
        if let s2 { dict["S2"] = "\(s2)" }
        if let s3 { dict["S3"] = "\(s3)" }
        if let s4 { dict["S4"] = "\(s4)" }
        if let h1 { dict["H1"] = h1 }
        if let h2 { dict["H2"] = h2 }
        if let h3 { dict["H3"] = h3 }
        if let h4 { dict["H4"] = h4 }
        if let i1 { dict["I1"] = i1 }
        if let i2 { dict["I2"] = i2 }
        if let i3 { dict["I3"] = i3 }
        if let i4 { dict["I4"] = i4 }
        if let i5 { dict["I5"] = i5 }
        for (key, value) in orderedAwg3 { dict[key] = value }
        return dict
    }
}
