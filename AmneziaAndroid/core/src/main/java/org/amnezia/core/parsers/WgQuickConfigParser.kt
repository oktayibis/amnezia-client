package org.amnezia.core.parsers

import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile

object WgQuickConfigParser {

    fun parse(text: String, profileName: String? = null): ServerProfile {
        val interfaceAttrs = mutableMapOf<String, String>()
        val peerAttrs = mutableMapOf<String, String>()

        var currentSection = ""

        text.lines().forEach { line ->
            var trimmed = line.trim()
            // Strip comments
            val commentIdx = trimmed.indexOf('#')
            if (commentIdx != -1) {
                trimmed = trimmed.substring(0, commentIdx).trim()
            }
            if (trimmed.isEmpty()) return@forEach

            val lower = trimmed.lowercase()
            if (lower == "[interface]") {
                currentSection = "interface"
                return@forEach
            } else if (lower == "[peer]") {
                currentSection = "peer"
                return@forEach
            }

            val equalsIdx = trimmed.indexOf('=')
            if (equalsIdx != -1) {
                val key = trimmed.substring(0, equalsIdx).trim().lowercase()
                val value = trimmed.substring(equalsIdx + 1).trim()
                if (currentSection == "interface") {
                    val existing = interfaceAttrs[key]
                    interfaceAttrs[key] = if (existing != null) "$existing,$value" else value
                } else if (currentSection == "peer") {
                    val existing = peerAttrs[key]
                    peerAttrs[key] = if (existing != null) "$existing,$value" else value
                }
            }
        }

        if (interfaceAttrs.isEmpty() || peerAttrs.isEmpty()) {
            throw IllegalArgumentException("Missing [Interface] or [Peer] section in configuration")
        }

        val privateKey = interfaceAttrs["privatekey"]
            ?: throw IllegalArgumentException("Interface is missing PrivateKey")
        val publicKey = peerAttrs["publickey"]
            ?: throw IllegalArgumentException("Peer is missing PublicKey")
        val endpoint = peerAttrs["endpoint"]
            ?: throw IllegalArgumentException("Peer is missing Endpoint")

        val (host, port) = parseEndpoint(endpoint)

        val addresses = interfaceAttrs["address"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: listOf("10.0.0.2/32")
        val dnsList = interfaceAttrs["dns"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: listOf("1.1.1.1", "1.0.0.1")
        val allowedIps = peerAttrs["allowedips"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: listOf("0.0.0.0/0", "::/0")

        val presharedKey = peerAttrs["presharedkey"]
        val mtu = interfaceAttrs["mtu"]?.toIntOrNull() ?: 1280

        // AmneziaWG obfuscation parameters
        val jc = interfaceAttrs["jc"]?.toIntOrNull()
        val jmin = interfaceAttrs["jmin"]?.toIntOrNull()
        val jmax = interfaceAttrs["jmax"]?.toIntOrNull()
        val s1 = interfaceAttrs["s1"]?.toIntOrNull()
        val s2 = interfaceAttrs["s2"]?.toIntOrNull()
        val s3 = interfaceAttrs["s3"]?.toIntOrNull()
        val s4 = interfaceAttrs["s4"]?.toIntOrNull()
        // Kept verbatim: H1..H4 may be ranges ("123-456") and I1..I5 are tag strings in AWG 2.0.
        fun text(key: String) = interfaceAttrs[key]?.trim()?.ifEmpty { null }
        val h1 = text("h1")
        val h2 = text("h2")
        val h3 = text("h3")
        val h4 = text("h4")

        val isAwg = jc != null || jmin != null || jmax != null || s1 != null || s2 != null ||
                h1 != null || h2 != null || h3 != null || h4 != null
        val protocolType = if (isAwg) ProtocolType.AMNEZIA_WG else ProtocolType.WIREGUARD
        val name = profileName ?: "WireGuard ($host)"

        return ServerProfile(
            name = name,
            protocolType = protocolType,
            host = host,
            port = port,
            clientIp = addresses.firstOrNull() ?: "10.0.0.2/32",
            dnsServers = dnsList,
            publicKey = publicKey,
            privateKey = privateKey,
            presharedKey = presharedKey,
            allowedIps = allowedIps,
            jc = jc,
            jmin = jmin,
            jmax = jmax,
            s1 = s1,
            s2 = s2,
            s3 = s3,
            s4 = s4,
            h1 = h1,
            h2 = h2,
            h3 = h3,
            h4 = h4,
            i1 = text("i1"),
            i2 = text("i2"),
            i3 = text("i3"),
            i4 = text("i4"),
            i5 = text("i5"),
            mtu = mtu
        )
    }

    private fun parseEndpoint(endpoint: String): Pair<String, Int> {
        val trimmed = endpoint.trim()
        if (trimmed.startsWith("[")) {
            // IPv6 [2001:db8::1]:51820
            val closing = trimmed.indexOf(']')
            if (closing != -1 && closing + 1 < trimmed.length && trimmed[closing + 1] == ':') {
                val host = trimmed.substring(1, closing)
                val port = trimmed.substring(closing + 2).toIntOrNull() ?: 51820
                return Pair(host, port)
            }
        }
        val colonIdx = trimmed.lastIndexOf(':')
        if (colonIdx != -1) {
            val host = trimmed.substring(0, colonIdx)
            val port = trimmed.substring(colonIdx + 1).toIntOrNull() ?: 51820
            return Pair(host, port)
        }
        return Pair(trimmed, 51820)
    }

    fun serialize(profile: ServerProfile): String {
        val sb = StringBuilder()
        sb.appendLine("[Interface]")
        sb.appendLine("PrivateKey = ${profile.privateKey}")
        sb.appendLine("Address = ${profile.clientIp}")
        if (profile.dnsServers.isNotEmpty()) {
            sb.appendLine("DNS = ${profile.dnsServers.joinToString(", ")}")
        }
        if (profile.mtu > 0) {
            sb.appendLine("MTU = ${profile.mtu}")
        }
        profile.jc?.let { sb.appendLine("Jc = $it") }
        profile.jmin?.let { sb.appendLine("Jmin = $it") }
        profile.jmax?.let { sb.appendLine("Jmax = $it") }
        profile.s1?.let { sb.appendLine("S1 = $it") }
        profile.s2?.let { sb.appendLine("S2 = $it") }
        profile.s3?.let { sb.appendLine("S3 = $it") }
        profile.s4?.let { sb.appendLine("S4 = $it") }
        profile.h1?.let { sb.appendLine("H1 = $it") }
        profile.h2?.let { sb.appendLine("H2 = $it") }
        profile.h3?.let { sb.appendLine("H3 = $it") }
        profile.h4?.let { sb.appendLine("H4 = $it") }
        profile.i1?.let { sb.appendLine("I1 = $it") }
        profile.i2?.let { sb.appendLine("I2 = $it") }
        profile.i3?.let { sb.appendLine("I3 = $it") }
        profile.i4?.let { sb.appendLine("I4 = $it") }
        profile.i5?.let { sb.appendLine("I5 = $it") }

        sb.appendLine()
        sb.appendLine("[Peer]")
        sb.appendLine("PublicKey = ${profile.publicKey}")
        profile.presharedKey?.let { sb.appendLine("PresharedKey = $it") }
        sb.appendLine("Endpoint = ${profile.host}:${profile.port}")
        sb.appendLine("AllowedIPs = ${profile.allowedIps.joinToString(", ")}")
        sb.appendLine("PersistentKeepalive = 25")
        return sb.toString()
    }
}
