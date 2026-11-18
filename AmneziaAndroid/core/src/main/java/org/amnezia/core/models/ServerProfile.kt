package org.amnezia.core.models

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class ServerProfile(
    val id: String = UUID.randomUUID().toString(),
    var name: String = "VPN Server",
    var protocolType: ProtocolType = ProtocolType.AMNEZIA_WG,
    var host: String = "",
    var port: Int = 51820,
    var clientIp: String = "10.0.0.2/32",
    var dnsServers: List<String> = listOf("1.1.1.1", "1.0.0.1"),
    var publicKey: String = "",
    var privateKey: String = "",
    var presharedKey: String? = null,
    var allowedIps: List<String> = listOf("0.0.0.0/0", "::/0"),
    // AmneziaWG Obfuscation parameters
    var jc: Int? = null,
    var jmin: Int? = null,
    var jmax: Int? = null,
    var s1: Int? = null,
    var s2: Int? = null,
    // AWG 2.0: cookie-reply / transport junk sizes
    var s3: Int? = null,
    var s4: Int? = null,
    // Magic headers: a single value ("123") or, since AWG 2.0, a range ("123-456")
    var h1: String? = null,
    var h2: String? = null,
    var h3: String? = null,
    var h4: String? = null,
    // AWG 1.5+/2.0 special junk packets (e.g. "<r 2><b 0x...>")
    var i1: String? = null,
    var i2: String? = null,
    var i3: String? = null,
    var i4: String? = null,
    var i5: String? = null,
    // AWG 3.x interface settings, keyed by their wg-quick names (see AWG3_KEYS), kept verbatim.
    var awg3: Map<String, String>? = null,
    // A number ("25") or, since AWG 3.x, a range ("22-30"). Null means the default of 25 seconds.
    var persistentKeepalive: String? = null,
    var mtu: Int = 1280,
    var pingMs: Long? = null,
    var flagEmoji: String = "🌐",
    var rawConfig: String? = null
) {
    val endpointString: String
        get() = if (host.isNotEmpty()) "$host:$port" else "Not configured"

    val protocol: ProtocolType
        get() = protocolType

    /** AWG 3.x settings in the order of the official config template. */
    val orderedAwg3: List<Pair<String, String>>
        get() = AWG3_KEYS.mapNotNull { key -> awg3?.get(key)?.let { key to it } }

    val persistentKeepaliveValue: String
        get() = persistentKeepalive ?: DEFAULT_PERSISTENT_KEEPALIVE

    companion object {
        /** AWG 3.x interface keys, in the order of the official config template. */
        val AWG3_KEYS = listOf(
            "HeaderProtectionKey",
            "ContentPaddingAddition",
            "RekeyAfterTime",
            "RekeyTimeout",
            "RejectAfterTime",
            "KeepaliveTimeout",
            "MaxHandshakeAttempts",
            "RandomTrailers",
            "DisableCookies",
        )

        const val DEFAULT_PERSISTENT_KEEPALIVE = "25"

        /**
         * Normalises a PersistentKeepalive value: "25" stays "25", " 22 - 30 " becomes "22-30".
         * Anything else (including a reversed range) is null.
         */
        fun parseKeepalive(raw: String?): String? {
            val value = raw?.trim().orEmpty()
            value.toIntOrNull()?.let { return if (it in 0..65535) it.toString() else null }
            val parts = value.split("-").map { it.trim().toIntOrNull() }
            if (parts.size != 2) return null
            val (low, high) = parts
            if (low == null || high == null || low < 0 || high > 65535 || low > high) return null
            return "$low-$high"
        }
    }
}
