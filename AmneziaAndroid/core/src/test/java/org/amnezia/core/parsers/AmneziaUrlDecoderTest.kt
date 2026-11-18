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

    @Test
    fun testDecodeAwg3JsonAndEncodeRoundtrip() {
        // last_config as written by the official client: wg-quick key names, JSON numbers and booleans.
        val lastConfig = org.json.JSONObject()
            .put("client_priv_key", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=")
            .put("server_pub_key", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=")
            .put("client_ip", "10.8.1.10")
            .put("hostName", "203.0.113.10")
            .put("port", 34316)
            .put("Jc", "4")
            .put("H1", "1351553658-1920902942")
            .put("HeaderProtectionKey", "ddddddddddddddddddddddddddddddddddddddddddd=")
            .put("ContentPaddingAddition", "0-64")
            .put("MaxHandshakeAttempts", 18)
            .put("RandomTrailers", true)
            .put("DisableCookies", false)
            .put("persistent_keep_alive", "22-30")
        val root = org.json.JSONObject()
            .put("description", "AWG 3")
            .put("defaultContainer", "amnezia-awg")
            .put("containers", org.json.JSONArray().put(
                org.json.JSONObject()
                    .put("container", "amnezia-awg")
                    .put("awg", org.json.JSONObject().put("last_config", lastConfig.toString()))
            ))

        val profile = AmneziaUrlDecoder.decode(root.toString())
        val awg3 = profile.awg3!!
        assertEquals("ddddddddddddddddddddddddddddddddddddddddddd=", awg3["HeaderProtectionKey"])
        assertEquals("0-64", awg3["ContentPaddingAddition"])
        assertEquals("18", awg3["MaxHandshakeAttempts"])
        assertEquals("true", awg3["RandomTrailers"])
        assertEquals("false", awg3["DisableCookies"])
        assertEquals("22-30", profile.persistentKeepalive)

        // Sharing the profile again (vpn:// export) keeps them too.
        val reimported = AmneziaUrlDecoder.decode(AmneziaUrlDecoder.encodeToUrl(profile))
        assertEquals(awg3, reimported.awg3)
        assertEquals("22-30", reimported.persistentKeepalive)
    }
}
