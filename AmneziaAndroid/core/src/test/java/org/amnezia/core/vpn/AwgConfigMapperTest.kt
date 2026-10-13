package org.amnezia.core.vpn

import org.amnezia.awg.config.Interface
import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AwgConfigMapperTest {

    // Valid 32-byte base64 Curve25519 keys
    private val testPrivateKey = "0G8wRjYQy7n4iVz9J8a4x4K3v2u1t0s9r8q7p6o5n4M="
    private val testPublicKey = "YmFzZTY0a2V5dGVzdDEyMzQ1Njc4OTAxMjM0NTY3ODk="

    @Test
    fun mapsWireGuardProfileCorrectly() {
        val profile = ServerProfile(
            name = "Test WG",
            protocolType = ProtocolType.WIREGUARD,
            host = "192.168.1.1",
            port = 51820,
            clientIp = "10.0.0.2/32",
            dnsServers = listOf("1.1.1.1", "8.8.8.8"),
            privateKey = testPrivateKey,
            publicKey = testPublicKey,
            allowedIps = listOf("0.0.0.0/0"),
            mtu = 1420
        )

        val config = profile.toAwgConfig()
        assertNotNull(config)

        val iface = config.`interface`
        assertNotNull(iface)
        assertEquals(1420, iface.mtu.orElse(0))
        assertNotNull(iface.keyPair)

        assertEquals(1, config.peers.size)
        val peer = config.peers[0]
        assertEquals("192.168.1.1:51820", peer.endpoint.orElse(null)?.toString())
        assertEquals(25, peer.persistentKeepalive.orElse(0))
    }

    @Test
    fun mapsAmneziaWgObfuscationParametersCorrectly() {
        val profile = ServerProfile(
            name = "Test AWG",
            protocolType = ProtocolType.AMNEZIA_WG,
            host = "94.138.209.154",
            port = 34316,
            clientIp = "10.8.0.2/32",
            dnsServers = listOf("1.1.1.1"),
            privateKey = testPrivateKey,
            publicKey = testPublicKey,
            allowedIps = listOf("0.0.0.0/0", "::/0"),
            jc = 4,
            jmin = 40,
            jmax = 70,
            s1 = 15,
            s2 = 30,
            h1 = "123456789",
            h2 = "234567890",
            h3 = "345678901",
            h4 = "456789012",
            mtu = 1280
        )

        val config = profile.toAwgConfig(dnsOverride = listOf("8.8.4.4"))
        assertNotNull(config)

        val iface = config.`interface`
        assertEquals(4, iface.junkPacketCount.orElse(0))
        assertEquals(40, iface.junkPacketMinSize.orElse(0))
        assertEquals(70, iface.junkPacketMaxSize.orElse(0))
        assertEquals(15, iface.initPacketJunkSize.orElse(0))
        assertEquals(30, iface.responsePacketJunkSize.orElse(0))
        assertEquals("123456789", iface.initPacketMagicHeader.orElse(null))
        assertEquals("234567890", iface.responsePacketMagicHeader.orElse(null))
        assertEquals("345678901", iface.underloadPacketMagicHeader.orElse(null))
        assertEquals("456789012", iface.transportPacketMagicHeader.orElse(null))
    }

    @Test
    fun mapsAmneziaWg2ParametersCorrectly() {
        val profile = ServerProfile(
            protocolType = ProtocolType.AMNEZIA_WG,
            host = "198.51.100.25",
            privateKey = testPrivateKey,
            publicKey = testPublicKey,
            jc = 4,
            jmin = 10,
            jmax = 50,
            s1 = 115,
            s2 = 36,
            s3 = 37,
            s4 = 9,
            h1 = "1351553658-1920902942",
            h2 = "1985824122-2031951811",
            h3 = "2100088783-2119911158",
            h4 = "2128748706-2129059843",
            i1 = "<r 2><b 0x8580>"
        )

        val iface = profile.toAwgConfig().`interface`
        assertEquals(37, iface.cookieReplyPacketJunkSize.orElse(0))
        assertEquals(9, iface.transportPacketJunkSize.orElse(0))
        assertEquals("1351553658-1920902942", iface.initPacketMagicHeader.orElse(null))
        assertEquals("2128748706-2129059843", iface.transportPacketMagicHeader.orElse(null))
        assertEquals("<r 2><b 0x8580>", iface.specialJunkI1.orElse(null))
        assertTrue(!iface.specialJunkI2.isPresent)
    }
}
