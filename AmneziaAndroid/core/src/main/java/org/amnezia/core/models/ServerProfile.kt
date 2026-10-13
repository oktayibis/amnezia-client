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
    var mtu: Int = 1280,
    var pingMs: Long? = null,
    var flagEmoji: String = "🌐",
    var rawConfig: String? = null
) {
    val endpointString: String
        get() = if (host.isNotEmpty()) "$host:$port" else "Not configured"

    val protocol: ProtocolType
        get() = protocolType
}
