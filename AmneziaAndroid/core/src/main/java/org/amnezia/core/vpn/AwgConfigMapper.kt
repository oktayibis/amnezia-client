package org.amnezia.core.vpn

import org.amnezia.awg.config.Config
import org.amnezia.awg.config.Interface
import org.amnezia.awg.config.Peer
import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile

/**
 * Maps our [ServerProfile] data model to the native [Config] required by AmneziaWG / WireGuard GoBackend.
 */
object AwgConfigMapper {

    /**
     * Converts a [ServerProfile] into an [org.amnezia.awg.config.Config] instance.
     * Supports both standard WireGuard and AmneziaWG obfuscated profiles.
     *
     * @param profile The server profile imported from QR, link, or .conf
     * @param dnsOverride Optional list of DNS servers to override the profile's DNS
     */
    fun toAwgConfig(profile: ServerProfile, dnsOverride: List<String>? = null): Config {
        val ifaceBuilder = Interface.Builder()

        // Interface: Private key
        if (profile.privateKey.isNotEmpty()) {
            ifaceBuilder.parsePrivateKey(profile.privateKey.trim())
        }

        // Interface: Client address (e.g. "10.0.0.2/32" or multiple separated by comma)
        if (profile.clientIp.isNotEmpty()) {
            ifaceBuilder.parseAddresses(profile.clientIp.trim())
        }

        // Interface: DNS Servers (User override takes precedence)
        val activeDns = dnsOverride?.takeIf { it.isNotEmpty() } ?: profile.dnsServers
        if (activeDns.isNotEmpty()) {
            ifaceBuilder.parseDnsServers(activeDns.joinToString(", "))
        }

        // Interface: MTU
        if (profile.mtu > 0) {
            ifaceBuilder.setMtu(profile.mtu)
        } else {
            ifaceBuilder.setMtu(1280)
        }

        // Interface: AmneziaWG Obfuscation Headers
        if (profile.protocolType == ProtocolType.AMNEZIA_WG) {
            profile.jc?.let { if (it in 0..128) ifaceBuilder.setJunkPacketCount(it) }
            profile.jmin?.let { if (it >= 0) ifaceBuilder.setJunkPacketMinSize(it) }
            profile.jmax?.let { if (it >= 0) ifaceBuilder.setJunkPacketMaxSize(it) }
            profile.s1?.let { if (it >= 0) ifaceBuilder.setInitPacketJunkSize(it) }
            profile.s2?.let { if (it >= 0) ifaceBuilder.setResponsePacketJunkSize(it) }
            // AWG 2.0
            profile.s3?.let { if (it >= 0) ifaceBuilder.setCookieReplyPacketJunkSize(it) }
            profile.s4?.let { if (it >= 0) ifaceBuilder.setTransportPacketJunkSize(it) }
            profile.h1?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseInitPacketMagicHeader(it.trim()) }
            profile.h2?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseResponsePacketMagicHeader(it.trim()) }
            profile.h3?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseUnderloadPacketMagicHeader(it.trim()) }
            profile.h4?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseTransportPacketMagicHeader(it.trim()) }
            profile.i1?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseSpecialJunkI1(it.trim()) }
            profile.i2?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseSpecialJunkI2(it.trim()) }
            profile.i3?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseSpecialJunkI3(it.trim()) }
            profile.i4?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseSpecialJunkI4(it.trim()) }
            profile.i5?.takeIf { it.isNotBlank() }?.let { ifaceBuilder.parseSpecialJunkI5(it.trim()) }
        }

        val iface = ifaceBuilder.build()

        // Peer configuration
        val peerBuilder = Peer.Builder()

        if (profile.publicKey.isNotEmpty()) {
            peerBuilder.parsePublicKey(profile.publicKey.trim())
        }

        if (profile.host.isNotEmpty()) {
            peerBuilder.parseEndpoint("${profile.host}:${profile.port}")
        }

        val allowedIps = if (profile.allowedIps.isNotEmpty()) {
            profile.allowedIps.joinToString(", ")
        } else {
            "0.0.0.0/0, ::/0"
        }
        peerBuilder.parseAllowedIPs(allowedIps)

        peerBuilder.setPersistentKeepalive(25)

        profile.presharedKey?.takeIf { it.isNotBlank() }?.let { psk ->
            peerBuilder.parsePreSharedKey(psk.trim())
        }

        val peer = peerBuilder.build()

        return Config.Builder()
            .setInterface(iface)
            .addPeer(peer)
            .build()
    }
}

/** Extension helper on [ServerProfile] for clean syntax. */
fun ServerProfile.toAwgConfig(dnsOverride: List<String>? = null): Config =
    AwgConfigMapper.toAwgConfig(this, dnsOverride)
