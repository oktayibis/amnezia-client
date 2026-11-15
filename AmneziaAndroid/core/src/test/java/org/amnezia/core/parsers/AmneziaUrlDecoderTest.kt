package org.amnezia.core.parsers

import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AmneziaUrlDecoderTest {

    @Test
    fun testDecodeAmneziaJsonAndEncodeRoundtrip() {
        val sampleProfile = ServerProfile(
            name = "Frankfurt AmneziaWG",
            protocolType = ProtocolType.AMNEZIA_WG,
            host = "198.51.100.25",
            port = 51820,
            clientIp = "10.8.0.2/32",
            dnsServers = listOf("1.1.1.1", "1.0.0.1"),
            publicKey = "HIgoByamLBM63vLzGsm53+zR2yv8a0Q9G4v0vXgZ5xU=",
            privateKey = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=",
            presharedKey = "pskSecret1234567890abcdef=",
            allowedIps = listOf("0.0.0.0/0", "::/0"),
            jc = 4,
            jmin = 40,
            jmax = 70,
            s1 = 15,
            s2 = 30,
            h1 = "12345678",
            h2 = "87654321",
            h3 = "11223344",
            h4 = "44332211",
            mtu = 1280
        )

        // Encode to vpn:// URL
        val urlString = AmneziaUrlDecoder.encodeToUrl(sampleProfile)
        assertTrue(urlString.startsWith("vpn://"))

        // Decode from vpn:// URL
        val decodedProfile = AmneziaUrlDecoder.decode(urlString)

        assertEquals(sampleProfile.name, decodedProfile.name)
        assertEquals(ProtocolType.AMNEZIA_WG, decodedProfile.protocolType)
        assertEquals("198.51.100.25", decodedProfile.host)
        assertEquals(51820, decodedProfile.port)
        assertEquals(sampleProfile.privateKey, decodedProfile.privateKey)
        assertEquals(sampleProfile.publicKey, decodedProfile.publicKey)
        assertEquals(sampleProfile.presharedKey, decodedProfile.presharedKey)
        assertEquals("10.8.0.2/32", decodedProfile.clientIp)
        assertEquals(listOf("1.1.1.1", "1.0.0.1"), decodedProfile.dnsServers)
        assertEquals(1280, decodedProfile.mtu)

        // Check AWG Obfuscation parameters
        assertEquals(4, decodedProfile.jc)
        assertEquals(40, decodedProfile.jmin)
        assertEquals(70, decodedProfile.jmax)
        assertEquals(15, decodedProfile.s1)
        assertEquals(30, decodedProfile.s2)
        assertEquals("12345678", decodedProfile.h1)
        assertEquals("87654321", decodedProfile.h2)
        assertEquals("11223344", decodedProfile.h3)
        assertEquals("44332211", decodedProfile.h4)
    }

    @Test
    fun testDecodeRawJsonString() {
        val jsonStr = """
        {
          "containers": [
            {
              "container": "amnezia-wireguard",
              "wireguard": {
                "last_config": "{\"clientPrivKey\":\"AAAA...\",\"serverPubKey\":\"BBBB...\",\"clientIp\":\"10.0.0.5/32\",\"hostName\":\"vpn.example.com\",\"port\":51820}"
              }
            }
          ],
          "description": "Standard WireGuard Server",
          "dns1": "8.8.8.8"
        }
        """.trimIndent()

        val profile = AmneziaUrlDecoder.decode(jsonStr)
        assertEquals("Standard WireGuard Server", profile.name)
        assertEquals(ProtocolType.WIREGUARD, profile.protocolType)
        assertEquals("vpn.example.com", profile.host)
        assertEquals(51820, profile.port)
        assertEquals(listOf("8.8.8.8"), profile.dnsServers)
    }

}
